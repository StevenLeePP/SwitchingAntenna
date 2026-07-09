/*
 * type1_yunsdr_rx_mex.c — Background 122.88 MS/s four-channel ring-buffer RX
 *
 * Architecture:
 *   A dedicated pthread continuously reads four 122.88 MS/s channels from
 *   the YunSDR via yunsdr_read_samples_multiport into a circular buffer.
 *   MATLAB's foreground thread takes periodic "snapshots" without blocking
 *   the hardware read loop, avoiding RX overflow.
 *
 * Commands (first argument is always a string):
 *   open   <dev> <fs> <LO_Hz> <gain>   — open device, configure 2 RF chips
 *   start  <block_samples> <ring_blk>  — launch background RX thread
 *   snapshot <n_blocks>                 — copy n blocks from ring, return IQ
 *   status                              — [sequence, stored, running, ret]
 *   stop                                — stop thread, free ring
 *   events                              — [4x3] overflow/count/timeout
 *   timestamp                           — read current hardware timestamp
 *   hwdepth [value]                     — get/set hardware buffer depth
 *   close                               — stop + close device
 *
 * Ring buffer layout (int16 interleaved I/Q):
 *   ring_iq[(slot*4 + ch) * block_samples*2 + sample]
 *   where slot = sequence % ring_blocks, ch = 0..3
 *   Each complex sample = 2 consecutive int16 values (I, Q).
 *
 * Snapshot copies the most recent take_blocks blocks while the mutex is
 * held only for the sequence read (not during the copy), so the hardware
 * thread can continue writing to slots outside the snapshot window.
 */

#include "mex.h"
#include "matrix.h"
#include "yunsdr_api_ss.h"

#include <stdint.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/* ── Global device and ring-buffer state ── */
static YUNSDR_DESCRIPTOR *g_device = NULL;
static pthread_t g_rx_thread;
static pthread_mutex_t g_ring_mutex = PTHREAD_MUTEX_INITIALIZER;
static volatile int g_thread_running = 0;
static int g_thread_created = 0;
static uint32_t g_block_samples = 0;    /* samples per block (e.g. 122880)  */
static uint32_t g_ring_blocks = 0;      /* number of blocks in ring (e.g. 64) */
static int16_t *g_ring_iq = NULL;       /* ring: [ring_blocks * 4 * 2 * block_samples] */
static uint64_t *g_ring_timestamp = NULL; /* timestamp per block */
static uint64_t g_sequence = 0;         /* total blocks received */
static int32_t g_last_read_ret = 0;     /* return code of last hardware read */

/* ── Stop background RX thread and free ring resources ── */
static void stop_stream(void)
{
    if (g_thread_created) {
        g_thread_running = 0;
        pthread_join(g_rx_thread, NULL);
        g_thread_created = 0;
    }
    free(g_ring_iq);
    free(g_ring_timestamp);
    g_ring_iq = NULL;
    g_ring_timestamp = NULL;
    g_block_samples = 0;
    g_ring_blocks = 0;
    g_sequence = 0;
    g_last_read_ret = 0;
}

/* ── Close device (stop stream first, then release hardware) ── */
static void close_device(void)
{
    stop_stream();
    if (g_device != NULL) {
        yunsdr_close_device(g_device);
        g_device = NULL;
        if (mexIsLocked())
            mexUnlock();
    }
}

/* ── Background RX worker thread ──
 *   Loops on yunsdr_read_samples_multiport, writes each block into
 *   the ring buffer at position (sequence % ring_blocks).
 *   The mutex protects only the sequence increment and ring write,
 *   so the snapshot path can read historical blocks without blocking
 *   the hardware thread for the duration of the copy. ── */
static void *rx_worker(void *unused)
{
    int16_t *buffers[4] = {NULL, NULL, NULL, NULL};
    uint64_t timestamp;
    uint64_t sequence;
    size_t channel_bytes;
    size_t channel_samples;
    size_t destination_offset;
    int32_t ret;
    int ch;

    (void)unused;

    /* One block = block_samples complex -> 2*block_samples int16 values */
    channel_samples = (size_t)g_block_samples * 2;
    channel_bytes = channel_samples * sizeof(int16_t);

    /* Per-channel temporary read buffers */
    for (ch = 0; ch < 4; ++ch) {
        buffers[ch] = (int16_t *)malloc(channel_bytes);
        if (buffers[ch] == NULL) {
            g_last_read_ret = -12;       /* ENOMEM */
            g_thread_running = 0;
            goto done;
        }
    }

    while (g_thread_running) {
        timestamp = 0;
        /* Blocking read: 4 channels, block_samples per channel, mask 0x0f */
        ret = yunsdr_read_samples_multiport(
            g_device, (void **)buffers, g_block_samples, 0x0f, &timestamp);
        g_last_read_ret = ret;
        if (ret < 0) {
            g_thread_running = 0;
            break;
        }

        /* Write each channel's data into the ring at the current slot */
        pthread_mutex_lock(&g_ring_mutex);
        sequence = g_sequence;
        for (ch = 0; ch < 4; ++ch) {
            destination_offset =
                (((size_t)(sequence % g_ring_blocks) * 4 + ch) *
                 channel_samples);
            memcpy(g_ring_iq + destination_offset, buffers[ch], channel_bytes);
        }
        g_ring_timestamp[sequence % g_ring_blocks] = timestamp;
        g_sequence = sequence + 1;
        pthread_mutex_unlock(&g_ring_mutex);
    }

done:
    for (ch = 0; ch < 4; ++ch)
        free(buffers[ch]);
    return NULL;
}

/* ── Helper: assert device is open ── */
static void require_device(void)
{
    if (g_device == NULL)
        mexErrMsgIdAndTxt("nr4:mex:NotOpen",
                          "Open the YunSDR device before this command.");
}

/* ── Helper: safe scalar conversions ── */
static uint32_t scalar_u32(const mxArray *value, const char *name)
{
    double x = mxGetScalar(value);
    if (x < 0.0 || x > 4294967295.0)
        mexErrMsgIdAndTxt("nr4:mex:Range", "%s is out of range.", name);
    return (uint32_t)x;
}

static uint64_t scalar_u64(const mxArray *value, const char *name)
{
    double x = mxGetScalar(value);
    if (x < 0.0)
        mexErrMsgIdAndTxt("nr4:mex:Range", "%s is out of range.", name);
    return (uint64_t)x;
}

static mxArray *make_u64(uint64_t value)
{
    mxArray *out = mxCreateNumericMatrix(1, 1, mxUINT64_CLASS, mxREAL);
    *((uint64_t *)mxGetData(out)) = value;
    return out;
}

static void check_ret(int32_t ret, const char *operation)
{
    if (ret < 0)
        mexErrMsgIdAndTxt("nr4:mex:YunSDR", "%s failed with %d.",
                          operation, ret);
}

/* ═══════════════════════════════════════════════════════════════
 *  command_open: initialise the YunSDR device
 *    - Configures 2 RF chips (each drives 2 RX channels)
 *    - Sets sample rate, LO, bandwidth, gain per chip
 *    - Enables hardware timestamp for sample-accurate timing
 * ═══════════════════════════════════════════════════════════════ */
static void command_open(int nlhs, mxArray **plhs, int nrhs,
                         const mxArray **prhs)
{
    char *device_string;
    uint32_t sample_rate;
    uint64_t center_frequency;
    uint32_t gain;
    int rf;

    if (nrhs != 5)
        mexErrMsgIdAndTxt("nr4:mex:OpenArgs",
                          "open requires device, sample rate, LO and gain.");
    close_device();  /* close any previously opened device first */

    device_string = mxArrayToString(prhs[1]);
    if (device_string == NULL)
        mexErrMsgIdAndTxt("nr4:mex:String", "Invalid device string.");
    sample_rate = scalar_u32(prhs[2], "sample rate");
    center_frequency = scalar_u64(prhs[3], "center frequency");
    gain = scalar_u32(prhs[4], "gain");

    g_device = yunsdr_open_device(device_string);
    mxFree(device_string);
    if (g_device == NULL)
        mexErrMsgIdAndTxt("nr4:mex:Open", "Could not open YunSDR.");
    mexLock();
    mexAtExit(close_device);  /* auto-cleanup on MEX clear or MATLAB exit */

    /* Two RF chips, each handles 2 RX channels */
    for (rf = 0; rf < 2; ++rf) {
        check_ret(yunsdr_set_rx_sampling_freq(g_device, (uint8_t)rf,
                                               sample_rate),
                  "set RX sample rate");
        check_ret(yunsdr_set_rx_lo_freq(g_device, (uint8_t)rf,
                                        center_frequency),
                  "set RX LO");
        check_ret(yunsdr_set_rx_rf_bandwidth(g_device, (uint8_t)rf,
                                             sample_rate),
                  "set RX bandwidth");
        check_ret(yunsdr_set_rx1_rf_gain(g_device, (uint8_t)rf, gain),
                  "set RX1 gain");
        check_ret(yunsdr_set_rx2_rf_gain(g_device, (uint8_t)rf, gain),
                  "set RX2 gain");
    }
    /* Toggle timestamp to reset and enable */
    check_ret(yunsdr_enable_timestamp(g_device, 0, 0), "disable timestamp");
    check_ret(yunsdr_enable_timestamp(g_device, 0, 1), "enable timestamp");

    if (nlhs > 0)
        plhs[0] = mxCreateLogicalScalar(true);
}

/* ═══════════════════════════════════════════════════════════════
 *  command_read: synchronous four-channel read (debug only)
 *    Not used during live operation; blocks until data arrives.
 *    Returns [Nx4 single] IQ, normalised to [-1, +1] from int16.
 * ═══════════════════════════════════════════════════════════════ */
static void command_read(int nlhs, mxArray **plhs, int nrhs,
                         const mxArray **prhs)
{
    uint32_t count;
    uint32_t channel_mask = 0x0f;
    uint64_t timestamp = 0;
    int16_t *buffers[4] = {NULL, NULL, NULL, NULL};
    mwSize dimensions[2];
    mxComplexSingle *output;
    int32_t ret;
    uint32_t n;
    int ch;

    require_device();
    if (g_thread_created)
        mexErrMsgIdAndTxt("nr4:mex:Streaming",
                          "Stop the background stream before sync read.");
    if (nrhs < 2 || nrhs > 3)
        mexErrMsgIdAndTxt("nr4:mex:ReadArgs",
                          "read requires count and optional channel mask.");
    count = scalar_u32(prhs[1], "sample count");
    if (nrhs == 3)
        channel_mask = scalar_u32(prhs[2], "channel mask");
    if (channel_mask != 0x0f)
        mexErrMsgIdAndTxt("nr4:mex:Mask",
                          "This receiver requires channel mask 0x0f.");

    for (ch = 0; ch < 4; ++ch) {
        buffers[ch] = (int16_t *)mxMalloc((size_t)count * 2 * sizeof(int16_t));
        if (buffers[ch] == NULL)
            mexErrMsgIdAndTxt("nr4:mex:Memory",
                              "Could not allocate RX work buffer.");
    }

    ret = yunsdr_read_samples_multiport(g_device, (void **)buffers,
                                        count, (uint8_t)channel_mask,
                                        &timestamp);
    if (ret < 0) {
        for (ch = 0; ch < 4; ++ch) mxFree(buffers[ch]);
        mexErrMsgIdAndTxt("nr4:mex:Read",
                          "YunSDR memory read failed with %d.", ret);
    }

    /* Convert interleaved int16 I/Q -> complex single, scale by 1/32768 */
    dimensions[0] = (mwSize)ret;
    dimensions[1] = 4;
    plhs[0] = mxCreateNumericArray(2, dimensions, mxSINGLE_CLASS, mxCOMPLEX);
    output = mxGetComplexSingles(plhs[0]);
    for (ch = 0; ch < 4; ++ch) {
        for (n = 0; n < (uint32_t)ret; ++n) {
            output[n + (size_t)ch * ret].real =
                (float)buffers[ch][2*n] / 32768.0f;
            output[n + (size_t)ch * ret].imag =
                (float)buffers[ch][2*n + 1] / 32768.0f;
        }
        mxFree(buffers[ch]);
    }

    if (nlhs > 1) plhs[1] = make_u64(timestamp);
    if (nlhs > 2) plhs[2] = mxCreateDoubleScalar((double)ret);
}

/* ═══════════════════════════════════════════════════════════════
 *  command_start: allocate ring and launch background RX thread
 *    Ring size = ring_blocks * 4 channels * 2 (I/Q) * block_samples
 *    e.g. 64 * 4 * 2 * 122880 = ~62.9 million int16 = ~126 MB
 * ═══════════════════════════════════════════════════════════════ */
static void command_start(int nrhs, const mxArray **prhs)
{
    size_t total_values;
    int create_ret;

    require_device();
    if (nrhs != 3)
        mexErrMsgIdAndTxt("nr4:mex:StartArgs",
                          "start requires block samples and ring blocks.");
    stop_stream();  /* free any previous ring */
    g_block_samples = scalar_u32(prhs[1], "block samples");
    g_ring_blocks = scalar_u32(prhs[2], "ring blocks");
    if (g_block_samples == 0 || g_ring_blocks < 2)
        mexErrMsgIdAndTxt("nr4:mex:StartRange",
                          "Invalid block or ring size.");

    total_values = (size_t)g_ring_blocks * 4 * 2 * g_block_samples;
    g_ring_iq = (int16_t *)calloc(total_values, sizeof(int16_t));
    g_ring_timestamp = (uint64_t *)calloc(g_ring_blocks, sizeof(uint64_t));
    if (g_ring_iq == NULL || g_ring_timestamp == NULL) {
        stop_stream();
        mexErrMsgIdAndTxt("nr4:mex:Memory",
                          "Could not allocate the RX ring.");
    }

    g_sequence = 0;
    g_last_read_ret = 0;
    g_thread_running = 1;
    create_ret = pthread_create(&g_rx_thread, NULL, rx_worker, NULL);
    if (create_ret != 0) {
        g_thread_running = 0;
        stop_stream();
        mexErrMsgIdAndTxt("nr4:mex:Thread",
                          "Could not create RX thread (%d).", create_ret);
    }
    g_thread_created = 1;
}

/* ═══════════════════════════════════════════════════════════════
 *  command_snapshot: copy the most recent take_blocks from ring
 *    The mutex is held only to read the current sequence number.
 *    The actual copy reads from historical ring slots that are
 *    at least (ring_blocks - take_blocks) behind the writer,
 *    guaranteeing they won't be overwritten during the copy.
 * ═══════════════════════════════════════════════════════════════ */
static void command_snapshot(int nlhs, mxArray **plhs, int nrhs,
                             const mxArray **prhs)
{
    uint32_t requested_blocks;
    uint64_t sequence;
    uint64_t first_sequence;
    uint32_t stored_blocks;
    uint32_t take_blocks;
    mwSize dimensions[2];
    mxComplexSingle *output;
    uint64_t *timestamps;
    uint64_t *timestamp_copy;
    int16_t *iq_copy;
    size_t channel_samples;
    size_t channel_bytes;
    size_t copy_offset;
    size_t source_offset;
    size_t output_row;
    uint32_t block;
    uint32_t n;
    int ch;

    require_device();
    if (!g_thread_created)
        mexErrMsgIdAndTxt("nr4:mex:NotStreaming",
                          "Start the background stream first.");
    if (nrhs != 2)
        mexErrMsgIdAndTxt("nr4:mex:SnapshotArgs",
                          "snapshot requires a block count.");
    requested_blocks = scalar_u32(prhs[1], "snapshot blocks");
    channel_samples = (size_t)g_block_samples * 2;
    channel_bytes = channel_samples * sizeof(int16_t);

    /* Allocate temporary copy buffers */
    iq_copy = (int16_t *)mxMalloc(
        (size_t)requested_blocks * 4 * channel_bytes);
    timestamp_copy = (uint64_t *)mxMalloc(
        (size_t)requested_blocks * sizeof(uint64_t));
    if (iq_copy == NULL || timestamp_copy == NULL) {
        mxFree(iq_copy);
        mxFree(timestamp_copy);
        mexErrMsgIdAndTxt("nr4:mex:Memory",
                          "Could not allocate snapshot work memory.");
    }

    /*
     * Freeze only the producer sequence under the mutex. The selected
     * slots are historical: with a 64-block ring and a 20-block snapshot,
     * the producer is still 44 blocks away from overwriting the oldest
     * selected slot. Copying ~39 MB while holding this mutex used to
     * block hardware reads for tens of milliseconds and cause RX overflow.
     */
    pthread_mutex_lock(&g_ring_mutex);
    sequence = g_sequence;
    stored_blocks = (uint32_t)((sequence < g_ring_blocks) ?
                               sequence : g_ring_blocks);
    take_blocks = (requested_blocks < stored_blocks) ?
                  requested_blocks : stored_blocks;
    first_sequence = sequence - take_blocks;
    pthread_mutex_unlock(&g_ring_mutex);

    /* Copy data from ring slots [first_sequence .. sequence-1] */
    for (block = 0; block < take_blocks; ++block) {
        uint64_t block_sequence = first_sequence + block;
        uint32_t slot = (uint32_t)(block_sequence % g_ring_blocks);
        timestamp_copy[block] = g_ring_timestamp[slot];
        for (ch = 0; ch < 4; ++ch) {
            source_offset = (((size_t)slot * 4 + ch) * channel_samples);
            copy_offset = (((size_t)block * 4 + ch) * channel_samples);
            memcpy(iq_copy + copy_offset, g_ring_iq + source_offset,
                   channel_bytes);
        }
    }

    /* Build output array: [take_blocks * block_samples x 4] complex single */
    dimensions[0] = (mwSize)take_blocks * g_block_samples;
    dimensions[1] = 4;
    plhs[0] = mxCreateNumericArray(2, dimensions, mxSINGLE_CLASS, mxCOMPLEX);
    output = mxGetComplexSingles(plhs[0]);
    if (nlhs > 1) {
        plhs[1] = mxCreateNumericMatrix(take_blocks, 1, mxUINT64_CLASS, mxREAL);
        timestamps = (uint64_t *)mxGetData(plhs[1]);
        memcpy(timestamps, timestamp_copy,
               (size_t)take_blocks * sizeof(uint64_t));
    }

    /* Convert int16 interleaved I/Q -> complex single, scale by 1/32768 */
    for (block = 0; block < take_blocks; ++block) {
        for (ch = 0; ch < 4; ++ch) {
            copy_offset = (((size_t)block * 4 + ch) * channel_samples);
            for (n = 0; n < g_block_samples; ++n) {
                output_row = (size_t)block * g_block_samples + n;
                output[output_row + (size_t)ch * dimensions[0]].real =
                    (float)iq_copy[copy_offset + 2*n] / 32768.0f;
                output[output_row + (size_t)ch * dimensions[0]].imag =
                    (float)iq_copy[copy_offset + 2*n + 1] / 32768.0f;
            }
        }
    }
    mxFree(iq_copy);
    mxFree(timestamp_copy);

    if (nlhs > 2)
        plhs[2] = make_u64(sequence);
}

/* ═══════════════════════════════════════════════════════════════
 *  command_status: return [sequence, stored_blocks, running, last_ret]
 *    Non-blocking; used by MATLAB to wait for ring fill.
 * ═══════════════════════════════════════════════════════════════ */
static void command_status(int nlhs, mxArray **plhs)
{
    double *values;
    uint64_t sequence;
    uint32_t stored_blocks;

    pthread_mutex_lock(&g_ring_mutex);
    sequence = g_sequence;
    stored_blocks = (uint32_t)((sequence < g_ring_blocks) ?
                               sequence : g_ring_blocks);
    pthread_mutex_unlock(&g_ring_mutex);

    if (nlhs > 0) {
        plhs[0] = mxCreateDoubleMatrix(1, 4, mxREAL);
        values = mxGetDoubles(plhs[0]);
        values[0] = (double)sequence;
        values[1] = (double)stored_blocks;
        values[2] = (double)g_thread_running;
        values[3] = (double)g_last_read_ret;
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  command_events: read per-channel overflow, count, and timeout.
 *    Returns [4x3] double matrix; used for post-capture diagnostics.
 * ═══════════════════════════════════════════════════════════════ */
static void command_events(int nlhs, mxArray **plhs)
{
    double *out;
    uint32_t count;
    int ch;

    require_device();
    plhs[0] = mxCreateDoubleMatrix(4, 3, mxREAL);
    out = mxGetDoubles(plhs[0]);
    for (ch = 0; ch < 4; ++ch) {
        check_ret(yunsdr_get_channel_event(g_device, RX_CHANNEL_OVERFLOW,
                                           (uint8_t)(ch + 1), &count),
                  "read RX overflow");
        out[ch] = (double)count;       /* column 1: overflow */
        check_ret(yunsdr_get_channel_event(g_device, RX_CHANNEL_COUNT,
                                           (uint8_t)(ch + 1), &count),
                  "read RX count");
        out[ch + 4] = (double)count;   /* column 2: sample count */
        check_ret(yunsdr_get_channel_event(g_device, RX_CHANNEL_TIMEOUT,
                                           (uint8_t)(ch + 1), &count),
                  "read RX timeout");
        out[ch + 8] = (double)count;   /* column 3: timeout count */
    }
    (void)nlhs;
}

static void command_timestamp(int nlhs, mxArray **plhs)
{
    uint64_t timestamp = 0;
    require_device();
    check_ret(yunsdr_read_timestamp(g_device, 0, &timestamp),
              "read timestamp");
    if (nlhs > 0)
        plhs[0] = make_u64(timestamp);
}

static void command_hwdepth(int nlhs, mxArray **plhs, int nrhs,
                            const mxArray **prhs)
{
    uint32_t depth = 0;
    require_device();
    if (nrhs == 2) {  /* set + get */
        depth = scalar_u32(prhs[1], "hardware buffer depth");
        check_ret(yunsdr_set_hwbuf_depth(g_device, 0, depth),
                  "set hardware buffer depth");
    } else if (nrhs != 1) {
        mexErrMsgIdAndTxt("nr4:mex:DepthArgs",
                          "hwdepth accepts zero or one value.");
    }
    check_ret(yunsdr_get_hwbuf_depth(g_device, 0, &depth),
              "get hardware buffer depth");
    if (nlhs > 0)
        plhs[0] = mxCreateDoubleScalar((double)depth);
}

/* ═══════════════════════════════════════════════════════════════
 *  mexFunction: command dispatcher
 * ═══════════════════════════════════════════════════════════════ */
void mexFunction(int nlhs, mxArray **plhs, int nrhs, const mxArray **prhs)
{
    char command[32];

    if (nrhs < 1 || !mxIsChar(prhs[0]))
        mexErrMsgIdAndTxt("nr4:mex:Command",
                          "The first input must be a command.");
    if (mxGetString(prhs[0], command, sizeof(command)) != 0)
        mexErrMsgIdAndTxt("nr4:mex:Command", "Command is too long.");

    if (strcmp(command, "open") == 0) {
        command_open(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "read") == 0) {
        command_read(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "start") == 0) {
        command_start(nrhs, prhs);
    } else if (strcmp(command, "snapshot") == 0) {
        command_snapshot(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "status") == 0) {
        command_status(nlhs, plhs);
    } else if (strcmp(command, "stop") == 0) {
        stop_stream();
    } else if (strcmp(command, "events") == 0) {
        command_events(nlhs, plhs);
    } else if (strcmp(command, "timestamp") == 0) {
        command_timestamp(nlhs, plhs);
    } else if (strcmp(command, "hwdepth") == 0) {
        command_hwdepth(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "close") == 0) {
        close_device();
    } else {
        mexErrMsgIdAndTxt("nr4:mex:Command", "Unknown command: %s.", command);
    }
}
