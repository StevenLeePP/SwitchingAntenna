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
 *   snapshot <n_blocks>                 — copy n raw 122.88 MS/s blocks
 *   snapshotvirtual <n_blocks>          — C-side switch + return virtual30 IQ
 *   ofdmgrid <iq> <cp> <cfo> <period> [window] — offline C OFDM test grid
 *   fifostart / fifostop                — enable/disable ordered FIFO mode
 *   dequeuevirtual <n_blocks>           — consume oldest virtual30 blocks
 *   fifostatus                           — producer/consumer/depth/drop stats
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
#include <stddef.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

#define TYPE1_NFFT 1024u
#define TYPE1_ACTIVE_SC 612u
#define TYPE1_VIRTUAL_FS 30720000.0f
#define TYPE1_PI 3.14159265358979323846f

typedef struct {
    float real;
    float imag;
} type1_cf;

static uint32_t scalar_u32(const mxArray *value, const char *name);
static uint64_t scalar_u64(const mxArray *value, const char *name);
static mxArray *make_u64(uint64_t value);

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
/* FIFO mode retains unread blocks. If the decoder falls behind, new input
 * is explicitly dropped and counted rather than silently overwriting data
 * that has already been handed to the consumer. */
static int g_fifo_mode = 0;
static uint64_t g_consumer_sequence = 0;
static uint64_t g_fifo_dropped_new = 0;
static uint64_t g_fifo_high_water = 0;

/* Direct-benchmark state.  This is the first persistent-consumer stage: it
 * deliberately performs native-ring switch extraction and all required
 * slot-0:10 FFTs without creating any MATLAB IQ/grid array.  PHY decoding is
 * added only after this stage demonstrates queue headroom. */
static int g_direct_bench_mode = 0;
static uint64_t g_direct_bench_frames = 0;
static double g_direct_bench_extract_ms = 0.0;
static double g_direct_bench_fft_ms = 0.0;
static double g_direct_bench_total_ms = 0.0;

typedef struct {
    int ready;
    mwSize nslots;
    uint32_t *dmrs_indices;       /* 306 x 4 x slots */
    type1_cf *dmrs_symbols;       /* 306 x 4 x slots */
    uint32_t *data_indices;       /* 7956 x 4 x slots */
    type1_cf *data_qpsk;          /* 7956 x slots x 4 */
    mxLogical *coded_bits;        /* 15912 x slots x 4 */
    float rzf_lambda;
    mxArray *mx_dmrs_indices;
    mxArray *mx_dmrs_symbols;
    mxArray *mx_data_indices;
    mxArray *mx_data_qpsk;
    mxArray *mx_coded_bits;
    mxArray *mx_slots;
    mxArray *mx_lambda;
} type1_direct_phy_state;

static type1_direct_phy_state g_direct_phy = {0};

typedef struct {
    int running;
    uint64_t first_sequence;
    uint64_t first_timestamp;
    uint64_t next_frame_raw;
    float cfo_hz;
    uint64_t frames;
    uint64_t bit_errors[4];
    uint64_t bits[4];
    double extract_ms, fft_ms, phy_ms, total_ms;
} type1_direct_runtime;
static type1_direct_runtime g_direct_run = {0};

#define TYPE1_DIRECT_AUDIT_CAPACITY 256u
typedef struct {
    uint64_t measured_raw;
    uint64_t next_before_raw;
    uint64_t next_after_raw;
    uint64_t first_sequence_before;
    uint64_t first_sequence_after;
    uint64_t first_timestamp_before;
    uint64_t first_timestamp_after;
    int64_t adjustment_raw;
} type1_direct_audit_record;
static type1_direct_audit_record g_direct_audit[TYPE1_DIRECT_AUDIT_CAPACITY];
static uint32_t g_direct_audit_count = 0;
static uint64_t g_direct_audit_overflow = 0;

static void free_direct_phy_maps(void)
{
    mxFree(g_direct_phy.dmrs_indices);
    mxFree(g_direct_phy.dmrs_symbols);
    mxFree(g_direct_phy.data_indices);
    mxFree(g_direct_phy.data_qpsk);
    mxFree(g_direct_phy.coded_bits);
    mxDestroyArray(g_direct_phy.mx_dmrs_indices);
    mxDestroyArray(g_direct_phy.mx_dmrs_symbols);
    mxDestroyArray(g_direct_phy.mx_data_indices);
    mxDestroyArray(g_direct_phy.mx_data_qpsk);
    mxDestroyArray(g_direct_phy.mx_coded_bits);
    mxDestroyArray(g_direct_phy.mx_slots);
    mxDestroyArray(g_direct_phy.mx_lambda);
    memset(&g_direct_phy, 0, sizeof(g_direct_phy));
}

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
    g_fifo_mode = 0;
    g_consumer_sequence = 0;
    g_fifo_dropped_new = 0;
    g_fifo_high_water = 0;
    g_direct_bench_mode = 0;
    g_direct_bench_frames = 0;
    g_direct_bench_extract_ms = 0.0;
    g_direct_bench_fft_ms = 0.0;
    g_direct_bench_total_ms = 0.0;
    memset(&g_direct_run, 0, sizeof(g_direct_run));
}

/* ── Close device (stop stream first, then release hardware) ── */
static void close_device(void)
{
    stop_stream();
    /* direct maps are MEX-persistent and are deliberately retained across
       radio close/open cycles.  Releasing them here races MATLAB's MEX exit
       teardown after an explicit close; directphysetup replaces them safely. */
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

        /* In FIFO mode preserve unread entries. The SDR read still happens
         * every block to protect the hardware DMA; only the software copy is
         * dropped when the bounded consumer queue is full. */
        pthread_mutex_lock(&g_ring_mutex);
        sequence = g_sequence;
        if (g_fifo_mode && sequence - g_consumer_sequence >= g_ring_blocks) {
            g_fifo_dropped_new++;
        } else {
            for (ch = 0; ch < 4; ++ch) {
                destination_offset =
                    (((size_t)(sequence % g_ring_blocks) * 4 + ch) *
                     channel_samples);
                memcpy(g_ring_iq + destination_offset, buffers[ch], channel_bytes);
            }
            g_ring_timestamp[sequence % g_ring_blocks] = timestamp;
            g_sequence = sequence + 1;
            if (g_fifo_mode) {
                uint64_t depth = g_sequence - g_consumer_sequence;
                if (depth > g_fifo_high_water) g_fifo_high_water = depth;
            }
        }
        pthread_mutex_unlock(&g_ring_mutex);
    }

done:
    for (ch = 0; ch < 4; ++ch)
        free(buffers[ch]);
    return NULL;
}

/* ── Fixed-size radix-2 forward FFT used by the direct-consumer path.
 *
 * This is deliberately kept separate from the YunSDR worker: no MATLAB
 * allocation, no dynamic work buffer, and no dependency on FFTW.  The
 * transform is unnormalised, matching the conventional forward FFT used by
 * MATLAB; the OFDM regression script checks the remaining toolbox scaling
 * and bin-order conventions before this kernel is used on the live ring. */
static void type1_fft1024(type1_cf x[TYPE1_NFFT])
{
    uint32_t i, j, len, half, base, k;

    for (i = 1, j = 0; i < TYPE1_NFFT; ++i) {
        uint32_t bit = TYPE1_NFFT >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            type1_cf temporary = x[i];
            x[i] = x[j];
            x[j] = temporary;
        }
    }

    for (len = 2; len <= TYPE1_NFFT; len <<= 1) {
        float angle = -2.0f * TYPE1_PI / (float)len;
        float step_real = cosf(angle);
        float step_imag = sinf(angle);
        half = len >> 1;
        for (base = 0; base < TYPE1_NFFT; base += len) {
            float wr = 1.0f;
            float wi = 0.0f;
            for (k = 0; k < half; ++k) {
                type1_cf even = x[base + k];
                type1_cf odd = x[base + k + half];
                type1_cf product;
                float next_wr;
                product.real = wr * odd.real - wi * odd.imag;
                product.imag = wr * odd.imag + wi * odd.real;
                x[base + k].real = even.real + product.real;
                x[base + k].imag = even.imag + product.imag;
                x[base + k + half].real = even.real - product.real;
                x[base + k + half].imag = even.imag - product.imag;
                next_wr = wr * step_real - wi * step_imag;
                wi = wr * step_imag + wi * step_real;
                wr = next_wr;
            }
        }
    }
}

/* ── command_ofdm_grid: offline fixed-parameter C OFDM regression hook.
 *
 * Inputs are a virtual-30.72-MS/s [samples x 4] complex-single waveform,
 * one CP length per requested symbol, the CFO in Hz, and the number of
 * samples after which CFO phase is reset (normally one 0.5-ms slot), and
 * optionally one CP-relative FFT-window offset per symbol.  The CP length
 * always advances the symbol cursor; the optional offset only moves the FFT
 * window within that CP.  This command does not open or touch the SDR.  It
 * exists to establish a strict grid-level equivalence baseline before the
 * same FFT is called from the persistent native-ring consumer. */
static void command_ofdm_grid(int nlhs, mxArray **plhs, int nrhs,
                              const mxArray **prhs)
{
    const mxComplexSingle *input;
    const double *cp_lengths;
    const double *window_offsets = NULL;
    mxComplexSingle *output;
    mwSize input_rows;
    mwSize n_symbols;
    mwSize dimensions[3];
    uint32_t phase_period;
    double phase_period_value;
    float frequency_hz;
    size_t cursor = 0;
    mwSize symbol;
    int channel;

    if (nrhs != 5 && nrhs != 6)
        mexErrMsgIdAndTxt("nr4:mex:OFDMAargs",
                          "ofdmgrid requires IQ, CP lengths, CFO, phase period and optional window offsets.");
    if (!mxIsSingle(prhs[1]) || !mxIsComplex(prhs[1]) ||
        mxGetNumberOfDimensions(prhs[1]) != 2 || mxGetN(prhs[1]) != 4)
        mexErrMsgIdAndTxt("nr4:mex:OFDMIQ",
                          "ofdmgrid IQ must be [samples x 4] complex single.");
    if (!mxIsDouble(prhs[2]) || mxIsComplex(prhs[2]))
        mexErrMsgIdAndTxt("nr4:mex:OFDMCp",
                          "ofdmgrid CP lengths must be a real double vector.");
    if (!mxIsDouble(prhs[3]) || mxGetNumberOfElements(prhs[3]) != 1 ||
        !mxIsDouble(prhs[4]) || mxGetNumberOfElements(prhs[4]) != 1)
        mexErrMsgIdAndTxt("nr4:mex:OFDMAargs",
                          "ofdmgrid CFO and phase period must be scalar doubles.");

    input_rows = mxGetM(prhs[1]);
    n_symbols = mxGetNumberOfElements(prhs[2]);
    if (n_symbols == 0)
        mexErrMsgIdAndTxt("nr4:mex:OFDMCp", "ofdmgrid needs at least one symbol.");
    phase_period_value = mxGetScalar(prhs[4]);
    if (phase_period_value < 1.0 || phase_period_value > 4294967295.0 ||
        phase_period_value != floor(phase_period_value))
        mexErrMsgIdAndTxt("nr4:mex:OFDMAargs", "OFDM phase period must be positive.");
    phase_period = (uint32_t)phase_period_value;

    if (nrhs == 6) {
        if (!mxIsDouble(prhs[5]) || mxIsComplex(prhs[5]) ||
            (mxGetNumberOfElements(prhs[5]) != 1 &&
             mxGetNumberOfElements(prhs[5]) != n_symbols))
            mexErrMsgIdAndTxt("nr4:mex:OFDMWindow",
                              "OFDM window offsets must be one real scalar or one per symbol.");
        window_offsets = mxGetDoubles(prhs[5]);
    }

    cp_lengths = mxGetDoubles(prhs[2]);
    for (symbol = 0; symbol < n_symbols; ++symbol) {
        double cp = cp_lengths[symbol];
        double window = window_offsets == NULL ? 0.0 :
            window_offsets[mxGetNumberOfElements(prhs[5]) == 1 ? 0 : symbol];
        ptrdiff_t fft_start = (ptrdiff_t)cursor + (ptrdiff_t)cp + (ptrdiff_t)window;
        if (cp < 0.0 || cp != floor(cp) || cp > 65535.0 ||
            window != floor(window) || window < -cp || window > 0.0 ||
            fft_start < 0 || (size_t)fft_start + TYPE1_NFFT > input_rows ||
            cursor + (size_t)cp + TYPE1_NFFT > input_rows)
            mexErrMsgIdAndTxt("nr4:mex:OFDMCp",
                              "CP lengths do not describe complete OFDM symbols in IQ.");
        cursor += (size_t)cp + TYPE1_NFFT;
    }

    dimensions[0] = TYPE1_ACTIVE_SC;
    dimensions[1] = n_symbols;
    dimensions[2] = 4;
    plhs[0] = mxCreateNumericArray(3, dimensions, mxSINGLE_CLASS, mxCOMPLEX);
    input = mxGetComplexSingles(prhs[1]);
    output = mxGetComplexSingles(plhs[0]);
    frequency_hz = (float)mxGetScalar(prhs[3]);
    cursor = 0;

    for (symbol = 0; symbol < n_symbols; ++symbol) {
        uint32_t cp = (uint32_t)cp_lengths[symbol];
        ptrdiff_t window = window_offsets == NULL ? 0 :
            (ptrdiff_t)window_offsets[mxGetNumberOfElements(prhs[5]) == 1 ? 0 : symbol];
        size_t fft_start = (size_t)((ptrdiff_t)cursor + (ptrdiff_t)cp + window);
        for (channel = 0; channel < 4; ++channel) {
            type1_cf work[TYPE1_NFFT];
            uint32_t sample;
            for (sample = 0; sample < TYPE1_NFFT; ++sample) {
                size_t time = fft_start + sample;
                float phase = -2.0f * TYPE1_PI * frequency_hz *
                    (float)(time % phase_period) / TYPE1_VIRTUAL_FS;
                float c = cosf(phase);
                float s = sinf(phase);
                mxComplexSingle value = input[time + (size_t)channel * input_rows];
                work[sample].real = value.real * c - value.imag * s;
                work[sample].imag = value.real * s + value.imag * c;
            }
            type1_fft1024(work);
            for (sample = 0; sample < TYPE1_ACTIVE_SC; ++sample) {
                uint32_t bin = (sample < TYPE1_ACTIVE_SC / 2) ?
                    TYPE1_NFFT - TYPE1_ACTIVE_SC / 2 + sample :
                    sample - TYPE1_ACTIVE_SC / 2;
                size_t destination = (size_t)sample +
                    (size_t)symbol * TYPE1_ACTIVE_SC +
                    (size_t)channel * TYPE1_ACTIVE_SC * n_symbols;
                output[destination].real = work[bin].real;
                output[destination].imag = work[bin].imag;
            }
        }
        cursor += (size_t)cp + TYPE1_NFFT;
    }

    (void)nlhs;
}

static double monotonic_ms(void)
{
    struct timespec value;
    clock_gettime(CLOCK_MONOTONIC, &value);
    return 1e3 * (double)value.tv_sec + 1e-6 * (double)value.tv_nsec;
}

static type1_cf direct_bench_virtual_sample(uint64_t first_sequence,
                                            size_t virtual_sample, int channel)
{
    size_t raw_sample = 4 * virtual_sample + (size_t)channel;
    uint64_t block_sequence = first_sequence + raw_sample / g_block_samples;
    uint32_t ring_slot = (uint32_t)(block_sequence % g_ring_blocks);
    size_t sample_in_block = raw_sample % g_block_samples;
    size_t source = (((size_t)ring_slot * 4 + (size_t)channel) *
                     (size_t)g_block_samples * 2 + 2 * sample_in_block);
    type1_cf value;
    value.real = (float)g_ring_iq[source] / 32768.0f;
    value.imag = (float)g_ring_iq[source + 1] / 32768.0f;
    return value;
}

/* Process the 5.5-ms active half of one 10-ms frame.  The caller retains
 * g_consumer_sequence until this function returns, so producer writes cannot
 * overwrite the native samples being read. */
static void direct_bench_process_frame(uint64_t first_sequence,
                                       double *extract_ms, double *fft_ms)
{
    const uint32_t active_symbols = 154; /* slot 0 through slot 10 */
    size_t cursor = 0;
    uint32_t symbol;
    int channel;

    for (symbol = 0; symbol < active_symbols; ++symbol) {
        uint32_t cp = (symbol % 14 == 0) ? 88u : 72u;
        size_t fft_start = cursor + cp;
        for (channel = 0; channel < 4; ++channel) {
            type1_cf work[TYPE1_NFFT];
            uint32_t sample;
            double started = monotonic_ms();
            for (sample = 0; sample < TYPE1_NFFT; ++sample)
                work[sample] = direct_bench_virtual_sample(
                    first_sequence, fft_start + sample, channel);
            *extract_ms += monotonic_ms() - started;
            started = monotonic_ms();
            type1_fft1024(work);
            *fft_ms += monotonic_ms() - started;
        }
        cursor += (size_t)cp + TYPE1_NFFT;
    }
}

static void command_direct_bench_start(int nlhs, mxArray **plhs, int nrhs)
{
    if (nrhs != 1)
        mexErrMsgIdAndTxt("nr4:mex:DirectBenchStartArgs",
                          "directbenchstart takes no arguments.");
    if (g_ring_iq == NULL || !g_thread_created)
        mexErrMsgIdAndTxt("nr4:mex:NotStreaming",
                          "Start the stream before directbenchstart.");
    if (g_block_samples % 4 != 0 || g_block_samples / 4 != 30720)
        mexErrMsgIdAndTxt("nr4:mex:DirectBenchRate",
                          "direct benchmark requires 122880 raw samples per 1-ms block.");
    pthread_mutex_lock(&g_ring_mutex);
    g_consumer_sequence = g_sequence; /* discard only pre-benchmark history */
    g_fifo_dropped_new = 0;
    g_fifo_high_water = 0;
    g_fifo_mode = 1;
    g_direct_bench_mode = 1;
    g_direct_bench_frames = 0;
    g_direct_bench_extract_ms = 0.0;
    g_direct_bench_fft_ms = 0.0;
    g_direct_bench_total_ms = 0.0;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(true);
}

static void command_direct_bench_poll(int nlhs, mxArray **plhs, int nrhs,
                                      const mxArray **prhs)
{
    uint32_t requested, take, available;
    uint64_t first;
    uint32_t frame;

    if (nrhs != 2)
        mexErrMsgIdAndTxt("nr4:mex:DirectBenchPollArgs",
                          "directbenchpoll requires a maximum frame count.");
    requested = scalar_u32(prhs[1], "direct benchmark frames");
    if (requested == 0)
        mexErrMsgIdAndTxt("nr4:mex:DirectBenchPollArgs",
                          "direct benchmark frame count must be positive.");
    pthread_mutex_lock(&g_ring_mutex);
    if (!g_direct_bench_mode || !g_fifo_mode) {
        pthread_mutex_unlock(&g_ring_mutex);
        mexErrMsgIdAndTxt("nr4:mex:DirectBenchOff",
                          "Call directbenchstart before directbenchpoll.");
    }
    available = (uint32_t)(g_sequence - g_consumer_sequence);
    take = requested < available / 10 ? requested : available / 10;
    first = g_consumer_sequence;
    pthread_mutex_unlock(&g_ring_mutex);

    for (frame = 0; frame < take; ++frame) {
        double extract_ms = 0.0, fft_ms = 0.0;
        double started = monotonic_ms();
        direct_bench_process_frame(first + (uint64_t)frame * 10,
                                   &extract_ms, &fft_ms);
        g_direct_bench_extract_ms += extract_ms;
        g_direct_bench_fft_ms += fft_ms;
        g_direct_bench_total_ms += monotonic_ms() - started;
        g_direct_bench_frames++;
        pthread_mutex_lock(&g_ring_mutex);
        if (g_consumer_sequence != first + (uint64_t)frame * 10) {
            pthread_mutex_unlock(&g_ring_mutex);
            mexErrMsgIdAndTxt("nr4:mex:DirectBenchConsumer",
                              "Only one direct FIFO consumer is supported.");
        }
        g_consumer_sequence += 10;
        pthread_mutex_unlock(&g_ring_mutex);
    }
    if (nlhs > 0) plhs[0] = mxCreateDoubleScalar((double)take);
}

/* [frames pending dropNew highWater extractMs fftMs totalMs], where the
 * final three values are per-frame averages. */
static void command_direct_bench_status(int nlhs, mxArray **plhs)
{
    double *out;
    uint64_t pending, dropped, high;
    uint64_t frames = g_direct_bench_frames;
    pthread_mutex_lock(&g_ring_mutex);
    pending = g_sequence - g_consumer_sequence;
    dropped = g_fifo_dropped_new;
    high = g_fifo_high_water;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) {
        plhs[0] = mxCreateDoubleMatrix(1, 8, mxREAL);
        out = mxGetDoubles(plhs[0]);
        out[0] = (double)frames;
        out[1] = (double)pending;
        out[2] = (double)dropped;
        out[3] = (double)high;
        out[4] = frames ? g_direct_bench_extract_ms / (double)frames : NAN;
        out[5] = frames ? g_direct_bench_fft_ms / (double)frames : NAN;
        out[6] = frames ? g_direct_bench_total_ms / (double)frames : NAN;
        out[7] = (double)g_direct_bench_mode;
    }
}

static void command_direct_bench_stop(int nlhs, mxArray **plhs, int nrhs)
{
    if (nrhs != 1)
        mexErrMsgIdAndTxt("nr4:mex:DirectBenchStopArgs",
                          "directbenchstop takes no arguments.");
    pthread_mutex_lock(&g_ring_mutex);
    g_direct_bench_mode = 0;
    g_fifo_mode = 0;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(true);
}

/* Persist the fixed reference maps once.  directpoll will consume these
 * native copies and therefore never dereference MATLAB inputs on its hot
 * path.  Layouts intentionally match type1_decode_frame_grid_mex.c. */
static void command_direct_phy_setup(int nlhs, mxArray **plhs, int nrhs,
                                     const mxArray **prhs)
{
    const mwSize *dmrs_dims, *data_dims, *qpsk_dims, *bit_dims;
    mwSize nslots, i, dmrs_count, data_count, qpsk_count, bit_count;
    const mxComplexSingle *source_complex;

    if (nrhs != 7)
        mexErrMsgIdAndTxt("nr4:mex:DirectPhySetupArgs",
                          "directphysetup requires DM-RS/data maps and RZF lambda.");
    if (!mxIsUint32(prhs[1]) || !mxIsSingle(prhs[2]) || !mxIsComplex(prhs[2]) ||
        !mxIsUint32(prhs[3]) || !mxIsSingle(prhs[4]) || !mxIsComplex(prhs[4]) ||
        !mxIsLogical(prhs[5]) || !mxIsDouble(prhs[6]))
        mexErrMsgIdAndTxt("nr4:mex:DirectPhySetupType", "Unexpected direct PHY map types.");
    if (mxGetNumberOfDimensions(prhs[1]) != 3 ||
        mxGetNumberOfDimensions(prhs[2]) != 3 ||
        mxGetNumberOfDimensions(prhs[3]) != 3 ||
        mxGetNumberOfDimensions(prhs[4]) != 3 ||
        mxGetNumberOfDimensions(prhs[5]) != 3)
        mexErrMsgIdAndTxt("nr4:mex:DirectPhySetupShape", "Direct PHY maps must be 3-D.");

    dmrs_dims = mxGetDimensions(prhs[1]);
    data_dims = mxGetDimensions(prhs[3]);
    qpsk_dims = mxGetDimensions(prhs[4]);
    bit_dims = mxGetDimensions(prhs[5]);
    nslots = dmrs_dims[2];
    if (nslots != 10 || dmrs_dims[0] != 306 || dmrs_dims[1] != 4 ||
        mxGetDimensions(prhs[2])[0] != 306 || mxGetDimensions(prhs[2])[1] != 4 ||
        mxGetDimensions(prhs[2])[2] != nslots || data_dims[0] != 7956 ||
        data_dims[1] != 4 || data_dims[2] != nslots || qpsk_dims[0] != 7956 ||
        qpsk_dims[1] != nslots || qpsk_dims[2] != 4 || bit_dims[0] != 15912 ||
        bit_dims[1] != nslots || bit_dims[2] != 4)
        mexErrMsgIdAndTxt("nr4:mex:DirectPhySetupShape", "Unexpected Type-A map shape.");

    free_direct_phy_maps();
    dmrs_count = 306 * 4 * nslots;
    data_count = 7956 * 4 * nslots;
    qpsk_count = 7956 * nslots * 4;
    bit_count = 15912 * nslots * 4;
    g_direct_phy.dmrs_indices = (uint32_t *)mxMalloc(dmrs_count * sizeof(uint32_t));
    g_direct_phy.dmrs_symbols = (type1_cf *)mxMalloc(dmrs_count * sizeof(type1_cf));
    g_direct_phy.data_indices = (uint32_t *)mxMalloc(data_count * sizeof(uint32_t));
    g_direct_phy.data_qpsk = (type1_cf *)mxMalloc(qpsk_count * sizeof(type1_cf));
    g_direct_phy.coded_bits = (mxLogical *)mxMalloc(bit_count * sizeof(mxLogical));
    if (g_direct_phy.dmrs_indices == NULL || g_direct_phy.dmrs_symbols == NULL ||
        g_direct_phy.data_indices == NULL || g_direct_phy.data_qpsk == NULL ||
        g_direct_phy.coded_bits == NULL) {
        free_direct_phy_maps();
        mexErrMsgIdAndTxt("nr4:mex:DirectPhyMemory", "Could not persist direct PHY maps.");
    }
    memcpy(g_direct_phy.dmrs_indices, mxGetData(prhs[1]), dmrs_count * sizeof(uint32_t));
    memcpy(g_direct_phy.data_indices, mxGetData(prhs[3]), data_count * sizeof(uint32_t));
    memcpy(g_direct_phy.coded_bits, mxGetLogicals(prhs[5]), bit_count * sizeof(mxLogical));
    source_complex = mxGetComplexSingles(prhs[2]);
    for (i = 0; i < dmrs_count; ++i) {
        g_direct_phy.dmrs_symbols[i].real = source_complex[i].real;
        g_direct_phy.dmrs_symbols[i].imag = source_complex[i].imag;
    }
    source_complex = mxGetComplexSingles(prhs[4]);
    for (i = 0; i < qpsk_count; ++i) {
        g_direct_phy.data_qpsk[i].real = source_complex[i].real;
        g_direct_phy.data_qpsk[i].imag = source_complex[i].imag;
    }
    g_direct_phy.nslots = nslots;
    g_direct_phy.rzf_lambda = (float)mxGetScalar(prhs[6]);
    g_direct_phy.mx_dmrs_indices = mxDuplicateArray(prhs[1]);
    g_direct_phy.mx_dmrs_symbols = mxDuplicateArray(prhs[2]);
    g_direct_phy.mx_data_indices = mxDuplicateArray(prhs[3]);
    g_direct_phy.mx_data_qpsk = mxDuplicateArray(prhs[4]);
    g_direct_phy.mx_coded_bits = mxDuplicateArray(prhs[5]);
    g_direct_phy.mx_slots = mxCreateDoubleMatrix(nslots, 1, mxREAL);
    g_direct_phy.mx_lambda = mxCreateDoubleScalar(mxGetScalar(prhs[6]));
    if (g_direct_phy.mx_dmrs_indices == NULL || g_direct_phy.mx_dmrs_symbols == NULL ||
        g_direct_phy.mx_data_indices == NULL || g_direct_phy.mx_data_qpsk == NULL ||
        g_direct_phy.mx_coded_bits == NULL || g_direct_phy.mx_slots == NULL ||
        g_direct_phy.mx_lambda == NULL) {
        free_direct_phy_maps();
        mexErrMsgIdAndTxt("nr4:mex:DirectPhyMemory", "Could not persist direct PHY MATLAB maps.");
    }
    for (i = 0; i < nslots; ++i) mxGetDoubles(g_direct_phy.mx_slots)[i] = (double)(i + 1);
    mexMakeArrayPersistent(g_direct_phy.mx_dmrs_indices);
    mexMakeArrayPersistent(g_direct_phy.mx_dmrs_symbols);
    mexMakeArrayPersistent(g_direct_phy.mx_data_indices);
    mexMakeArrayPersistent(g_direct_phy.mx_data_qpsk);
    mexMakeArrayPersistent(g_direct_phy.mx_coded_bits);
    mexMakeArrayPersistent(g_direct_phy.mx_slots);
    mexMakeArrayPersistent(g_direct_phy.mx_lambda);
    g_direct_phy.ready = 1;
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(true);
}

/* [ready nslots mapBytes lambda] */
static void command_direct_phy_status(int nlhs, mxArray **plhs)
{
    double *out;
    if (nlhs == 0) return;
    plhs[0] = mxCreateDoubleMatrix(1, 4, mxREAL);
    out = mxGetDoubles(plhs[0]);
    out[0] = (double)g_direct_phy.ready;
    out[1] = (double)g_direct_phy.nslots;
    out[2] = g_direct_phy.ready ? (double)(306*4*g_direct_phy.nslots *
             (sizeof(uint32_t)+sizeof(type1_cf)) + 7956*4*g_direct_phy.nslots *
             sizeof(uint32_t) + 7956*g_direct_phy.nslots*4*sizeof(type1_cf) +
             15912*g_direct_phy.nslots*4*sizeof(mxLogical)) : 0.0;
    out[3] = (double)g_direct_phy.rzf_lambda;
}

/* Invoke the existing validated C frame kernel with persistent reference
 * arrays.  This is the equivalence gate used before its arithmetic is folded
 * into native-ring directpoll; no reference map is copied on this call. */
static void command_direct_phy_decode_grid(int nlhs, mxArray **plhs, int nrhs,
                                           const mxArray **prhs)
{
    mxArray *rhs[8];
    mxArray *lhs[4] = {NULL, NULL, NULL, NULL};
    int result;
    if (nrhs != 2)
        mexErrMsgIdAndTxt("nr4:mex:DirectPhyGridArgs", "directphydecodegrid requires one grid.");
    if (!g_direct_phy.ready)
        mexErrMsgIdAndTxt("nr4:mex:DirectPhyMaps", "Call directphysetup first.");
    if (!mxIsSingle(prhs[1]) || !mxIsComplex(prhs[1]) ||
        mxGetNumberOfDimensions(prhs[1]) != 3 || mxGetDimensions(prhs[1])[0] != 612 ||
        mxGetDimensions(prhs[1])[1] < 154 || mxGetDimensions(prhs[1])[2] != 4)
        mexErrMsgIdAndTxt("nr4:mex:DirectPhyGrid", "grid must be 612x154-or-morex4 complex single.");
    rhs[0] = (mxArray *)prhs[1];
    rhs[1] = g_direct_phy.mx_slots;
    rhs[2] = g_direct_phy.mx_dmrs_indices;
    rhs[3] = g_direct_phy.mx_dmrs_symbols;
    rhs[4] = g_direct_phy.mx_data_indices;
    rhs[5] = g_direct_phy.mx_data_qpsk;
    rhs[6] = g_direct_phy.mx_coded_bits;
    rhs[7] = g_direct_phy.mx_lambda;
    result = mexCallMATLAB(4, lhs, 8, rhs, "type1_decode_frame_grid_mex");
    if (result != 0)
        mexErrMsgIdAndTxt("nr4:mex:DirectPhyKernel", "type1_decode_frame_grid_mex failed.");
    if (nlhs > 0) plhs[0] = lhs[0]; else mxDestroyArray(lhs[0]);
    if (nlhs > 1) plhs[1] = lhs[1]; else mxDestroyArray(lhs[1]);
    if (nlhs > 2) plhs[2] = lhs[2]; else mxDestroyArray(lhs[2]);
    if (nlhs > 3) plhs[3] = lhs[3]; else mxDestroyArray(lhs[3]);
}

static type1_cf direct_sample_raw(uint64_t first_sequence, uint64_t first_timestamp,
                                  uint64_t raw_timestamp)
{
    uint64_t delta = raw_timestamp - first_timestamp;
    uint64_t sequence = first_sequence + delta / g_block_samples;
    size_t sample = (size_t)(delta % g_block_samples);
    uint32_t slot = (uint32_t)(sequence % g_ring_blocks);
    /* The digital switch is indexed from the DMA block's first sample, as
       in snapshotvirtual: virtual(m,q)=raw(4*m+q,q).  Hardware timestamps
       need not be divisible by four, so absolute timestamp modulo four
       would rotate the antenna selection and corrupt the native grid. */
    int channel = (int)(delta & 3u);
    size_t source = (((size_t)slot * 4 + (size_t)channel) *
        (size_t)g_block_samples * 2 + 2 * sample);
    type1_cf value = {(float)g_ring_iq[source] / 32768.0f,
                      (float)g_ring_iq[source + 1] / 32768.0f};
    return value;
}

static mxArray *direct_make_grid(uint64_t first_sequence, uint64_t first_timestamp,
                                 uint64_t frame_raw, float cfo_hz,
                                 double *extract_ms, double *fft_ms)
{
    mwSize dims[3] = {612,154,4};
    mxArray *grid = mxCreateNumericArray(3,dims,mxSINGLE_CLASS,mxCOMPLEX);
    mxComplexSingle *out = mxGetComplexSingles(grid);
    size_t cursor = 0;
    uint32_t symbol;
    int channel;
    for (symbol=0; symbol<154; ++symbol) {
        uint32_t cp = symbol%14==0 ? 88u : 72u;
        size_t fft_start = cursor + cp;
        for (channel=0; channel<4; ++channel) {
            type1_cf work[TYPE1_NFFT]; uint32_t n; double t=monotonic_ms();
            for (n=0;n<TYPE1_NFFT;++n) {
                uint64_t raw = frame_raw + 4*(fft_start+n) + (uint64_t)channel;
                float phase = -2.0f*TYPE1_PI*cfo_hz*(float)((fft_start+n)%15360)/TYPE1_VIRTUAL_FS;
                type1_cf v=direct_sample_raw(first_sequence,first_timestamp,raw);
                float cr=cosf(phase), si=sinf(phase);
                work[n].real=v.real*cr-v.imag*si; work[n].imag=v.real*si+v.imag*cr;
            }
            *extract_ms += monotonic_ms()-t; t=monotonic_ms(); type1_fft1024(work); *fft_ms += monotonic_ms()-t;
            for (n=0;n<612;++n) { uint32_t bin=n<306?718+n:n-306; size_t d=n+(size_t)symbol*612+(size_t)channel*612*154; out[d].real=work[bin].real; out[d].imag=work[bin].imag; }
        }
        cursor += cp+TYPE1_NFFT;
    }
    return grid;
}

/* One-shot diagnostic hook: expose the exact native-ring extraction and FFT
 * used by directpoll.  It intentionally does not touch the FIFO consumer
 * state, so MATLAB can compare this grid against a timestamp-aligned
 * snapshot without perturbing the persistent real-time path. */
static void command_direct_grid(int nlhs, mxArray **plhs, int nrhs,
                                const mxArray **prhs)
{
    uint64_t wanted, sequence, begin, found = UINT64_MAX;
    uint32_t i;
    double extract_ms = 0.0, fft_ms = 0.0;
    float cfo_hz;

    if (nrhs != 3)
        mexErrMsgIdAndTxt("nr4:mex:DirectGridArgs",
                          "directgrid requires frame raw timestamp and CFO.");
    if (g_ring_iq == NULL || !g_thread_created)
        mexErrMsgIdAndTxt("nr4:mex:DirectGrid", "Start RX before directgrid.");
    if (!mxIsDouble(prhs[2]) || mxGetNumberOfElements(prhs[2]) != 1 ||
        !isfinite(mxGetScalar(prhs[2])))
        mexErrMsgIdAndTxt("nr4:mex:DirectGridArgs", "CFO must be one finite double.");

    wanted = scalar_u64(prhs[1], "frame raw timestamp");
    cfo_hz = (float)mxGetScalar(prhs[2]);
    pthread_mutex_lock(&g_ring_mutex);
    sequence = g_sequence;
    begin = sequence > g_ring_blocks ? sequence - g_ring_blocks : 0;
    for (i = 0; i < (uint32_t)(sequence - begin); ++i) {
        uint64_t candidate = begin + i;
        uint64_t timestamp = g_ring_timestamp[candidate % g_ring_blocks];
        if (wanted >= timestamp && wanted - timestamp < g_block_samples) {
            found = candidate;
            break;
        }
    }
    if (found == UINT64_MAX) {
        pthread_mutex_unlock(&g_ring_mutex);
        mexErrMsgIdAndTxt("nr4:mex:DirectGridRange",
                          "Locked frame timestamp is no longer in ring.");
    }
    /* The ring is sized in seconds and this diagnostic takes ~7 ms.  Holding
       the mutex makes its source samples immutable for the comparison. */
    plhs[0] = direct_make_grid(found, g_ring_timestamp[found % g_ring_blocks],
                               wanted, cfo_hz, &extract_ms, &fft_ms);
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 1) {
        plhs[1] = mxCreateDoubleMatrix(1, 2, mxREAL);
        mxGetDoubles(plhs[1])[0] = extract_ms;
        mxGetDoubles(plhs[1])[1] = fft_ms;
    }
}

static void command_direct_start(int nlhs,mxArray **plhs,int nrhs,const mxArray **prhs)
{
    uint64_t wanted, sequence, begin, found=UINT64_MAX; uint32_t i;
    if(nrhs!=3) mexErrMsgIdAndTxt("nr4:mex:DirectStartArgs","directstart requires frame raw timestamp and CFO.");
    if(!g_direct_phy.ready||g_ring_iq==NULL||!g_thread_created) mexErrMsgIdAndTxt("nr4:mex:DirectStart","Configure maps and start RX first.");
    wanted=scalar_u64(prhs[1],"frame raw timestamp");
    pthread_mutex_lock(&g_ring_mutex); sequence=g_sequence; begin=sequence>g_ring_blocks?sequence-g_ring_blocks:0;
    for(i=0;i<(uint32_t)(sequence-begin);++i){uint64_t s=begin+i,ts=g_ring_timestamp[s%g_ring_blocks];if(wanted>=ts&&wanted-ts<g_block_samples){found=s;break;}}
    if(found==UINT64_MAX){pthread_mutex_unlock(&g_ring_mutex);mexErrMsgIdAndTxt("nr4:mex:DirectStartRange","Locked frame timestamp is no longer in ring.");}
    g_consumer_sequence=found; g_fifo_dropped_new=0; g_fifo_high_water=0; g_fifo_mode=1;
    memset(&g_direct_run,0,sizeof(g_direct_run));
    memset(g_direct_audit,0,sizeof(g_direct_audit));
    g_direct_audit_count=0; g_direct_audit_overflow=0;
    g_direct_run.running=1; g_direct_run.first_sequence=found; g_direct_run.first_timestamp=g_ring_timestamp[found%g_ring_blocks]; g_direct_run.next_frame_raw=wanted; g_direct_run.cfo_hz=(float)mxGetScalar(prhs[2]);
    pthread_mutex_unlock(&g_ring_mutex);
    if(nlhs)plhs[0]=mxCreateLogicalScalar(true);
    if(nlhs>1)plhs[1]=make_u64(found);
    if(nlhs>2)plhs[2]=make_u64(sequence);
    if(nlhs>3)plhs[3]=make_u64(g_direct_run.first_timestamp);
}

/* Startup-only flush.  This deliberately discards pre-track history before
 * directstart; it is reported separately from dropNew, which remains a
 * runtime FIFO-overflow validity failure. */
static void command_direct_flush(int nlhs, mxArray **plhs, int nrhs)
{
    uint64_t discarded;
    if (nrhs != 1)
        mexErrMsgIdAndTxt("nr4:mex:DirectFlushArgs", "directflush takes no arguments.");
    if (g_ring_iq == NULL || !g_thread_created)
        mexErrMsgIdAndTxt("nr4:mex:DirectFlush", "Start RX before directflush.");
    pthread_mutex_lock(&g_ring_mutex);
    if (g_direct_run.running) {
        pthread_mutex_unlock(&g_ring_mutex);
        mexErrMsgIdAndTxt("nr4:mex:DirectFlush", "directflush is allowed only before directstart.");
    }
    discarded = g_sequence - g_consumer_sequence;
    g_consumer_sequence = g_sequence;
    g_fifo_mode = 0;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = mxCreateDoubleScalar((double)discarded);
}

/* Timestamp of the newest complete DMA block.  The two-stage MATLAB
 * starter uses it to choose the newest PSS-aligned frame with enough active
 * symbols already present, rather than reopening historical backlog. */
static void command_direct_latest_timestamp(int nlhs, mxArray **plhs, int nrhs)
{
    uint64_t timestamp, sequence;
    if (nrhs != 1)
        mexErrMsgIdAndTxt("nr4:mex:DirectLatestArgs", "directlatesttimestamp takes no arguments.");
    if (g_ring_iq == NULL || !g_thread_created)
        mexErrMsgIdAndTxt("nr4:mex:DirectLatest", "Start RX before directlatesttimestamp.");
    pthread_mutex_lock(&g_ring_mutex);
    if (g_sequence == 0) {
        pthread_mutex_unlock(&g_ring_mutex);
        mexErrMsgIdAndTxt("nr4:mex:DirectLatest", "RX ring is empty.");
    }
    sequence = g_sequence;
    timestamp = g_ring_timestamp[(sequence - 1u) % g_ring_blocks];
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = make_u64(timestamp);
    if (nlhs > 1) plhs[1] = make_u64(sequence);
}

static void command_direct_poll(int nlhs,mxArray **plhs,int nrhs,const mxArray **prhs)
{
    uint32_t max,done=0; if(nrhs!=2)mexErrMsgIdAndTxt("nr4:mex:DirectPollArgs","directpoll requires max frames."); max=scalar_u32(prhs[1],"max frames");
    while(done<max){uint64_t producer; mxArray *grid,*rhs[8],*lhs[4]={0}; double ex=0,ff=0,t,phy; uint32_t p;
        pthread_mutex_lock(&g_ring_mutex); producer=g_sequence; if(!g_direct_run.running||producer<g_direct_run.first_sequence+6){pthread_mutex_unlock(&g_ring_mutex);break;} pthread_mutex_unlock(&g_ring_mutex);
        t=monotonic_ms(); grid=direct_make_grid(g_direct_run.first_sequence,g_direct_run.first_timestamp,g_direct_run.next_frame_raw,g_direct_run.cfo_hz,&ex,&ff);
        rhs[0]=grid;rhs[1]=g_direct_phy.mx_slots;rhs[2]=g_direct_phy.mx_dmrs_indices;rhs[3]=g_direct_phy.mx_dmrs_symbols;rhs[4]=g_direct_phy.mx_data_indices;rhs[5]=g_direct_phy.mx_data_qpsk;rhs[6]=g_direct_phy.mx_coded_bits;rhs[7]=g_direct_phy.mx_lambda;phy=monotonic_ms(); if(mexCallMATLAB(4,lhs,8,rhs,"type1_decode_frame_grid_mex")!=0){mxDestroyArray(grid);mexErrMsgIdAndTxt("nr4:mex:DirectPhyKernel","C PHY kernel failed.");} phy=monotonic_ms()-phy;
        for(p=0;p<4;++p){double *e=mxGetDoubles(lhs[0]); g_direct_run.bit_errors[p]+=(uint64_t)e[p*10]+(uint64_t)e[p*10+1]+(uint64_t)e[p*10+2]+(uint64_t)e[p*10+3]+(uint64_t)e[p*10+4]+(uint64_t)e[p*10+5]+(uint64_t)e[p*10+6]+(uint64_t)e[p*10+7]+(uint64_t)e[p*10+8]+(uint64_t)e[p*10+9];g_direct_run.bits[p]+=159120;}
        mxDestroyArray(grid);mxDestroyArray(lhs[0]);mxDestroyArray(lhs[1]);mxDestroyArray(lhs[2]);mxDestroyArray(lhs[3]);g_direct_run.extract_ms+=ex;g_direct_run.fft_ms+=ff;g_direct_run.phy_ms+=phy;g_direct_run.total_ms+=monotonic_ms()-t;g_direct_run.frames++;done++;
        pthread_mutex_lock(&g_ring_mutex);g_direct_run.first_sequence+=10;g_direct_run.first_timestamp+=10*(uint64_t)g_block_samples;g_direct_run.next_frame_raw+=10*(uint64_t)g_block_samples;g_consumer_sequence=g_direct_run.first_sequence;pthread_mutex_unlock(&g_ring_mutex);
    } if(nlhs)plhs[0]=mxCreateDoubleScalar(done);
}

/* [running frames pending dropNew highWater err(1:4) bits(1:4)
 *  extractMs fftMs phyMs totalMs] -- timing fields are per-frame means. */
static void command_direct_status(int nlhs, mxArray **plhs)
{
    double *out;
    uint64_t pending, dropped, high;
    uint64_t frames = g_direct_run.frames;
    int p;
    pthread_mutex_lock(&g_ring_mutex);
    pending = g_sequence - g_consumer_sequence;
    dropped = g_fifo_dropped_new;
    high = g_fifo_high_water;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs == 0) return;
    plhs[0] = mxCreateDoubleMatrix(1, 17, mxREAL);
    out = mxGetDoubles(plhs[0]);
    out[0] = g_direct_run.running;
    out[1] = (double)frames;
    out[2] = (double)pending;
    out[3] = (double)dropped;
    out[4] = (double)high;
    for (p = 0; p < 4; ++p) {
        out[5+p] = (double)g_direct_run.bit_errors[p];
        out[9+p] = (double)g_direct_run.bits[p];
    }
    out[13] = frames ? g_direct_run.extract_ms / frames : NAN;
    out[14] = frames ? g_direct_run.fft_ms / frames : NAN;
    out[15] = frames ? g_direct_run.phy_ms / frames : NAN;
    out[16] = frames ? g_direct_run.total_ms / frames : NAN;
}

static void command_direct_stop(int nlhs, mxArray **plhs, int nrhs)
{
    if (nrhs != 1)
        mexErrMsgIdAndTxt("nr4:mex:DirectStopArgs", "directstop takes no arguments.");
    pthread_mutex_lock(&g_ring_mutex);
    g_direct_run.running = 0;
    g_fifo_mode = 0;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(true);
}

/* Control-plane only: MATLAB's low-rate PSS/CP tracker refreshes CFO while
 * the data plane remains in native C. */
static void command_direct_set_cfo(int nlhs, mxArray **plhs, int nrhs,
                                   const mxArray **prhs)
{
    if (nrhs != 2 || !mxIsDouble(prhs[1]) || mxGetNumberOfElements(prhs[1]) != 1)
        mexErrMsgIdAndTxt("nr4:mex:DirectCFOArgs", "directsetcfo requires one scalar CFO in Hz.");
    if (!isfinite(mxGetScalar(prhs[1])))
        mexErrMsgIdAndTxt("nr4:mex:DirectCFOArgs", "CFO must be finite.");
    pthread_mutex_lock(&g_ring_mutex);
    if (!g_direct_run.running) {
        pthread_mutex_unlock(&g_ring_mutex);
        mexErrMsgIdAndTxt("nr4:mex:DirectOff", "Call directstart before directsetcfo.");
    }
    g_direct_run.cfo_hz = (float)mxGetScalar(prhs[1]);
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(true);
}

/* Align the consumer's nominal 10-ms frame clock to a low-rate PSS tracker.
 * Only the modulo-frame residual is applied, so an RX backlog never causes
 * frame skipping or a jump to the tracker's newest frame. */
static void command_direct_set_timing(int nlhs, mxArray **plhs, int nrhs,
                                      const mxArray **prhs)
{
    uint64_t measured, period, current;
    int64_t difference, adjustment;
    type1_direct_audit_record record;

    if (nrhs != 2)
        mexErrMsgIdAndTxt("nr4:mex:DirectTimingArgs",
                          "directsettiming requires one frame raw timestamp.");
    measured = scalar_u64(prhs[1], "frame raw timestamp");
    pthread_mutex_lock(&g_ring_mutex);
    if (!g_direct_run.running) {
        pthread_mutex_unlock(&g_ring_mutex);
        mexErrMsgIdAndTxt("nr4:mex:DirectOff", "Call directstart before directsettiming.");
    }
    period = 10u * (uint64_t)g_block_samples;
    current = g_direct_run.next_frame_raw;
    memset(&record, 0, sizeof(record));
    record.measured_raw = measured;
    record.next_before_raw = current;
    record.first_sequence_before = g_direct_run.first_sequence;
    record.first_timestamp_before = g_direct_run.first_timestamp;
    difference = (int64_t)measured - (int64_t)current;
    adjustment = difference % (int64_t)period;
    if (adjustment > (int64_t)(period / 2u)) adjustment -= (int64_t)period;
    if (adjustment < -(int64_t)(period / 2u)) adjustment += (int64_t)period;
    g_direct_run.next_frame_raw = (uint64_t)((int64_t)current + adjustment);
    /* next_frame_raw is allowed to slew across a 1-ms DMA boundary. Keep
       its ring origin in the containing block before direct_sample_raw
       subtracts timestamps; otherwise an unsigned underflow selects a
       distant, unrelated ring entry after a long OTA run. */
    while (g_direct_run.next_frame_raw < g_direct_run.first_timestamp &&
           g_direct_run.first_sequence > 0) {
        g_direct_run.first_sequence--;
        g_direct_run.first_timestamp -= (uint64_t)g_block_samples;
    }
    while (g_direct_run.next_frame_raw - g_direct_run.first_timestamp >=
           (uint64_t)g_block_samples) {
        g_direct_run.first_sequence++;
        g_direct_run.first_timestamp += (uint64_t)g_block_samples;
    }
    g_consumer_sequence = g_direct_run.first_sequence;
    record.next_after_raw = g_direct_run.next_frame_raw;
    record.first_sequence_after = g_direct_run.first_sequence;
    record.first_timestamp_after = g_direct_run.first_timestamp;
    record.adjustment_raw = adjustment;
    if (g_direct_audit_count < TYPE1_DIRECT_AUDIT_CAPACITY)
        g_direct_audit[g_direct_audit_count++] = record;
    else
        g_direct_audit_overflow++;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = mxCreateDoubleScalar((double)adjustment);
}

/* Export timing-control evidence without converting hardware timestamps to
 * double, which would lose low-order raw-sample precision. */
static void command_direct_audit(int nlhs, mxArray **plhs, int nrhs)
{
    const char *names[] = {"count","overflow","measuredRaw", "nextBeforeRaw",
        "nextAfterRaw","firstSequenceBefore","firstSequenceAfter",
        "firstTimestampBefore","firstTimestampAfter","adjustmentRaw"};
    mxArray *out;
    uint64_t *measured, *before, *after, *seq_before, *seq_after;
    uint64_t *ts_before, *ts_after;
    double *adjustment;
    uint32_t count, i;
    if (nrhs != 1)
        mexErrMsgIdAndTxt("nr4:mex:DirectAuditArgs", "directaudit takes no arguments.");
    pthread_mutex_lock(&g_ring_mutex);
    count = g_direct_audit_count;
    out = mxCreateStructMatrix(1, 1, 10, names);
    mxSetField(out,0,"count",mxCreateDoubleScalar((double)count));
    mxSetField(out,0,"overflow",mxCreateDoubleScalar((double)g_direct_audit_overflow));
    mxSetField(out,0,"measuredRaw",mxCreateNumericMatrix(1,count,mxUINT64_CLASS,mxREAL));
    mxSetField(out,0,"nextBeforeRaw",mxCreateNumericMatrix(1,count,mxUINT64_CLASS,mxREAL));
    mxSetField(out,0,"nextAfterRaw",mxCreateNumericMatrix(1,count,mxUINT64_CLASS,mxREAL));
    mxSetField(out,0,"firstSequenceBefore",mxCreateNumericMatrix(1,count,mxUINT64_CLASS,mxREAL));
    mxSetField(out,0,"firstSequenceAfter",mxCreateNumericMatrix(1,count,mxUINT64_CLASS,mxREAL));
    mxSetField(out,0,"firstTimestampBefore",mxCreateNumericMatrix(1,count,mxUINT64_CLASS,mxREAL));
    mxSetField(out,0,"firstTimestampAfter",mxCreateNumericMatrix(1,count,mxUINT64_CLASS,mxREAL));
    mxSetField(out,0,"adjustmentRaw",mxCreateDoubleMatrix(1,count,mxREAL));
    measured=(uint64_t*)mxGetData(mxGetField(out,0,"measuredRaw"));
    before=(uint64_t*)mxGetData(mxGetField(out,0,"nextBeforeRaw"));
    after=(uint64_t*)mxGetData(mxGetField(out,0,"nextAfterRaw"));
    seq_before=(uint64_t*)mxGetData(mxGetField(out,0,"firstSequenceBefore"));
    seq_after=(uint64_t*)mxGetData(mxGetField(out,0,"firstSequenceAfter"));
    ts_before=(uint64_t*)mxGetData(mxGetField(out,0,"firstTimestampBefore"));
    ts_after=(uint64_t*)mxGetData(mxGetField(out,0,"firstTimestampAfter"));
    adjustment=mxGetDoubles(mxGetField(out,0,"adjustmentRaw"));
    for(i=0;i<count;++i){const type1_direct_audit_record *r=&g_direct_audit[i];
        measured[i]=r->measured_raw; before[i]=r->next_before_raw; after[i]=r->next_after_raw;
        seq_before[i]=r->first_sequence_before; seq_after[i]=r->first_sequence_after;
        ts_before[i]=r->first_timestamp_before; ts_after[i]=r->first_timestamp_after;
        adjustment[i]=(double)r->adjustment_raw;
    }
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = out; else mxDestroyArray(out);
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
 * command_snapshot_virtual: C-side four-phase switching and
 * 122.88-to-30.72 MS/s de-interleaving.
 *
 * This is mathematically identical to type1_digital_switch.m:
 *   virtualRF(m,q) = raw122(4*m+q, q), q=0..3.
 * Returning virtual30 directly avoids exporting the other 3/4 of raw
 * samples to MATLAB and avoids a MATLAB-side stitched temporary array.
 * ═══════════════════════════════════════════════════════════════ */
static void command_snapshot_virtual(int nlhs, mxArray **plhs, int nrhs,
                                     const mxArray **prhs)
{
    uint32_t requested_blocks;
    uint32_t stored_blocks;
    uint32_t take_blocks;
    uint64_t sequence;
    uint64_t first_sequence;
    uint64_t *timestamps;
    uint64_t *timestamp_copy;
    mwSize dimensions[2];
    mxComplexSingle *output;
    size_t output_rows;
    size_t output_row;
    size_t source_offset;
    uint32_t block;
    uint32_t slot;
    uint32_t n;
    int ch;

    if (g_ring_iq == NULL || !g_thread_created)
        mexErrMsgIdAndTxt("nr4:mex:NotStreaming",
                          "Start the background stream first.");
    if (nrhs != 2)
        mexErrMsgIdAndTxt("nr4:mex:SnapshotArgs",
                          "snapshotvirtual requires a block count.");
    requested_blocks = scalar_u32(prhs[1], "snapshotvirtual blocks");
    if (requested_blocks == 0)
        mexErrMsgIdAndTxt("nr4:mex:SnapshotArgs",
                          "snapshotvirtual block count must be positive.");
    if (g_block_samples % 4 != 0)
        mexErrMsgIdAndTxt("nr4:mex:SwitchAlignment",
                          "Block size must be divisible by four.");

    /* Select historical slots using the same non-blocking safety rule as
     * command_snapshot. No raw intermediate buffer is allocated. */
    pthread_mutex_lock(&g_ring_mutex);
    sequence = g_sequence;
    stored_blocks = (uint32_t)((sequence < g_ring_blocks) ?
                               sequence : g_ring_blocks);
    take_blocks = (requested_blocks < stored_blocks) ?
                  requested_blocks : stored_blocks;
    first_sequence = sequence - take_blocks;
    pthread_mutex_unlock(&g_ring_mutex);

    output_rows = (size_t)take_blocks * (g_block_samples / 4);
    dimensions[0] = (mwSize)output_rows;
    dimensions[1] = 4;
    plhs[0] = mxCreateNumericArray(2, dimensions, mxSINGLE_CLASS, mxCOMPLEX);
    output = mxGetComplexSingles(plhs[0]);

    if (nlhs > 1) {
        plhs[1] = mxCreateNumericMatrix(take_blocks, 1, mxUINT64_CLASS, mxREAL);
        timestamps = (uint64_t *)mxGetData(plhs[1]);
    } else {
        timestamps = NULL;
    }
    timestamp_copy = (uint64_t *)mxMalloc((size_t)take_blocks * sizeof(uint64_t));
    if (timestamp_copy == NULL)
        mexErrMsgIdAndTxt("nr4:mex:Memory",
                          "Could not allocate virtual snapshot timestamps.");

    for (block = 0; block < take_blocks; ++block) {
        uint64_t block_sequence = first_sequence + block;
        slot = (uint32_t)(block_sequence % g_ring_blocks);
        timestamp_copy[block] = g_ring_timestamp[slot];
        for (ch = 0; ch < 4; ++ch) {
            source_offset = (((size_t)slot * 4 + ch) *
                             (size_t)g_block_samples * 2);
            for (n = 0; n < g_block_samples / 4; ++n) {
                size_t input_sample = 4 * (size_t)n + (size_t)ch;
                output_row = (size_t)block * (g_block_samples / 4) + n;
                output[output_row + (size_t)ch * output_rows].real =
                    (float)g_ring_iq[source_offset + 2 * input_sample] / 32768.0f;
                output[output_row + (size_t)ch * output_rows].imag =
                    (float)g_ring_iq[source_offset + 2 * input_sample + 1] / 32768.0f;
            }
        }
    }
    if (timestamps != NULL)
        memcpy(timestamps, timestamp_copy, (size_t)take_blocks * sizeof(uint64_t));
    mxFree(timestamp_copy);
    if (nlhs > 2)
        plhs[2] = make_u64(sequence);
}

/* Ordered FIFO consumer. Unlike snapshotvirtual this starts at the oldest
 * unread block and advances g_consumer_sequence only after the output has
 * been copied. Queue entries are descriptors; IQ stays in the native ring. */
static void command_dequeue_virtual(int nlhs, mxArray **plhs, int nrhs,
                                    const mxArray **prhs)
{
    uint32_t requested, take, available, block, slot, n;
    uint64_t sequence, first;
    mwSize rows, dims[2];
    mxComplexSingle *output;
    uint64_t *timestamps = NULL;
    int ch;

    if (g_ring_iq == NULL || !g_thread_created)
        mexErrMsgIdAndTxt("nr4:mex:NotStreaming", "Start the stream first.");
    if (nrhs != 2)
        mexErrMsgIdAndTxt("nr4:mex:DequeueArgs", "dequeuevirtual requires a block count.");
    requested = scalar_u32(prhs[1], "dequeue blocks");
    if (requested == 0 || requested > g_ring_blocks)
        mexErrMsgIdAndTxt("nr4:mex:DequeueRange", "Requested blocks must be 1..ringBlocks.");
    if (g_block_samples % 4 != 0)
        mexErrMsgIdAndTxt("nr4:mex:SwitchAlignment", "Block size must be divisible by four.");

    pthread_mutex_lock(&g_ring_mutex);
    if (!g_fifo_mode) {
        pthread_mutex_unlock(&g_ring_mutex);
        mexErrMsgIdAndTxt("nr4:mex:FifoOff", "Call fifostart before dequeuevirtual.");
    }
    sequence = g_sequence;
    available = (uint32_t)(sequence - g_consumer_sequence);
    take = requested < available ? requested : available;
    first = g_consumer_sequence;
    pthread_mutex_unlock(&g_ring_mutex);

    rows = (mwSize)take * (g_block_samples / 4);
    dims[0] = rows; dims[1] = 4;
    plhs[0] = mxCreateNumericArray(2, dims, mxSINGLE_CLASS, mxCOMPLEX);
    output = mxGetComplexSingles(plhs[0]);
    if (nlhs > 1) {
        plhs[1] = mxCreateNumericMatrix(take, 1, mxUINT64_CLASS, mxREAL);
        timestamps = (uint64_t *)mxGetData(plhs[1]);
    }
    for (block = 0; block < take; ++block) {
        slot = (uint32_t)((first + block) % g_ring_blocks);
        if (timestamps != NULL) timestamps[block] = g_ring_timestamp[slot];
        for (ch = 0; ch < 4; ++ch) {
            size_t source = (((size_t)slot * 4 + ch) *
                             (size_t)g_block_samples * 2);
            for (n = 0; n < g_block_samples/4; ++n) {
                size_t input = 4*(size_t)n + (size_t)ch;
                size_t row = (size_t)block*(g_block_samples/4) + n;
                output[row + (size_t)ch*rows].real =
                    (float)g_ring_iq[source + 2*input] / 32768.0f;
                output[row + (size_t)ch*rows].imag =
                    (float)g_ring_iq[source + 2*input + 1] / 32768.0f;
            }
        }
    }
    pthread_mutex_lock(&g_ring_mutex);
    if (g_consumer_sequence != first) {
        pthread_mutex_unlock(&g_ring_mutex);
        mexErrMsgIdAndTxt("nr4:mex:FifoConsumer", "Only one FIFO consumer is supported.");
    }
    g_consumer_sequence += take;
    sequence = g_sequence;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 2) plhs[2] = make_u64(sequence);
}

static void command_fifo_start(int nlhs, mxArray **plhs, int nrhs)
{
    if (nrhs != 1) mexErrMsgIdAndTxt("nr4:mex:FifoStartArgs", "fifostart takes no arguments.");
    pthread_mutex_lock(&g_ring_mutex);
    g_consumer_sequence = g_sequence; /* explicitly discard pre-start history */
    g_fifo_dropped_new = 0;
    g_fifo_high_water = 0;
    g_fifo_mode = 1;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(true);
}

static void command_fifo_stop(int nlhs, mxArray **plhs, int nrhs)
{
    if (nrhs != 1) mexErrMsgIdAndTxt("nr4:mex:FifoStopArgs", "fifostop takes no arguments.");
    pthread_mutex_lock(&g_ring_mutex);
    g_fifo_mode = 0;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(true);
}

/* [mode producer consumer pending capacity droppedNew highWater stored] */
static void command_fifo_status(int nlhs, mxArray **plhs)
{
    double *v;
    uint64_t sequence, consumer, pending, dropped, high;
    int mode;
    pthread_mutex_lock(&g_ring_mutex);
    sequence = g_sequence; consumer = g_consumer_sequence;
    pending = sequence - consumer; dropped = g_fifo_dropped_new;
    high = g_fifo_high_water; mode = g_fifo_mode;
    pthread_mutex_unlock(&g_ring_mutex);
    if (nlhs > 0) {
        plhs[0] = mxCreateDoubleMatrix(1, 8, mxREAL); v = mxGetDoubles(plhs[0]);
        v[0] = mode; v[1] = (double)sequence; v[2] = (double)consumer;
        v[3] = (double)pending; v[4] = (double)g_ring_blocks;
        v[5] = (double)dropped; v[6] = (double)high;
        v[7] = (double)((sequence < g_ring_blocks) ? sequence : g_ring_blocks);
    }
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
    } else if (strcmp(command, "snapshotvirtual") == 0) {
        command_snapshot_virtual(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "ofdmgrid") == 0) {
        command_ofdm_grid(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "directbenchstart") == 0) {
        command_direct_bench_start(nlhs, plhs, nrhs);
    } else if (strcmp(command, "directbenchpoll") == 0) {
        command_direct_bench_poll(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "directbenchstatus") == 0) {
        command_direct_bench_status(nlhs, plhs);
    } else if (strcmp(command, "directbenchstop") == 0) {
        command_direct_bench_stop(nlhs, plhs, nrhs);
    } else if (strcmp(command, "directphysetup") == 0) {
        command_direct_phy_setup(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "directphystatus") == 0) {
        command_direct_phy_status(nlhs, plhs);
    } else if (strcmp(command, "directphydecodegrid") == 0) {
        command_direct_phy_decode_grid(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "directgrid") == 0) {
        command_direct_grid(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "directflush") == 0) {
        command_direct_flush(nlhs, plhs, nrhs);
    } else if (strcmp(command, "directlatesttimestamp") == 0) {
        command_direct_latest_timestamp(nlhs, plhs, nrhs);
    } else if (strcmp(command, "directstart") == 0) {
        command_direct_start(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "directpoll") == 0) {
        command_direct_poll(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "directsetcfo") == 0) {
        command_direct_set_cfo(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "directsettiming") == 0) {
        command_direct_set_timing(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "directaudit") == 0) {
        command_direct_audit(nlhs, plhs, nrhs);
    } else if (strcmp(command, "directstatus") == 0) {
        command_direct_status(nlhs, plhs);
    } else if (strcmp(command, "directstop") == 0) {
        command_direct_stop(nlhs, plhs, nrhs);
    } else if (strcmp(command, "dequeuevirtual") == 0) {
        command_dequeue_virtual(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "fifostart") == 0) {
        command_fifo_start(nlhs, plhs, nrhs);
    } else if (strcmp(command, "fifostop") == 0) {
        command_fifo_stop(nlhs, plhs, nrhs);
    } else if (strcmp(command, "fifostatus") == 0) {
        command_fifo_status(nlhs, plhs);
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
