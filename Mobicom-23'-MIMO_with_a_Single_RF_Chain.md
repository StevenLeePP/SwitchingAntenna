# GreenMO: Enabling Virtualized, Sustainable Massive MIMO with a Single RF Chain

Agrim Gupta<sup>†</sup> , Sajjad Nassirpour<sup>§</sup> , Manideep Dunna<sup>†</sup> , Eamon Patamasing<sup>†</sup> , Alireza Vahid<sup>§</sup> , Dinesh Bharadia<sup>†</sup> 

<sup>†</sup>University of California San Diego, <sup>§</sup>University of Colorado Denver 

{agg003,mdunna,epatamas,dineshb}@ucsd.edu,{sajjad.nassirpour,alireza.vahid}@ucdenver.edu 

## Abstract

With the turn of new decade, wireless communications face a major challenge on connecting many more new users and devices, at the same time being energy eficient and minimiz ing its carbon footprint. However, the current approaches to address the growing number of users and spectrum demands, like Massive MIMO, demand exorbitant energy consumption. The reason is that traditionally Massive MIMO requires a digital beamforming architecture that needs a separate RF chain per antenna, so the power consumption scales with number of antennas. Instead, GreenMO creates a new Massive MIMO architecture with just a single physi cally laid RF chain, shared by all the antennas and introduces for the first time, the concept of virtualizing the RF chain hardware. That is, GreenMO creates an optimal number of virtual RF chains to serve a given number of spatial streams, depending on channel conditions and network load. Due to eficient, softwarized control over the number of virtual RF chains, GreenMO paves the way for green and flexible massive MIMO. We prototype GreenMO on a PCB with eight antennas and evaluate it with a WARPv3 SDR platform in an ofice environment. The results demonstrate that GreenMO is 3× more power-eficient than traditional Massive MIMO and 4× more spectrum-eficient than traditional OFDMA systems, while multiplexing 4 spatial streams, and can save upto 50% power in modern 5G NR base stations. 

## CCS Concepts

• Networks → Wireless access points, base stations and infrastructure; • Hardware → Beamforming. 

## Keywords

Massive MIMO, 5G NR, Green Communications, Spatial Multiplexing, Digital Beamforming, Hybrid Beamforming 

## ACM Reference Format:

Agrim Gupta<sup>†</sup> , Sajjad Nassirpour<sup>§</sup> , Manideep Dunna<sup>†</sup> , Eamon Patamasing<sup>†</sup> , Alireza Vahid<sup>§</sup> , Dinesh Bharadia<sup>†</sup> . 2023. GreenMO: Enabling Virtualized, Sustainable Massive MIMO with a Single RF Chain. In The 29th Annual International Conference on Mobile Computing and Networking (ACM MobiCom ’23), October 2–6, 2023, Madrid, Spain. ACM, New York, NY, USA, 17 pages. https://doi.org/10.1145/3570361.3592509 

## 1 Introduction

Over the past decade, wireless networks have grown exponentially and thereof have accrued a humongous carbon footprint, with the net carbon emissions rivaling that of the aviation sector [1, 2]. Extensive case studies have advocated for wireless networks to ‘grow sustainably’ [3, 4], and even consumer sentiment highlights this, with more than 70% consumers willing to switch to greener alternatives [5–7]. For wireless networks, the above translates to achieving eficient use of licensed spectrum and energy at disposal. Packing more bits per unit spectrum would support the growing data-rate by achieving spectrally eficient systems. However, in communicating these more number of bits, the energy consumed should grow sub-linearly to make wireless networks energy eficient. Ideally, the future wireless networks should achieve both spectrum and energy eficiencies, and should be flexible, as user load increases/decreases, energy consumption should proportionally scale up/down. 

Existing solutions for scaling wireless networks, require multiplexing more and more data streams to handle user loads, by procuring new spectrum, or interfacing more antennas. However, these two methods largely address spectrum and energy eficiencies in isolation [8]. The most energy eficient method is by enabling frequency multiplexing, which allots diferent spectrum chunks (frequency bands) to different streams. The energy eficiency stems from the fact that single antenna systems sufice to implement frequency multiplexing, and form the simplest possible hardware with the least complexity. Further, the power consumption can be scaled up/down eficiently by communicating with more/ less spectrum bands with the single antenna. In comparison, spatial multiplexing allows multiple streams to be communicated over the same shared spectrum band, by using diferent spatial beams created via a multi-antenna array. However, the multi-antenna array increases the hardware complex ity of spatial multiplexing, resulting in higher energy con sumption than the single-antenna frequency multiplexing counterpart, as well as reduces flexibility in scaling the an tenna array energy consumption up/down in accordance to network load. 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/13fdc37572612c3f16f97404eddcb0c5bb6a46983de746c2ef7ad2284f8de144.jpg)



Figure 1: (a) GreenMO can break the SE-EE tradeof by creating a single-antenna like power consumption MIMO architecture (b) GreenMO achieves this by using single antenna RF chain hardware and sharing it across multiple antennas. This is enabled by analog-spreading blocks that accommodate multiple spatial beams into a single wide bandwidth stream, which later can be de-spread to form ‘virtual RF chains’. These multiple spatial beams are optimized per virtual RF chain using Binarized Analog Beamforming (BABF) approach so that a simple <sup>??</sup> × <sup>??</sup> MIMO processing block eliminates interference and recovers the original spatial streams


This lack of flexibility and increased power consumption, can be clearly observed with Massive MIMO (mMIMO) or Extreme MIMO, which is the most popular approach today for creating spatial multiplexing of wireless signals [9–12]. It requires a large number of antennas M>> N , to serve ?? spatially multiplexed streams by creating narrow independent spatial beams. There are two popular architectures for achieving this: Digital Beamforming (DBF) [13–20] and Hybrid Analog-Digital Beamforming (HBF) [21–32]. DBF and HBF both require multiple radio frequency (RF) chains to enable spatial multiplexing, but with diferent trade-ofs. Most commercial mMIMO architectures today implement DBF [13, 14, 33], since it provides individual control over each antenna. However, it requires a large number of RF chains, ?? which consume antenna-proportionate power to just communicate ?? streams. On the other hand, HBF uses an analog network to map ?? antennas to ?? RF chains, resulting in lower energy consumption. However, HBFs are not flexible, because if the number of streams increase to ?? ′ > ?? , it can’t increase the number of RF chains to meet the increased network load, since this is hard-coded to ?? outputs of the analog network. Despite their advantages, both DBF and HBF require additional hardware to interface multiple RF chains/analog networks, which leads to increased power consumption. This makes both these techniques far from achieving the energy eficiency, simplicity and flexibility of a single antenna counterpart (Fig. 1 a). Hence, a new class of MIMO architectures are needed which can operate at energy eficiencies closer to single antenna systems.

In this paper, we present the design and prototype of GreenMO, a new mMIMO architecture. GreenMO uses just a single RF chain, similar to single antenna frequency multiplexing (achieving EE), but can support a massive antenna array capable of delivering spatial multiplexing (achieving SE). To achieve GreenMO, our key insight is that <sup>??</sup> spatial streams generated by the multi-antenna system can be simply interfaced via a <sup>??</sup> × bandwidth ‘single’ RF chain instead of needing <sup>??</sup> separate physical RF chains. GreenMO’s overview is visually illustrated in Fig. 1b, and consists of three key components, analog-spreader per-antenna, a digital despreader and binarized analog-beamformer (BABF) algorithm to control the spreader de-spreader blocks. GreenMO’s ultra-low powered analog spreader network configures the <sup>?? >> ??</sup> antenna array to create <sup>??</sup> spatial beams which are all packed into a single <sup>??</sup> × wider bandwidth stream. Then, in the digital domain, GreenMO’s de-spreader unpacks these <sup>??</sup> spatial beams from the shared <sup>??</sup> × bandwidth single RF chain interface. Essentially, the de-spreader isolates the paths to the <sup>??</sup> antenna-array configurations that create these <sup>??</sup> spatial beams in digital-domain, which we refer to as ‘virtual RF chains’. The <sup>??</sup> virtual RF chains created are fed to a standard <sup>??</sup> × <sup>??</sup> MIMO processing block that removes residual interference and finally recovers the <sup>??</sup> streams’ data. GreenMO optimizes the selection of <sup>??</sup> antennas for each of these <sup>??</sup> virtual RF chains, using BABF approach to ensure that the recovered spatial streams after MIMO processing have negligible interference. Because of the ‘virtual RF chain’ abstraction, GreenMO attains flexibility in addition to maximizing SE and EE, since it can tune the number of virtual RF chains in response to network load and optimize the power consumption by scaling up/down appropriately. 

The first key-challenge in GreenMO’s design is how to pack the <sup>??</sup> spatial beams within a single RF chain? The key idea is to accommodate the individual <sup>??</sup> bandwidth <sup>??</sup> spatial beams by spreading the bandwidth to <sup>??</sup> <sup>??</sup> bandwidth in the analog domain, which would allow interfacing these <sup>??</sup> beams with the single <sup>??</sup> <sup>??</sup> bandwidth RF chain. This analog frequency spreading efect is created by passing each antenna’s signals via ‘faster-than-bandwidth RF switches’ with active power draw <sup><</sup> 1mW. These switches multiply the antenna signals with sub-sample level time period bi nary on-of spreading codes in time domain. In frequency domain, these spreading codes get convolved with the an tenna signals which shifts signals to higher-frequency har monics of the binary on-of spreading codes. Basically, these high frequency harmonics efect helps GreenMO to shift (or spread) the original narrow bandwidth antenna signals into a wider bandwidth. By careful duty cycling, GreenMO’s analog spreader can achieve an ideal spreading efect with minimal insertion/conversion losses. Further, we show that the analog spreader can create similar spreading efect but with varying phase responses, via <sup>??</sup> distinct orthogonal spreading codes. Hence, by utilizing these <sup>??</sup> orthogonal spreading codes with varying phase responses, GreenMO can set the array into <sup>??</sup> configurations that generate these <sup>??</sup> spatial beams, which get interfaced via a single <sup>??</sup> <sup>??</sup> bandwidth RF chain. 

The second challenge GreenMO’s design is how to create the <sup>??</sup> virtual RF chains from the analog spreaded <sup>??</sup> <sup>??</sup> band width? GreenMO’s insight here is that the varying phase response of the <sup>??</sup> orthogonal spreading codes infact leads to orthogonalization in the discrete sampled time domain. The de-spreader can splices these <sup>??</sup> <sup>??</sup> digitized samples at the corresponding orthogonalized time samples of the <sup>??</sup> codes, which also downsamples to bring the signals back to <sup>??</sup> bandwidth. Hence, this step isolates the <sup>??</sup> spatial beams created by the analog-spreader network via the <sup>??</sup> spreading codes. These <sup>??</sup> spatial beams output from the de-spreader block are also referred to as ‘virtual RF chains’ since they form the <sup>??</sup> paths to the antenna array configurations generating these <sup>??</sup> beams. Finally, these <sup>??</sup> <sup>??</sup> bandwidth virtual RF chains are fed to a traditional <sup>??</sup> × <sup>??</sup> MIMO processing block to recover the <sup>??</sup> spatial streams’ <sup>??</sup> bandwidth data by removing residual interference between the spatial beams carried over via the virtual RF chains. 

Finally, GreenMO configures the analog spreader network to optimize the <sup>??</sup> antennas to create the best <sup>??</sup> spatial beams, which atop the MIMO processing recovers the spatial streams with minimal interference. To achieve this, GreenMO opti mizes each virtual RF chain to create a spatial beam that beamforms towards one particular stream. Further, we show that this beamforming can be achieved by having all <sup>??</sup> antennas available for all the <sup>??</sup> virtual RF chains. That is, GreenMO does not split <sup>??</sup> antennas across <sup>??</sup> virtual chains. This is made possible by the orthogonality of the spreading codes, in the way that we can add to codes together for an antenna so that it shows up in both the spliced samples of virtual RF chain created by these codes. For the optimiza tion of which antennas form a part of a particular virtual 

RF chain, GreenMO chooses the maximally co-phased group of antennas for a particular stream, which basically ends up beamforming towards that particular stream, albeit with binary 0-1 control over each antenna dubbed as BABF (Binarized Analog Beamforming). BABF allows GreenMO to create narrower <sup>??</sup> spatial beams by using more number of <sup>??</sup> antennas, than <sup>??</sup> virtual RF chains. These beams are narrow enough to be fed to a $N \times N$ MIMO processing block which easily removes any residual interference. 

We implement GreenMO hardware and software prototype implementation with <sup>??</sup> = 8 antennas to flexibly serve 2<sup>,</sup> 3<sup>,</sup> 4 streams, as desired by network provider. We deploy GreenMO in indoor environments over multiple radio locations to emulate diferent streams, and benchmark against the traditional mMIMO architecture and frequency multiplexing. Our key results demonstrate similar performance metrics as compared with traditional mMIMO architecture with 3× less power requirements, achieving the same network capacity as compared to frequency multiplexing with 4× lesser spectrum requirements, which experimentally confirm the spectral eficiency and stream-proportionate energy consumption. At the same time, we show that GreenMO can be used for small-scale MIMO in smartphones, where it can increase the throughput by 3× in an energy-proportionate manner without demanding wider spectrum. Finally, we end with a case study on how GreenMO can achieve similar bitrates as compared to current 5G NR mMIMO base stations at 1<sup>.</sup>8x energy eficiency. With base-stations contributing to 70% of the power consumption in today’s mobile networks [34–36], GreenMO’s 1<sup>.</sup>8x power savings could have tremendous implications in future base station designs. 

## 2 Background: The push to reduce RF chains while enabling Massive MIMO

We will briefly go over the background on why we need Massive MIMO, and how there have been attempts to reduce the Massive MIMO energy consumption. Past approaches have either proposed turning of interfacing hardware (RF chains) when not in need, or developing hybrid analog-digital architectures with reduced number of RF chains, unlike GreenMO which enables Massive MIMO with just a single RF chain. 

The need for Massive MIMO (mMIMO) is quite evident from history of MIMO deployments. mu-MIMO (multi-user MIMO) which utilized <sup>??</sup> antennas for <sup>??</sup> spatial streams [19, 20, 22, 37] was largely unsuccessful, since <sup>??</sup> antennas create ‘broad’ <sup>??</sup> spatial beams, resulting in substantial interference. Unlike mu-MIMO, mMIMO (Massive MIMO) uses massive number of antennas $M \ > > \ N$ to create the required narrow <sup>??</sup> beams for spatial streams with negligible interference. mMIMO has popularly adopted Digital Beamforming(DBF) [15–20] architecture, which interfaces each antenna digitally via a separate RF chain per-antenna. 

This makes the power consumption antenna-proportionate (<sup>??</sup>×) [28–30] just to get <sup>??</sup> spatial streams. Thus, the mMIMO energy eficiency depends largely on the RF chain power con sumption required per-antenna [38–41]. 

To reduce the power consumption, past approaches have proposed turning-of RF chains depending on networkload [42–45], or use low-bit ADCs in the RF chains [46–49]. Turning of RF chains adaptively in response to network load is compounded because often mMIMO systems have Base Band Units (BBU) implemented in-chip. Hence, only the gen erated <sup>??</sup> spatial-streams are backhauled instead of <sup>??</sup> per antenna streams [13, 15], which requires to build the intelligence of adaptively turning of antennas/RF chains in-chip. Further, turning of RF chains reduces the array gain which leads to problems in link-budget especially in uplink limited cellular systems [50]. Low-bit ADCs bring forth reduced sup port for higher constellations, and increased quantization noises, which reduces mMIMO spectrum eficiency[47, 48] to get lower power consumption. 

An alternate approach to reduce power consumption is by mapping the the large number of <sup>??</sup> antennas to smaller number of <sup>??</sup> RF chains, usually via a phase-shifter analog network. Then, digital processing atop these analog network mapped <sup>??</sup> RF chains, creates the <sup>??</sup> spatial streams, and hence this approach is referred to as ‘Hybrid beamformers (HBF)’. The phase-shifter analog network ensures the array gains are kept high, and limit issues with turning of RF chains, with a large body of works on creating diferent analog networks like fully-connected, partially-connected to address diferent link budgets [21–32]. However, these analog networks make HBF’s rigid, as they are constructed to optimize power consumption for a fixed <sup>??</sup> , and can not be adapted easily to increase the number of RF chains if number of streams exceed N. In addition to rigidity, the analog networks in HBFs have high insertion losses, both due to the hardware ineficiency, as well as fundamentally due to large amounts of signal splitting to create the complicated analog network topology (can go >10dB [16, 22, 46]). These losses need to be compensated appropriately with separate amplifiers [16, 46], which ends up increasing the power-consumption. Hence even though the HBFs reduce RF chains to a smaller-fixed <sup>??</sup> number, they fail to do-so flexibly and often this reduction comes at a cost of increased analog-network power consumption, and thus are not as low-powered as single antenna counterparts. 

In contrast to existing classes of fully digital and HBF approaches, GreenMO creates a new mMIMO architecture that minimizes circuit power consumption to single antenna interfacing level. Instead of using multiple physically laid RF chains to serve $M > > N$ antennas, GreenMO connects these <sup>??</sup> antennas to just 1 RF chain using a ‘analog-spreading network’ which can create <sup>??</sup> ‘virtual RF chains’ over the single 

RF chain by spreading it’s analog bandwidth. The number of virtual RF chains (<sup>??</sup> ) in GreenMO depends on how much bandwidth is spread by the analog network. This enables <sup>??</sup> to be easily adjusted based on network load, by tuning the bandwidth of the single RF chain via software. We also show that this analog-spreading network connecting <sup>??</sup> antennas to 1 RF chain, can be implemented with ultra-low circuit power, and negligible insertion losses. Hence, GreenMO paves the way for flexible mMIMO architectures, with power consumption akin to single antenna counterparts. 

## 3 Design

GreenMO designs a new MIMO architecture which enables spatial multiplexing with a single RF chain and maximises both energy and spectrum eficiency (EE & SE). In this section, we will describe the three key ideas which enable GreenMO to create <sup>??</sup> spatial streams from just 1 RF chain: (1) analog spreading with <sup>??</sup> orthogonal codes that allows configuring <sup>??</sup> antenna array (<sup>?? >> ??</sup> ) into <sup>??</sup> groups, (2) corresponding digital de-spreading to isolate these <sup>??</sup> groups, which creates a virtual path (virtual RF chain) to each of the antenna groups, and finally, (3) the BABF approach to determine which <sup>??</sup> antennas are selected in the <sup>??</sup> groups to minimize the interference between the <sup>??</sup> streams. GreenMO’s design overview is also visually illustrated in Fig. 1(b). 

## 3.1 How to create analog spreading efect in hardware with minimal power overhead hardware with minimal power overhead

To practically realize the analog spreading block, GreenMO needs to consider two requirements. First requirement is that the spreading efect has to be created right next to antenna in the RF domain, before the signals across the antennas are combined. Hence, it rules out any simple baseband frequency spreading circuits. Second requirement is that the analog spreading unit need to have almost-zero, or minimal power consumption (denoted as $P _ { \mathrm { a n a l o g ~ s p r e a d i n g } } )$ as compared to power in the single RF chain (denoted as $P _ { 1 \mathrm { R F C h a i n } } )$ This is because $P _ { \mathrm { G r e e n M O } } ~ = ~ M P _ { \mathrm { a n a l o g ~ s p r e a d i n g } } + P _ { 1 }$ <sub>RF</sub> <sub>Chain</sub>, as <sup>??</sup> antennas are passive entities and there are only the analog spreading units needed per-antenna as other active elements apart from the single RF chain. We require ??<sub>analog</sub> <sub>spreading</sub> $< < P _ { 1 }$ <sub>RF</sub> <sub>Chain</sub>, so that $P _ { \mathrm { G r e e n M O } } \approx P _ { 1 }$ <sub>RF</sub> <sub>Chain</sub>, and GreenMO achieves the same EE as compared to a single antenna single RF chain counterpart. 

A naive approach here would be to use frequency mixers to create the desired frequency spreading efect. Although mixers by themselves can be passive circuits, they typically have considerable frequency conversion losses of about 5- 10 dB[51, 52]. Thus, a mixer spreading unit would require per-antenna amplifiers (PA/LNA) to ofset these insertion losses. Hence, even though mixers can work right at the RF level, it does not fit the second requirement due to the conversion losses. Instead, GreenMO’s insight is that both the requirements can be met by taking a leaf out of backscatter systems, which face similar constraints on RF circuits that shift frequencies to nearby channels [53–57]. These backscat ter systems also need near zero power power operation to justify batteryless operation, and can not tolerate insertion losses which would lead to reduced reflected signal power. RF switches have minimal insertion losses, <1 dB, and hence do not require amplification (LNAs/PAs). As a consequence, backscatter systems use simple RF switches, instead of mixers to meet these requirements. 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/d9a5377bf3bfa004f3cc44591990707c5de9a5d86c53cade2ca8fbc16e7aa324.jpg)



1. Antenna 2. RF Switch 3. Signal after switch: s(t).c(t) 4. Eventual digitization at receives S(f) toggles at c(t) => S(f)*C(f) in freq. domain 4B shows spreaded signal Figure 2: How RF switches create the required analog spreading efect


Also, RF switches work directly at the RF frequencies as they have the capability to toggle the impinging RF signals on and of. Further, this on-of toggling if done periodically with a on-of square wave of certain frequency create harmonics and spreads the signals. Now, in order to spread the band width from <sup>??</sup> to <sup>??</sup> <sup>??</sup>, the RF switches would need need to im plement switching clocks with frequencies of the order of <sup>??</sup>, which would create integer harmonics at <sup>????</sup> and thus spread the signals via these harmonics. Hence, the active power draw, which is proportional to the clock frequency, would be in order of bandwidth (<sup>??</sup> (<sup>??</sup>)) for the RF switches, instead of center frequency (<sup>??</sup> (<sup>??</sup>??)) as compared to up/down conversion mixers in the single RF chain. Since the active power draw is proportional to clock frequency, the analog spreading operation of the RF switcher per-antenna, will have orders of magnitude lower active power draw than the single up/downconversion chain (<sup>??</sup><sub>analog-spreading</sub> <sub>RF</sub> <sub>switches</sub> $< < P _ { 1 \mathrm { R F c h a i n } } )$ . This is because typically <sup>??</sup> is just a small fraction of <sup>??</sup>?? , for eg, in Wi-Fi $f _ { c } = 2 . 4 / 5$ GHz whereas $B \leq 1 2 0 ~ \mathrm { M H z }$ 

To explicitly show how GreenMO uses RF switches as analog spreading unit, we model the signal at antenna to be <sup>??</sup> (<sup>??</sup>), which goes through RF switch toggling a periodic on-of wave given by <sup>??</sup> (<sup>??</sup>). Due to switching, we get multiplication in time domain <sup>??</sup> (<sup>??</sup> )<sup>??</sup> (<sup>??</sup> ), corresponding to convolution in fre quency domain $S ( f ) * C ( f )$ . If we take a 1/<sup>??</sup> time period on of sequence <sup>??</sup> (<sup>??</sup>) it will fundamental frequency as <sup>??</sup>. However, the <sup>??</sup> frequency on-of codes will have harmonics at integral multiples of <sup>??</sup> which would spread the signal much beyond the nyquist period [−<sup>??</sup> <sup>??</sup>/2<sup>,</sup> <sup>??</sup> <sup>??</sup>/2). This is visually illustrated in Fig. 2 for <sup>??</sup> = 4. 

So a natural question is how do we obtain the required spreading efect only between [−<sup>??</sup> <sup>??</sup>/2<sup>,</sup> <sup>??</sup> <sup>??</sup>/2) and remove the non-linearities? A naive solution is to perform low pass filtering for the band of interest [−2<sup>??,</sup> 2<sup>??</sup>) before sampling to eliminate these copies altogether. However, this would waste the signal power which has landed beyond the band, as these would just get filtered out. Instead, we realize that the non-linearities created by switching can be harnessed in a powerful way by simple sampling process. We make the observation that by sampling at <sup>??</sup> <sup>??</sup> rate, a 1/<sup>??</sup> duty cycled code of <sup>??</sup> frequency basically gives equal harmonics at integral frequencies in the required nyquist range. For more details please refer to supplemental material containing the mathematical proof [58]. This is because the other harmonic components simply alias on top of the required peaks in the [−<sup>??</sup> <sup>??</sup>/2<sup>,</sup> <sup>??</sup> <sup>??</sup>/2) (shown visually via folding arrows in Fig. 2 for <sup>??</sup> = 4). Hence, instead of filtering these non-linearities, by simply sampling them via <sup>??</sup> <sup>??</sup> ADC these harmonics fold on top of each other and thus make the system eficient by not wasting any received signal power in filtering. 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/b0105c045b41cad4638168267f075083b70df15ff70baa721db4e24768cc972d.jpg)



Figure 3: GreenMO on-of spreading codes: continuous and discrete time


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/57c8dfe9a89db79e6fe609ffde4f968cbb02de495adafffe39cbd976956a2f29.jpg)



Figure 4: GreenMO’s digital de-spreader works by de-interleaving the timedomain samples which isolates + downsamples each code


Hence, as a first step towards serving <sup>??</sup> streams with a single RF chain, GreenMO uses RF switches to spread each antenna signals into <sup>??</sup> <sup>??</sup> bandwidth, and further achieves this at minimal power overhead and eficiently without substantial insertion/conversion losses. This is possible by careful duty cycling of the switching clock, such that the created harmonic distortions alias on top of each other to make the spreading process eficient. 

## 3.2 ‘N’ configurable analog spreader, despreader to create <sup>??</sup> virtual RF chains

So far, we have seen how the RF switches can act as minimal power analog spreading units. Next, we will show the <sup>??</sup> configurability of this analog spreading efect, that allows GreenMO to set the <sup>??</sup> antenna array into <sup>??</sup> diferent groups, and the corresponding digital de-spreading, to enable the creation of <sup>??</sup> virtual RF chains serving each group. 

The key-idea behind the generation of <sup>??</sup> virtual RF chains is that <sup>??</sup> → <sup>??</sup> <sup>??</sup> bandwidth spreading can be performed via <sup>??</sup> discrete time sampled orthogonal codes. These <sup>??</sup> orthogonal codes are shown in Fig. 3a, labeled from $c _ { 1 } , c _ { 2 } \dots c _ { N } ,$ each having same frequency <sup>??</sup>, duty-cycle $1 / N$ but having diferent initial phases. When these codes are sampled with <sup>??</sup> <sup>??</sup> bandwidth, (Discrete time sampled code waveforms, Fig. 3b), $c _ { 1 }$ is on for every <sup>?? ??</sup> samples, $c _ { 2 }$ is on for $N i + 1 \ ( i$ is just a sampling index) samples and generalizing $c _ { j }$ is on for $N i + j - 1$ samples. As seen in Fig. 3c-d, these codes share similar magnitude response but a diferent phase response, as a consequence of having diferent ‘on’ sample indexes. That is, $c _ { j }$ has phases $\frac { \pi } { N } * i * j$ for diferent <sup>??</sup> denoting the <sup>??</sup> delta functions $- N B / 2 , - ( N - 1 ) B / 2 , \dots ( N - 1 ) B / 2 .$ . These codes can be de-spread in frequency domain by inverting a bunch of linear equations, as the codes form an inverse ma trix relation because each $c _ { j } { ' } s$ phase response follow a roots of unity sequence (Refer to supplemental material, [58] for details). However, the equivalent time-domain de-spreading is more straightforward, since difering phase response more naturally shows up as orthogonalized time samples. 

In order to de-spread the codes in time-domain, the digital de-spreader basically collects every $N i + j - 1$ samples to create the <sup>??</sup>-th virtual RF chain corresponding to $c _ { j } .$ . This ends up downsampling the <sup>??</sup> <sup>??</sup> signals into <sup>??</sup>, as well as isolating the diferent coded samples. That is, to de-spread $c _ { j } { ' } s$ we col lect the $N i + j - 1$ samples, which ends up removing the ‘of samples of $c _ { j }$ and preserves only the ‘on’ samples (downsam pling), and because no other code is on for $N i + j - 1$ samples, also isolates $\boldsymbol { c _ { j } } ^ { \prime }$ s coded signal. To simplify the description, we first consider 1 antenna per group, and show the general ized multi-antenna per group in the next sub-section. The $M = 4$ example is depicted in Fig. 4, where these 4 antennas share a single 4<sup>??</sup> RF chain. The signals at each antenna pass through the respective $N = 4$ orthogonal spreading codes per-antenna, and get-combined. Now, the digital de-spreader needs to isolate the original signals at each antenna, and it works by collecting the 4<sup>??,</sup> $4 n + 1 , 4 n + 2 , 4 n + 3$ samples to de-spread $c _ { 0 } , c _ { 1 } , c _ { 2 } , c _ { 3 }$ respectively. This also ends up down sampling the 4<sup>??</sup> signal by 4 and creates the <sup>??</sup> bandwidth signal which represents a ‘virtual RF chain’ for that particular antenna. In a way, even though a separate physical path to each antenna doesn’t exist, by analog-spreading and the cor responding de-spreading, GreenMO creates a ‘virtual’ path to each antenna from the single shared RF chain. However, this requires sampling and switching clock synchronization, so that the sampling instances align with the switching in stances. This is enabled by deriving the spreading clocks <sup>??</sup> ?? from the sampling clock of the SDR itself (WARP for the current implementation), and thus the switching and sampling instances align well. 

The concept of ‘virtual RF chain’ enables separate signal path for each antenna even when they share the same downconversion chain; in a way the downconversion chain is virtualized over all the antennas. These virtual RF chains make GreenMO flexible, as GreenMO can adjust the number of virtual RF chains on the fly. That is, if the number of spatial streams required change from $N  N ^ { \prime }$ , GreenMO can respond by simply changing the sampling rate from ?? ?? <sub>to</sub> $N ^ { \prime } B _ { \mathrm { { ; } } }$ , and carve out $N ^ { \prime }$ virtual RF chains to meet the increased demand. However, in order to truly enable this flexibility, GreenMO needs to generalize to these situations where number of antennas $M \ne N$ . In a way, the $M = N$ antenna version of GreenMO enables a single virtual RF chain counterpart of a standard Digital beamformer (DBF), since one antenna is interfaced per virtual RF chains. In the next section, we show GreenMO goes beyond just mimicking a DBF, and can use lot more antennas than virtual RF chains $M > N$ to create narrower beams from the <sup>??</sup> antennas and support <sup>??</sup> spatial streams by using just <sup>??</sup> <sup>??</sup> sampled single RF chain connecting each of these <sup>??</sup> antennas. 

## 3.3 Utilizing <sup>?? > ??</sup> antennas per virtual RF Chain for interference-free <sup>??</sup> streams

Having described how analog spreading, digital de-spreading allows GreenMO to create <sup>??</sup> virtual RF chains (virtual paths to antennas), we will now show how we can interface many more antennas $M > N$ to these <sup>??</sup> virtual RF chains. The key insight to this generalization is the fact , we can turn ‘on’ multiple antennas per virtual RF chain instead, and also, an antenna can simultaneously be ‘on’ for multiple virtual RF chains. This multiple antenna to multiple virtual RF chain mapping is enabled by the orthogonality of the toggling sequences $c _ { j } .$ That ${ \mathrm { i } } s ,$ if we want to turn on antennas $i _ { 1 } , i _ { 2 } , i _ { 3 }$ for the virtual RF chain created by $c _ { j } .$ , we can supply the $c _ { j }$ clock to each of these antennas indexed via $i _ { 1 } , i _ { 2 } , i _ { 3 }$ . If a particular <sup>??</sup>-th antenna has to be turned on for $j _ { 1 } , j _ { 2 } , j _ { 3 }$ virtual RF chains, we can supply clocks $c _ { j _ { 1 } } + c _ { j _ { 2 } } + c _ { j _ { 3 } }$ to that antenna. Since $c _ { j _ { 1 } } , c _ { j _ { 2 } }$ and $c _ { j _ { 3 } }$ don’t overlap in time, adding these codes together would create a new toggling sequence which would be ‘on’ for $N k + j _ { 1 } - 1 , N k + j _ { 2 } - 1 , N k + j _ { 3 } - 1$ samples and hence turn on this antenna for all these 3 virtual RF chains. This is illustrated visually via right-bottom inset in Fig. 5. 

This many-to-many mapping of antennas to virtual RF chains can be represented in a matrix form, where the switching network allows us to implement a binary matrix $\mathbf { S } \in \lbrace 0 , \bar { 1 } \rbrace ^ { M * N }$ in analog domain, <sup>??</sup> being the number of antennas and <sup>??</sup> being the number of streams, as well as the number of virtual RF chains to keep the power-consumption streams-proportionate. Basically, this matrix projects the higher dimensional channel H which is complex valued ${ \mathbf { C } } ^ { \breve { N } * M }$ which represents the amplitude and phase of each <sup>??</sup> -th stream at <sup>??</sup>-th antenna, into an equivalent $\mathsf { C } ^ { N * N }$ channel $\tilde { \mathbf { H } } = \mathbf { H } \mathbf { S }$ by toggling antennas on-of strategically. 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/b4bd13fea75b04609ec55201db8fa7d586c4ff8e53bdee4324a4f12bbafce397.jpg)



Figure 5: How GreenMO groups antennas per virtual RF chain by adding orthogonal codes and ensuring that the co-phased antennas per-stream get grouped to provide beamforming gain


Hence, GreenMO architecture projects the <sup>??</sup> ∗ <sup>??</sup> over-the air wireless channel between <sup>??</sup> streams and <sup>??</sup> antennas into <sup>??</sup> ∗ <sup>??</sup> equivalent channel between the <sup>??</sup> streams and <sup>??</sup> virtual RF chains, via S matrix implemented in analog domain by RF switches and the supplied clocks. The choice of this matrix when $M = N$ is obvious, we can just set it to identity matrix to isolate 1 antenna signals per virtual RF chain, as was also motivated in the prior sub-section. When $M > N ,$ we need to select the matrix S strategically such that we create narrower beams by projecting the higher dimen sional matrix H into a well-formed <sup>??</sup> ∗ <sup>??</sup> equivalent H<sup>˜</sup> . To do so, our insight is that since we have <sup>??</sup> virtual RF chains for <sup>??</sup> streams, we can use the higher number of antennas to perform approximate on-of beamforming towards one stream per virtual RF chain. That is, for virtual RF chain <sup>??</sup>, we basically turn ‘on’ the maximal set of antennas inphase for <sup>??</sup>-th stream, so that the signal power for user <sup>??</sup> is boosted for <sup>??</sup>-th virtual chain. This is visually illustrated via right-top inset in Fig. 5, with an example of virtual RF chain antenna configuration for blue stream. We dub this selection of the matrix S which implements per-stream beam forming as BABF approach (Binarized analog beamforming). The BABF approach basically takes the analog beamforming weights and quantizes it to binary 0 − 1 level, so that it can be implemented in analog domain via RF switches. 

Putting it all together: So, to conclude the design sec tion, we will briefly summarize and put the various design elements in context. We showed how the analog spreading, digital de-spreading can eficiently use the <sup>??</sup> <sup>??</sup> bandwidth of single RF chain to enable <sup>??</sup> virtual RF chains. Then we 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/410b6037b995b92c7a1f1c6227c55a75f814533ce9e7a893c248aa4d2b9ff537.jpg)



Figure 6: Hardware implementation on a custom designed PCB for GreenMO showed how the per-antenna codes can be chosen such that the entire <sup>??</sup> antenna array is available to all the <sup>??</sup> virtual RF chain, by means of the switching matrix S. This allows GreenMO to use the array to beamform towards one stream per virtual chain, via the BABF approach. This analog spreading + digital de-spreading + BABF approach culminated in creation of an equivalent <sup>??</sup> ∗ <sup>??</sup> channel H<sup>˜</sup> = HS between the <sup>??</sup> streams and <sup>??</sup> virtual RF chains. This H<sup>˜</sup> can then be fed to <sup>??</sup> × <sup>??</sup> MIMO processing which would invert this $\tilde { \mathbf { H } } ^ { - 1 }$ to finally recover the spatial streams.


## 4 Implementation

We implement the GreenMO architecture on a multi-layer PCB prototype fabricated using Rogers substrate (Fig. 6), with HMC197BE [59] RF switches for analog spreading and CMOD A7 15t FPGA [60] to generate the on-of 1/<sup>??</sup> dutycycled clocks <sup>??</sup>?? for spreading and de-spreading. On the toplayer of the PCB, we have the RF plane of GreenMO ar chitecture, consisting of SMA connectors which connect to antennas, RF switches, and multi-level Wilkinson networks to interface the 8 switched antennas to the single RF chain. On the bottom layer of the PCB, we have the control plane of GreenMO architecture, consisting of CMOD-A7 FPGA attached to the PCB via header pins, which provides the spreading codes to RF switches on top layer using vias. 

We utilize WARPv3 SDR for our implementation of an uplink receiver. The sampling bandwidth for WARPv3 is 40 MHz, thus has a sampling time period of 25 ns. The HMC197BE RF switch has tRISE = 3 ns, and tON = 10 ns, sufficiently lesser than 25 ns sampling time, hence the selected switches are fast enough to perform the required switching for analog spreading. In addition, the CMOD’s spreading clock and WARPv3 sampling clock are synched to ensure digital de-spreading works as shown in Fig. 4. We achieve this synched behaviour by writing custom verilog modules on the CMOD FPGA that derive the spreading clocks <sup>??</sup>?? from WARPv3’s sampling clock. 

A Linux PC is connected to both WARPv3 (via ethernet) and CMOD FPGA (via micro usb cable), and implements the required signal processing, as well as configure CMOD and 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/2049f53c950966a62a32fb409f94d4e9fc8a72ab0796bbe23afc96d64b95fbad.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/d2362e140d7ffac095bdceba0bf3cee86398561faee5faedb2936c81001abd49.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/e2e07b3fcaca766865adacf2e66c48d619cd26b2e82684876bf8f4a8c8b8486e.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/a52bab5fa9125eda0dbdf8cb5d76af197380e31bebf76942acf183ef20ebdf92.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/545c5dc6f3580070da17f263e0248212c69e67af09b225cfcd02e0c4a355f46e.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/96daef31a2db66144194a26bdcc2645a151f44bb17ed230c57b7a031ca820538.jpg)



Figure 7: (a) Shows the frequency domain raw spreaded signal sampled via the single RF chain, with (b) shows the time domain. The created virtual RF chains are shown in (c), after BABF which increases <sup>??</sup>-th stream’s power in <sup>??</sup>-th virtual chain. Finally (d) shows the recovered streams obtained after digital combining across the virtual chains. (e) and (f) show the raw constellations before and after digital de-spreading and combining


WARP correctly to collect the sampled IQ hardware data from the single RF chain. We utilize the WARPLab codes in MATLAB on the linux $\mathrm { P C } ,$ to create 802.11 compliant OFDM waveform with 64 subcarriers (48 data, 4 pilots and 12 null subcarriers). In our hardware implementation, we test for $N = 2 , 3 ,$ 4 streams. Since the sampling bandwidth of WARPv3 platform is 40 MHz, the bandwidth of each stream is fixed to 10 MHz to support a maximum of 4 streams. These $N = 2 , 3 ,$ 4 10 MHz streams are implemented via <sup>??</sup> indepen dent USRP SBX daughterboards. We have tested the stream communication with and without these USRPs being synched to WARP and found that since GreenMO enables a spatial operation, a tight time synch is not required. Since our PCB implementation has 8 antennas, the switching matrix S is a 8 × <sup>??</sup> matrix, with each <sup>??</sup>-th row representing the on-of states of the <sup>??</sup>-th antenna for the <sup>??</sup> diferent virtual RF chains. For an example, say $N = 4$ and this row was $[ 1 , 0 , 1 , 0 ]$ , so this would simply be implemented as 1 ∗ $c _ { 0 } + 0 * c _ { 1 } + 1 * c _ { 2 } + 0 * c _ { 3 }$ Thus, in order to implement this matrix in hardware, we represent each row, which is a $M \times 1$ binary vector by a hexadecimal digit. The Linux PC communicates 8 of these hexadecimal digits representing 8 antennas’ on-of states to the FPGA via a standard UART code over the USB interface. 

GreenMO in action: A example captured over-the-air trace: A example hardware trace when <sup>??</sup> = 4 is shown in Fig. 7. By plotting the frequency domain spectrum of the sampled signal via WARP, we can see the analog spreading in action which has taken the 10 MHz interfering streams and spread it to 40 MHz (Fig. 7a). When plotted in time domain, first we can see via diferent colors in Fig. 7b the non-overlapping LTS’s per-stream to allow for channel estimation. However, the data bits transmission of all the streams overlap, as shown in red. Note that the single received trace has sample index from 0 to 4<sup>??</sup> since the single RF chain signal bandwidth is 40 MHz whereas per-stream spectrum is 10 MHz. From this 40 MHz spreaded sampled signal, we de-spread the 4 codes by isolating {4<sup>??</sup>}<sup>,</sup> {4<sup>??</sup> +1}<sup>,</sup> {4<sup>??</sup> +2}<sup>,</sup> {4<sup>??</sup> +3} samples, as shown in Fig. 7(c) to create the 4 virtual RF chains. Note that 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/4cad7cb01dd58be1348d7275f583cd7fbf8f7ac0a0e43f1daa31ee03d8314825.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/fc4d25d40598511895b7d9cbbca4c823cb7c4fc8ec0b0378e6a15ec369390dd0.jpg)


Figure 8: Conference room test setting (a), with 0<sup>,</sup> 1<sup>,</sup> <sup>.</sup> <sup>.</sup> <sup>.</sup> 9 in (b) representing the 10 configurations for the 4 radio positions emulating the 2<sup>,</sup> 3<sup>,</sup> 4 streams each virtual RF chain has sample indexes from 0 to <sup>??</sup> since we capture every 4-th sample but with diferent starting sample in the process of virtual RF chain isolation. We see that in a virtual RF chain, one stream’s power is prioritized (by observing the per-stream LTS power levels) because of strategic antenna grouping per virtual RF chain. 

Finally, this equivalent H<sup>˜</sup> = HS channel created in the 4 virtual RF chains, is inverted to get Fig. 7d. We can see that the interference is almost pushed to noise floor, since the LTS’s of other streams are almost completely cancelled out. When the data is decoded after channel inversion, we recover the transmitted QAM-16 constellation in each stream, as shown in Fig. 7f. Hence, this example trace shows how GreenMO works end-to-end to enable 4 spatially multiplexed interfering 10 MHz streams from a single 40 MHz RF chain. 

## 5 Evaluations

So far, we have described the design, implementation and how GreenMO works via a example captured trace. In this section, we will go over various experiments and ablation studies performed to verify GreenMO’s design choices and showcase GreenMO’s key-result of achieving both energy & spectrum eficiency. First, we will go over the experimental setting, then compare GreenMO’s performance metrics (en ergy/spectrum usage and obtained throughput) to various baselines and conclude by presenting ablation studies. 

(a) Evaluation setting: To evaluate GreenMO, we consider a ofice environment (conference room setting, 12m*5m dimensions, Fig. 8a) with TV screens/desks/whiteboards which act as reflectors and make it a rich multipath setting. We fix the location of GreenMO PCB, which acts as an AP, roughly in middle of the room. The positions of USRP radios which generate 2<sup>,</sup> 3<sup>,</sup> 4 streams (depending on evaluation scenario) communicated to the AP are varied across 10 configurations scattered around the room. We verify the narrowness of beams generated by GreenMO by evaluat ing SINR (Signal to Interference+Noise ratio) across these 10 configurations, having diferent degrees of proximity between the radios. For the experiments we set the transmit power such that we have average SISO SNR of about 15 dB, and utilize QAM-16 constellation with 0.5 rate convolutional code. From the controlled 15 dB SNR, the net maximum capacity achievable is $4 * 1 0 \log _ { 2 } ( 1 0 ^ { 1 . 5 } )$ ≈ 200 Mbps, when the maximum number of 4 streams are communicated. At 15 dB SNR, the recommended MCS would be QAM-16 with 0.5 rate code[61], which achieves about 48 Mbps goodput. This choice of SNRs, as well as constellation is consistent with the recent works on Massive MIMO systems [15]. 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/bddfc8438be4c6cbe5faecbeb8234d52bd6f9162b8e53c3257c56ce08d48daa7.jpg)



(a) Spectrum eficiency


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/c5a542f4cd70450e510bc9e15957b9444cb1430304a6a5f4da70e6b2bfcb0d8a.jpg)



(b) Energy Eficiency


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/eccfc5ef1667cc84cbd44768f3fb483bd9a00756c43203c480c3cacda5ca3aaf.jpg)



(c) Trace level DBF comparisons


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/9e58eff6ac5c039b0eb76201ee1917ac1d33d815e9660e79c322dceeb64c04af.jpg)



(d) Trace level HBF comparisons



Figure 9: GreenMO vs baseliness: GreenMO comes close to upper bounds for both SE and EE measurements (a-b). The SE is upper bounded by energy ineficient 8 Antenna DBF and FC HBF, whereas the EE is upper bounded by spectrally ineficient FDMA. From (c-d), we see that GreenMO achieves median SINR close to 15 dB by using just 4 virtual RF chains, and comes about 3 dB close to 8 Ant DBF, FC HBF. We see that PC HBF has SINR almost similar to 4 Ant DBF. In (d) M-K-N means M total antennas, with K antennas in 1 RF Chain and total N RF chains. Thus 8-2-4 represents a PC HBF with 2 antennas per RF chain, 8-8-4 represents a FC HBF.


We compare GreenMO’s single RF chain spatial multiplexed interfering streams with multi-RF chain spatial ap proaches like 4 antenna & 8 antenna digital beamformers (DBF), as well as 8 → 4 partially and fully connected hybrid beamformers (PC/FC HBF), and single antenna frequency multiplexed (FDMA) streams as well. The FDMA and 4 an tenna DBF baselines are implemented on the same WARP hardware as well. However for 8 antenna DBF, the results are evaluated via trace level emulations, by collecting channels the 8 antennas using RF-switches which connect 4 antennas at a time to WARP, since WARP doesn’t have 8 separate RF chains. Further, we evaluate HBF results via trace-driven em ulations as well, by mapping the 8 antenna hardware traces to <sup>??</sup> combined traces $( N = 2 , 3 , 4 )$ via network of phase shifters. In the trace-driven HBF emulations, phase shifters are assumed to have no quantization errors for simplicity. 

(b.i) Spectral Eficiency (SE), Fig. 9a: To calculate SE (bits per Hz), we divide the obtained goodput (Mbps) and the utilized RF spectrum (MHz). FDMA easily achieves the desired goodputs of 24<sup>,</sup> 36<sup>,</sup> 48 Mbps while communicating 2<sup>,</sup> 3<sup>,</sup> 4 streams and using 20<sup>,</sup> 30<sup>,</sup> 40 MHz spectrum, since each stream occupies non-interfering 10 MHz spectrum chunks having the SISO SNR of 15dB each. Thus, FDMA SE remains constant, as to create more streams, it needs more spectrum chunks. Instead, DBF/HBF/GreenMO approaches utilize the same 10 MHz spectrum chunks and fit multiple streams via spatial multiplexing. In the trace driven simulation we observe that by using 8 antennas, DBF meets the median SINR requirements of 15 dB (Fig. 9c). Further, a fully connected HBF which would map the 8 antennas to all 4 RF chains, also obtains median SINR>15 dB (Fig. 9d). Hence both 8 antenna DBF and FC HBF would obtain the ideal goodput metrics (Table 1) and form the oracle baselines for SE calculations. 


Table 1: Power consumption calculations and Goodput measurements


<table><tr><td rowspan="2">Architect-ture</td><td rowspan="2">Num. streams</td><td rowspan="2">Spectrum used (MHz)</td><td colspan="4">Power Consumption</td><td rowspan="2">Good-put (mbps)</td></tr><tr><td>AA (mW)</td><td>RFE (mW)</td><td>ADC (mW)</td><td>Total (mW)</td></tr><tr><td rowspan="3">8 Ant GreenMO</td><td>2</td><td>10</td><td>8</td><td>354</td><td>200</td><td>562</td><td>~ 24</td></tr><tr><td>3</td><td>10</td><td>8</td><td>354</td><td>300</td><td>662</td><td>~ 36</td></tr><tr><td>4</td><td>10</td><td>8</td><td>354</td><td>400</td><td>762</td><td><eq>{47} \pm {0.65}</eq></td></tr><tr><td rowspan="3">FDMA</td><td>2</td><td>20</td><td>-</td><td>354</td><td>200</td><td>554</td><td>~ 24</td></tr><tr><td>3</td><td>30</td><td>-</td><td>354</td><td>300</td><td>654</td><td>~ 36</td></tr><tr><td>4</td><td>40</td><td>-</td><td>354</td><td>400</td><td>754</td><td>~ 48</td></tr><tr><td rowspan="3">4 Ant. DBF</td><td>2</td><td>10</td><td>-</td><td>1632</td><td>400</td><td>2032</td><td>~ 24</td></tr><tr><td>3</td><td>10</td><td>-</td><td>1632</td><td>400</td><td>2032</td><td><eq>{33} \pm {2.3}</eq></td></tr><tr><td>4</td><td>10</td><td>-</td><td>1632</td><td>400</td><td>2032</td><td><eq>{39} \pm {4.3}</eq></td></tr><tr><td rowspan="3">8 Ant. DBF (Trace)</td><td>2</td><td>10</td><td>-</td><td>3264</td><td>800</td><td>4064</td><td>~ 24</td></tr><tr><td>3</td><td>10</td><td>-</td><td>3264</td><td>800</td><td>4064</td><td>~ 36</td></tr><tr><td>4</td><td>10</td><td>-</td><td>3264</td><td>800</td><td>4064</td><td>~ 48</td></tr><tr><td rowspan="3">8 Ant PC HBF (Trace)</td><td>2</td><td>10</td><td>40</td><td>816</td><td>200</td><td>1056</td><td>~ 24</td></tr><tr><td>3</td><td>10</td><td>60</td><td>1224</td><td>300</td><td>1584</td><td><eq>{33} \pm {2.3}</eq></td></tr><tr><td>4</td><td>10</td><td>80</td><td>1632</td><td>400</td><td>2132</td><td><eq>{39} \pm {4.3}</eq></td></tr><tr><td rowspan="3">8 Ant FC HBF (Trace)</td><td>2</td><td>10</td><td>160</td><td>816</td><td>200</td><td>1176</td><td>~ 24</td></tr><tr><td>3</td><td>10</td><td>240</td><td>1224</td><td>300</td><td>1764</td><td>~ 36</td></tr><tr><td>4</td><td>10</td><td>320</td><td>1632</td><td>400</td><td>2352</td><td>~ 48</td></tr></table>

In comparison, the median SINR achieved by 8 antenna GreenMO, while using just 4 virtual RF chains (VRFs) is only about 2 dB lower than 15dB SNR level (Fig. 9c), and hence the goodput measurements are only slightly of for 4 streams, about 47 ± 0<sup>.</sup>65 Mbps (Table 1), whereas for 2<sup>,</sup> 3 streams they are ideal 24<sup>,</sup> 36 Mbps. However, the 4 antenna DBF, PC HBF are quite of from the oracle baselines, as they only use 1/2 antennas per RF chain respectively, resulting in broader beams and hence higher interference and bit-errors. 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/859b03373fe296fb705ab2b6466823964257b94b9b0d5492c39eda09c3c3ad63.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/d87d96576d9febede24defb81eae57f58d8844e0cdc910f440a9c72a42b1f0c4.jpg)



(a) GreenMO achieves target SINR (b) GreenMO achieves target goodput Figure 10: Increasing number of antennas improves SINR and goodput


(b.ii) Energy Eficiency (EE), Fig. 9b: EE is calculated in bits per joule by dividing the goodput with power consump tion in watts (Table 1). Since FDMA interfaces just a single antenna, it has the simplest hardware and the least power consumption, and thus forms an oracle for EE metric. FDMA consumes 354 mW (3v VCC, 118mA current) from operation of MAX2829 RF transceiver used in WARP to amplify, fil ter and downconvert[62]. ADC power varies linearly with the sampling frequency [16, 46], which is also true for the AD9963 ADC used for WARP, as evident from the datasheet [63], and it consumes 100 mW per 10 MHz sampled bandwidth. Hence to obtain the 24<sup>,</sup> 36<sup>,</sup> 48 Mbps goodput by enabling 2<sup>,</sup> 3<sup>,</sup> 4 streams with 20<sup>,</sup> 30<sup>,</sup> 40 MHz bandwidth, FDMA spends just 354 + 200<sup>,</sup> 354 + 300<sup>,</sup> 354 + 400 mW power (Table 1). GreenMO also uses same single RF chain hardware like FDMA, but with addition of the switched antenna array. Hence, GreenMO consumes 562<sup>,</sup> 662<sup>,</sup> 762 mW respectively for 2<sup>,</sup> 3<sup>,</sup> 4 streams, with extra 8mW power requirements in the antenna array (AA, Table 1). The 8 RF-switches in the antenna array consume ∼ 1 mW active power per-switch when operated with 40 MHz, 25% duty cycled clock. 

For the DBF/HBF baselines, we need to configure the MAX2829 RFIC into synchronized MIMO modes, which for 4 RFIC’s, require 1632 mW (4×408 mW). This gets added with 4 ∗ 100 mW power for sampling 10 MHz across the 4 AD9963 ADCs, and hence total power for 4 antenna DBF is $1 6 3 2 + 4 0 0 = 2 0 3 2 \mathrm { \ m W }$ . We assume 2032 ∗ 2 = 4064 mW power for the trace driven study of 8 antenna DBF. PC/FC HBFs would need 2<sup>,</sup> 3<sup>,</sup> 4 MAX2829 RFIC’s to enable the 2<sup>,</sup> 3<sup>,</sup> 4 streams, and hence the power consumption scales proportionately (Table 1). However, in addition, HBF approaches require phase shifters in the antenna array, with PC HBF needing 8 phase shifters (one per antenna) and FC HBF needing 8 ∗ 4 = 32 phase shifters (one per antenna per RF chain). When implemented via popular active phase shifter approach which create phase shifts with minimal quantization errors and insertion losses, consume around 10mW each[16], and hence 80mW power consumption in the PC HBF antenna array, and a maximum of 320mW in FC HBF depending on number of streams. Alternately, high-bit passive phase shifters would not consume power by itself, but would have insertion losses which would require gain compensation from LNA, hence consuming similar net power [46]. 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/13e94f2e8c815ddb4668a5bd093f03d591902db7930d5c26f840e395cec93231.jpg)



(a) GreenMO attains capacity


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/231f8d47404ce0a1dec27ad312eec11326cf88ea93071614ced5d4d994a76108.jpg)



(b) 4 Ant. GreenMO enables 3 streams



Figure 11: (a) As num. antennas are increased from 4 → 8 GreenMO meets FDMA capacity (b) Power-adaptive multi-stream results with 4 ant. GreenMO


As compared to HBF/DBF baselines, GreenMO achieves roughly 3x the energy eficiency while serving 4 streams (Fig. 9b). Further, we see that GreenMO is able to meet similar EE as compared to FDMA, since the power consumption mimics that of FDMA with only slight extra power required in the switched antenna array (AA). Since we do not have an ASIC implementation of any baselines, the power measurements are quoted from the datasheets of the necessary IC blocks part of each baseline. 

(c) GreenMO can increase number of antennas to meet capacity: The key reason GreenMO achieves both SE and EE is that it allows antennas to be added without requiring complicated analog networks and at minimal extra antenna array power overhead. Hence, GreenMO can leverage more antennas to arbitrarily attain a given target throughput/SIN-R/capacity requirements, while not exacerbating the energy consumption. To show how using multiple antennas leads to these impressive results, we vary the number of antennas by electronically turning of antennas in GreenMO PCB to show how varying 4 → 6 → 8 antenna configurations in GreenMO leads us closer to the target SINR of 15dB for 4 spatial streams (Fig. 10a). This also allows GreenMO to attain the target 48 Mbps goodput, reaching 47 Mbps as antennas increase to 8, Fig. 10b. Overall, 8 antenna GreenMO’s average capacity while communicating 4, 10 MHz streams, evaluated as 4 ∗ 10 MHz ∗ log (SINR), is very close to the FDMA levels 40 MHz ∗ log (SISO SNR), Fig. 11a. The errorbars in Fig. 11a indicate that at certain radio configurations, using 8 antennas we get beamforming gain atop spatial multiplexing, pushing the SINR <sup>></sup> 15 dB SISO level. However, at other configs, mainly when the radios are closer to each other, the 8 antenna spatial beams are not narrow enough to bring interference down to noise level, and hence SINR is <sup><</sup> 15 dB. 

(d) Using GreenMO for Wi-Fi MIMO: GreenMO shows that MIMO is possible with single RF chain, and hence aside from Massive MIMO for base stations, it can also enable power savings in small-scale MIMO implemented in Wi-Fo with lesser number of antennas in phones/APs. To test this, we limit ourselves to 4 antennas version of GreenMO (Note that 4 antenna phones, or Wi-Fi APs are not uncommon), placed <sup>??</sup>/2 apart. We plot the goodput CDFs in Fig. 11b, and as we can see 4 ant GreenMO is able to get up to 3 independent streams very robustly, whereas 4 streams transmission is not robust as is expected from a 4 antenna GreenMO. With GreenMO, smartphones can configure higher number of streams to be communicated in a battery adaptive manner, if there is more battery it can sample higher bandwidth in the single RF chain, and communicate more streams, while still using similar spectrum resources. 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/9b560269ce77cf668742f6dd3ccd19e2cba766ad98e28f120b9647f61b06a9af.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/6ba5747b8c6ae38bfb8851ba8cac51718dac1f23d57e36dab507ff65dfdb84c0.jpg)



(a) Test setup, Physical vs Virtual RFCs (b) SINR CDFs, Physical vs Virtual RFCs (c) Choice of Switching matrix S


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/f892736ea178448be721701e03158d4bc2cc47e7e35467c7c710d24e83a7b109.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/5d4c8615c173c7d91d22baad0ebb86ea04157ada0c92f2ad43678988d570e857.jpg)



(d) Synch. vs Unsynch. Tx-Rx Radios



Figure 12: Ablation results: Physical vs Virtual RF chains setup (a) and SINR CDF (b) when same antennas used per virtual/physical RF chain, (c) SINR performance improvement due to BABF, and (d) shows that GreenMO’s technique is oblivious to TX-RX radios being synchronized or not


(e) Ablation studies, (e.i) Physical vs Virtual RF chains: To compare the physical and virtual RF chains in a fair manner, we use 4 external RF switches to toggle 4 anten nas between (1) 4 physical RF chains of WARP, or (2) the 4 virtual RF chains of GreenMO (Fig. 12a). This setup ensures that the same antennas are interfaced to each physical/vir tual chain and hence the same wireless channels are captured for each of them, which enables a fair comparison. From this setup, we collect the 2<sup>,</sup> 3<sup>,</sup> 4 streams’ traces and evaluate the SINR metric to compare if virtual RF chains have similar performance to the physical counterparts. We see that the SINR remain similar (Fig. 12b) which validates GreenMO’s virtual RF chains perform on par with physical chains. 

(e.ii) Why BABF?: Using BABF approach, GreenMO can group co-phased antennas to beamform towards one stream per virtual RF chain, and this enables a well-conditioned equivalent channel matrix HS. Hence, as a consequence, the 4 × 4 MIMO channel inversion of HS results in negligible interference with high SINR performance. These results are quantified as shown in Fig. 12c for a particular 4 stream configuration, where we evaluate the final SINRs by choosing S randomly, and via BABF, and we repeat this 100 times to plot the CDF. BABF always works better than any random choice of S, and on an average (median line) it works 10 dB better. This justifies the BABF approach of computing S. 

(e.iii) Synchronized vs Unsynchronized Radios: GreenMO performs a spatial interference suppression operation, hence it is oblivious to TX-RX Radio synchronization. We conduct experiments where we synchronize the 4 radios generating the 4 streams to share the same clock, and repeat it without synchronization. The SINR metrics in both the cases remain very similar, shown in Fig. 12d. However, 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/6e37f7a1736b8e8eae5efb6d4fbf3fab0a2f32fd1209edb2e859bd641804f241.jpg)



Figure 13: (a) 8 streams simulations SINR CDFs of various architectures (b) Possible GreenMO uplink+downlink TDD TX/RX architecture


GreenMO needs at least loosely synchronized radios such that their preambles do not collide to enable channel estimation, which is guaranteed by modern cellular protocols. 

## 6 Discussion and Limitations

GreenMO hardware experiments are limited to 4 streams with 8 antennas in uplink setting. In this section, we show a generalization of GreenMO to create a NR compliant TDD uplink/downlink architecture. We also show a brief case study on how GreenMO can be ∼ 2× more energy eficient than existing 5G NR radios while creating the required 8 spatial streams. We conclude with how GreenMO can scale to wider bandwidths, mitigate against channel estimation latency and hybrid multi-RF chain GreenMO architecture. 

(a) Time-divisioned (TDD) Uplink+Downlink GreenMO: We show a possible NR compliant TDD GreenMO uplink+downlink architecture in Fig. 13 (b). TDD operation is enabled by switching back and forth between the single Tx/Rx physical chain akin to a standard single antenna TDD chain. The downlink equivalency is motivated by the frequency domain picture of switching, since the DC harmonic would preserve the phases set by base band precoder and allow for downlink beamforming. However, we need a filter right next to switch so that we do not transmit the other harmonic signals. In downlink, we get additional power requirements for power amplifier (PA), and the PA energy consumption remains same for almost all possible architectures, like FDMA, mMIMO, or even GreenMO. This is because PA power is EIRP driven, and FDMA would need one stronger PA whereas mMIMO uses smaller PAs per antenna (but multiple of them) since it also gets antenna beamforming gain. Infact, GreenMO can flexibly do both, either smaller PAs per antenna after the splitter, or a single powerful PA before splitter (usually better to have a single PA). A detailed study on which 

(c) 

![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/9b3d3cfae01e97efee69d5681c221ad010fc5c24be3e3310935b20238ebbf469.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/6abcc19648b531b4398e6a6fa50e5bd875abc9e9b0edc0ba6da55a03b82fc37b.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/08defc74f18fb963efb280a68547329659aecf8b4a13182dbc8c5d6dafa03adb.jpg)


![image](https://cdn-mineru.openxlab.org.cn/result/2026-06-25/c41cd905-13cc-420d-a244-9b52304c1502/8f37c1faf0dc7bcc5bf08aff02b73c3c23d4a1a852cec71b6f86ffada8a0a5f7.jpg)



Figure 14: (a) GreenMO achieves same Spectral Eficiency (SE) as 64 Ant. DBF by using 256 antennas and 8 VRFs (b) Energy Eficiency (EE) increases for GreenMO as antennas increase whereas DBF shows a dip around 64 antenna mark (c) Plots EE vs SE and for DBF increasing SE comes with a reduced EE, whereas GreenMO breaks the SE-EE tradeof and ofers a linearly increasing way of achieving both higher EE and SE (d) Shows power consumption breakouts of DBF based Massive MIMO and GreenMO AAU, evaluated for 64 and 256 antennas to serve 8 concurrent spatial streams


PA integration approach is better, alongwith associated eficiencies is out of scope for this paper. 

(b) 8 streams, 64 antenna simulations: We place 8 radios in simulated environments similar to our evaluation setting, and model the multipath wireless channel via ray tracing. The simulations use identical OFDM waveforms to our experiments. Hence, this simulation framework gives results consistent with the experimental trends. Noise is added artificially to maintain 15 dB SISO SNR, similar to experiments. The wireless channel is applied by calculating distances from the simulation multipath reflectors, which provide the time delays/two-way path loss, incorporated in the time-delays/attenuation of the OFDM waveforms. 

Fig. 13a shows the 64 antenna simulations to serve 8 spatial streams. This is considered a standard baseline with multi user dense deployments [16]. GreenMO uses 64 antennas and creates 8 virtual RF chains to obtain >15dB SINR at 90% percentile. Our simulations assume perfect phase quanti zation in HBF approaches, and still GreenMO outperforms partially connected HBF. The reason is that unlike partially connected beamformers GreenMO can use all the 64 antennas per virtual RF chain because of the many-to-many mapping (Section 3.3). GreenMO’s performance comes about 5<sup>????</sup> close at median level to the 64 Antenna DBF and FC HBF, even though using only a single physical RF chain. 

(c) How much power can GreenMO save in a 5G NR base station while meeting the existing SE levels? To meet the SE of existing radios, GreenMO can increase the number of antennas (Fig. 14a). For example, we see that GreenMO meets SE level of 50 bits per Hz in today’s 64 Tx/Rx MIMO base stations at 256 Antennas and 8 virtual RF chains. Unlike DBF, GreenMO can interface 256 Antennas without showing a degradation in EE (Fig. 14b), since be yond 64 antennas DBF architecture has diminishing gains in capacity while serving 8 streams, but with a proportionate increase in energy. Hence, DBF’s EE vs number of antennas starts showing a dip post 64 antennas (Fig. 14b), which might also indicate why so many major base-station vendors today ofer a 64 Tx/Rx DBF mMIMO radio [13, 14, 33]. When EE and SE are plotted against each other, we see that the EE achieved by 256 antenna GreenMO is roughly twice (1.8x) that of 64 Tx/Rx DBF approach (Fig. 14c). The Power calculations supporting the EE computations are detailed in Fig. 14d, with the power composition metrics (45% PA, 30% Baseband, 20% RFE and 5% misc. cooling costs) taken from [33]. Basically, RFE+Baseband power grows linearly with number of RF chains[40, 64]. Hence, in a typical <sup>?? ></sup> 8 DBF radio, RFE+Baseband power grows <sup>??</sup> × with <sup>??</sup> antennas. Beyond <sup>??</sup> <sup>></sup> 64 antennas, the RFE+Baseband power starts dominating the net power calculations (exceeds that of PA+cooling power), and leads to EE degradation in existing mMIMO radios. Instead in GreenMO, the RFE+Baseband power remains at a constant 8× level since GreenMO just creates 8 virtual RF chains from the single physical chain laid to all the <sup>??</sup> antennas. As explained earlier in Section 6a, PA power is EIRP driven and remain similar for all architectures, but GreenMO optimizes the other power components and brings them down drastically, to save about 50% power in existing 5G mMIMO base station. 

(d) Scaling to wider bandwidths: GreenMO architecture can scale to wider-bandwidths with faster switches and higher sampling bandwidth ADCs. Photonic RF switches offer pico-second rise time[65–67] which are 1000x faster than COTS solid state switches used in GreenMO. Also, there are some expensive commercially available RF switches ofering sub-ns, to low <10ns rise times[68, 69], to enable bandwidths 100 MHz - 1 GHz. GreenMO’s architecture can create a new application scenario for faster switches as traditionally RF switches have been optimized only for improved isolation, or wideband operation, not for speed. 

On the other hand, ADCs capable of ∼1 GHz sampling bandwidth [70, 71] are commonplace now. These 1 GHz sampling ADCs were thought to be useful only for mmWave frequencies where such wide over-the-air spectrum is available. Hence, GreenMO can enable these 1GHz ADCs to be useful even in sub-6 networks and unify the hardware needs of both sub-6 and mmWave bands. However, in order for GreenMO to keep being energy-eficient while scaling to wider bandwidths, it needs to carefully characterize the high sampling bandwidth ADC, where for example, the otherwise linear power scaling with sampling frequency may become super-linear, as well as other practical efects like cooling of a single high bandwidth may be more dificult than a distributed set of smaller bandwidth ADCs. In addition to handling a wider bandwidth ADC, GreenMO would also demand wide bandwidth support hardware, like LNAs/filters, which may have issues like dynamic range, and/otherwise may be costlier than simpler low bandwidth hardware. 

(e) Handling neighbour band jammer and improved analog control over antennas: Further, to improve GreenMO uplink architecture, we need narrowband filters [72, 73] which would guard GreenMO against a neighbour band jammer. Also, instead of using a simple {0<sup>,</sup> 1} binary switch per antenna, using better hardware would enable more granular control over the per-antenna degrees of freedom. For example, a simple change could be to implement {1<sup>,</sup> −1} control by <sup>??</sup> shifting one antenna path compared to another and toggling between these with RF switch. This would rotate the out of phase antennas towards the in-phase BABF cluster, instead of simply turning them of. 

(f) Addressing channel estimation latency: While interfacing 4 streams with 8 antennas, the channel estimation was straightforward. However, to enable higher number of antennas (eg. 256 antennas as suggested in Section 6c), estimating per-antenna channels would be costly. But, the BABF approach can also work with simpler joint communicationsensing based channel estimation, and can figure out the antenna configuration by just knowing the direction of users to beamform in that direction. Leveraging existing infrastructure (radars[74], mmWave radios [75], RIS[76]) for direction estimation has been a popular line of work which make large antenna GreenMO robust to channel estimation latencies. 

(g) Multi RF chain GreenMO: In this paper, we have tested GreenMO architecture with just a single physical RF chain. However, if we have multiple RF chains, all capable of clocking at higher sampling rates, GreenMO can create a multiple set of virtual RF chains from each of these physical RF chains. Thus, GreenMO’s time combining can be viewed as an alternate to traditional space combining method. By utilizing space-time combining we can increase the number of spatial streams by providing multiplicative gain to number of total RF chains (physical×virtual). This approach could possibly push the limits of available spatial multiplexing gains imaginable, as we can find a sweet spot where multiple physical RF chains operate at a high enough bandwidth to generate new virtual RF chains, enabling multiplicity in the total RF chains created. 

(h) Other applications for GreenMO: GreenMO can also bring the benefits of Massive MIMO to previously unthought-of energy constraint applications, like small cells [77], and drone based MIMO APs[78]. This can enable higher levels of cellular densification [79] and increase the drone air-time by reducing wireless power consumption [80]. 

## 7 Related Works

GreenMO presents for the first time, a system implementation of MIMO architecture with a single RF chain. In this section, we will compare to other upcoming architectures and theoretical approaches proposing single RF chain MIMO. 

Some recent papers have also proposed using a higher analog circuit intermediate frequency (IF) bandwidth to enable single RF chain MIMO [81–83], however they typically just multiplex outputs from analog beamforming blocks instead of implementing spatial multiplexing. Put more simply, these works either use IF bandwidth code domain [81, 82] or diferent freq. bands in the higher IF bandwidth [83] to multiplex the outputs from a prior analog beamforming front-end. The challenge with these works is that they need to perform beam-nulling in analog domain, which is not robust to wideband operation and phase shifter inaccuracies [84]. 

Also, a parallel set of works explore parasitic antenna arrays to create artificial temporal wireless channel alterations [85–92], and Time Modulated Antenna Arrays (TMAA) [93– 104], which create opportunities for diversity gains/spatial multiplexing with a single RF chain, similar to GreenMO switching. The parasitic arrays have shown dificulties in scaling with number of antennas [91], and further, require precision control over antenna impedance to generate the orthogonal beams [90]. The most notable of the TMAA apprpaches utilize a 4 antenna array and a 50 MHz switching speed to allow for increased diversity gains while decoding simple modulations like QPSK [94–96, 98, 104]. However, these demonstrations are again limited to diversity gains from single RF chains, unlike GreenMO which enables multistream spatial multiplexing, with higher order constellations like QAM-16 and wideband OFDM transmissions. 

RF-switches have also been used in antenna arrays to attain diversity gains by introducing hopping efects [105], improve spatial localization accuracy by stitching across antenna arrays and increasing aperture [106, 107], and to perform strategic antenna selection to create beam nulling for <sup>??</sup> user interference channels [108–110]. However, GreenMO switches are actively switching at baseband frequencies and the efect created by this fast switching is very diferent from the static on-of modelling in these papers. There are other papers which target the uplink MIMO problem as well, with some of them requiring coordination from the users to do interference alignment [111, 112], set random delays in transmissions to break channel correlations [113], or utilize distributed APs to serve multiple users [114]. 

## 8 Acknowledgements

We are grateful to the anonymous reviewers and shepherd for their insightful feedback. We also thank members of WCSNG, UCSD for their feedback throughout the process, in particular, Roshan Ayyalasomayajula, for his comments on simplifying the figures and paper disposition. 

## References



[1] The wireless communications industry and its carbon footprint. https: //www.azocleantech.com/article.aspx?ArticleID=1131. 





[2] How to estimate carbon emissions in mobile networks: a stream lined approach. https://www.ericsson.com/en/blog/2021/5/how-toestimate-carbon-emissions-from-mobile-networks. 





[3] The case for committing to greener telecom networks (mckinsey report). https://www.mckinsey.com/industries/technology-mediaand-telecommunications/our-insights/the-case-for-committing-togreener-telecom-networks. 





[4] Putting sustainability at the top of the telco agenda (bcg report). https://www.bcg.com/publications/2021/building-sustainabletelecommunications-companies. 





[5] Search for sustainable goods grows by 71% as ‘eco-wakening’ grips the globe. https://www.worldwildlife.org/press-releases/search-for sustainable-goods-grows-by-71-as-eco-wakening-grips-the-globe. 





[6] Adidas ceo: 70% of consumers prefer to buy sustainable prod ucts. https://www.environmentalleader.com/2021/06/adidas-ceo-70-of-consumers-prefer-to-buy-sustainable-products/. 





[7] Recent study reveals more than a third of global consumers are willing to pay more for sustainability as demand grows for environmentally-friendly alternatives. https://www.businesswire.com/news/home/20211014005090/en/Recent Study-Reveals-More-Than-a-Third-of-Global-Consumers-Are-Willing-to-Pay-More-for-Sustainability-as-Demand-Grows-for-Environmentally-Friendly-Alternatives. 





[8] Shuangfeng Han, Sen Bian, et al. Energy-eficient 5g for a greener future. Nature Electronics, 3(4):182–184, 2020. 





[9] Thomas L Marzetta. Massive mimo: an introduction. Bell Labs Technical Journal, 20:11–22, 2015. 





[10] Erik G Larsson, Ove Edfors, Fredrik Tufvesson, and Thomas L Marzetta. Massive mimo for next generation wireless systems. IEEE communications magazine, 52(2):186–195, 2014. 





[11] Emil Björnson, Erik G Larsson, and Thomas L Marzetta. Massive mimo: Ten myths and one critical question. IEEE Communications Magazine, 54(2):114–123, 2016. 





[12] Emil Björnson, Jakob Hoydis, Luca Sanguinetti, et al. Massive mimo networks: Spectral, energy, and hardware eficiency. Foundations and Trends® in Signal Processing, 11(3-4):154–655, 2017. 





[13] Ericsson 5g massive mimo handbook. https://www.ericsson.com/en/ ran/massive-mimo. 





[14] Huwaei 5g power whitepaper. https://carrier.huawei.com/~/media/ CNBG/Downloads/Spotlight/5g/5G-Power-White-Paper-en.pdf. 





[15] Jian Ding, Rahman Doost-Mohammady, Anuj Kalia, and Lin Zhong. Agora: Real-time massive mimo baseband processing in software. In Proceedings of the 16th International Conference on emerging Networking EXperiments and Technologies, pages 232–244, 2020. 





[16] Han Yan, Sridhar Ramesh, Timothy Gallagher, Curtis Ling, and Danijela Cabric. Performance, power, and area design trade-ofs in millimeter-wave transmitter beamforming architectures. IEEE Circuits and Systems Magazine, 19(2):33–58, 2019. 





[17] Daniel C Araújo, Taras Maksymyuk, André LF de Almeida, Tarcisio Maciel, João CM Mota, and Minho Jo. Massive mimo: survey and future research topics. Iet Communications, 10(15):1938–1946, 2016. 





[18] Jakob Hoydis, Stephan Ten Brink, and Mérouane Debbah. Massive mimo in the ul/dl of cellular networks: How many antennas do we need? IEEE Journal on selected Areas in Communications, 31(2):160– 171, 2013. 





[19] Lingjia Liu, Runhua Chen, Stefan Geirhofer, Krishna Sayana, Zhihua Shi, and Yongxing Zhou. Downlink mimo in lte-advanced: Su-mimo vs. mu-mimo. IEEE Communications Magazine, 50(2):140–147, 2012. 





[20] Eduardo Castaneda, Adao Silva, Atilio Gameiro, and Marios Kountouris. An overview on resource allocation techniques for multi-user mimo systems. IEEE Communications Surveys & Tutorials, 19(1):239– 284, 2016. 





[21] Hong-Teuk Kim, Byoung-Sun Park, Seong-Sik Song, Tak-Su Moon, So-Hyeong Kim, Jong-Moon Kim, Ji-Young Chang, and Yo-Chul Ho. A 28-GHz cmos direct conversion transceiver with packaged 2*4 antenna array for 5G cellular system. IEEE Journal of Solid-State Circuits, 53(5):1245–1259, 2018. 





[22] Thomas Kühne, Piotr Gawłowicz, Anatolij Zubow, Falko Dressler, and Giuseppe Caire. Bringing hybrid analog-digital beamforming to commercial MU-MIMO wifi networks. In Proceedings of the 26th Annual International Conference on Mobile Computing and Networking, pages 1–3, 2020. 





[23] Yasaman Ghasempour, Muhammad K Haider, Carlos Cordeiro, Dimitrios Koutsonikolas, and Edward Knightly. Multi-stream beamtraining for mmWave MIMO networks. In Proceedings of the 24th Annual International Conference on Mobile Computing and Networking, pages 225–239, 2018. 





[24] Xiufeng Xie, Eugene Chai, Xinyu Zhang, Karthikeyan Sundaresan, Amir Khojastepour, and Sampath Rangarajan. Hekaton: Eficient and practical large-scale MIMO. In Proceedings of the 21st Annual International Conference on Mobile Computing and Networking, pages 304–316, 2015. 





[25] Yongce Chen, Yan Huang, Chengzhang Li, Y Thomas Hou, and Wenjing Lou. Turbo-HB: A novel design and implementation to achieve ultra-fast hybrid beamforming. In IEEE INFOCOM 2020-IEEE Conference on Computer Communications, pages 1489–1498. IEEE, 2020. 





[26] Didi Zhang, Yafeng Wang, Xuehua Li, and Wei Xiang. Hybridly connected structure for hybrid beamforming in mmWave massive MIMO systems. IEEE Transactions on Communications, 66(2):662–674, 2017. 





[27] Xianghao Yu, Juei-Chin Shen, Jun Zhang, and Khaled B Letaief. Alternating minimization algorithms for hybrid precoding in millimeter wave MIMO systems. IEEE Journal of Selected Topics in Signal Processing, 10(3):485–500, 2016. 





[28] Susnata Mondal, Rahul Singh, and Jeyanandh Paramesh. 21.3 a reconfigurable bidirectional 28/37/39GHz front-end supporting MIMO-TDD, carrier aggregation TDD and FDD/Full-duplex with selfinterference cancellation in digital and fully connected hybrid beamformers. In 2019 IEEE International Solid-State Circuits Conference-(ISSCC), pages 348–350. IEEE, 2019. 





[29] Susnata Mondal, Rahul Singh, Ahmed I Hussein, and Jeyanandh Paramesh. A 25–30 GHz fully-connected hybrid beamforming re ceiver for MIMO communication. IEEE Journal of Solid-State Circuits, 53(5):1275–1287, 2018. 





[30] Susnata Mondal, Rahul Singh, Ahmed I Hussein, and Jeyanandh Paramesh. A 25-30 GHz 8-antenna 2-stream hybrid beamforming receiver for MIMO communication. In 2017 IEEE Radio Frequency Integrated Circuits Symposium (RFIC), pages 112–115. IEEE, 2017. 





[31] Tatsunori Obara, Tatsuki Okuyama, Yuuichi Aoki, Satoshi Suyama, Jaekon Lee, and Yukihiko Okumura. Indoor and outdoor experimental trials in 28-GHz band for 5G wireless communication systems. In 2015 IEEE 26th Annual International Symposium on Personal, Indoor, and Mobile Radio Communications (PIMRC), pages 846–850. IEEE, 2015. 





[32] Zhe Chen, Xu Zhang, Sulei Wang, Yuedong Xu, Jie Xiong, and Xin Wang. BUSH: empowering large-scale MU-MIMO in WLANs with hybrid beamforming. In IEEE INFOCOM 2017-IEEE Conference on Computer Communications, pages 1–9. IEEE, 2017. 





[33] Application of ai technology in 5g base station to improve energy eficiency——practices of china telecom. https://www.itu.int/en/ITU-





T/climatechange/Documents/AI%20and%20environmental% 20efficiency_9%20December/Ying%20Shi.pdf, author=Shi, Ying, organization=China Telecom. 





[34] Cradle to the grave: Sustainability and the life of a base station. https: //www.azocleantech.com/article.aspx?ArticleID=1108. 





[35] Nicole Robertson. How to cut carbon emissions in telecoms networks. https://www.rcrwireless.com/20220404/opinion/readerforum/howto-cut-carbon-emissions-in-telecoms-networks-reader-forum. 





[36] Pål Frenger and Richard Tano. A technical look at 5g energy con sumption and performance. https://www.ericsson.com/en/blog/2019/ 9/energy-consumption-5g-nr. 





[37] Hannaneh Barahouei Pasandi and Tamer Nadeem. Latte: online mu-mimo grouping for video streaming over commodity wifi. In Proceedings of the 19th Annual International Conference on Mobile Systems, Applications, and Services, pages 491–492, 2021. 





[38] Hong Yang and Thomas L Marzetta. Total energy eficiency of cellular large scale antenna system multiple access mobile networks. In 2013 IEEE online conference on green communications (OnlineGreenComm), pages 27–32. IEEE, 2013. 





[39] Emil Björnson, Luca Sanguinetti, Jakob Hoydis, and Mérouane Deb bah. Optimal design of energy-eficient multi-user mimo systems: Is massive mimo the answer? IEEE Transactions on wireless communications, 14(6):3059–3075, 2015. 





[40] Daehan Ha, Keonkook Lee, and Joonhyuk Kang. Energy eficiency analysis with circuit power consumption in massive mimo systems. In 2013 IEEE 24th Annual International Symposium on Personal, Indoor, and Mobile Radio Communications (PIMRC), pages 938–942. IEEE, 2013. 





[41] KNR Surya Vara Prasad, Ekram Hossain, and Vijay K Bhargava. En ergy eficiency in massive mimo-based 5g networks: Opportunities and challenges. IEEE Wireless Communications, 24(3):86–94, 2017. 





[42] Ranjini Guruprasad, Kyuho Son, and Sujit Dey. Power-eficient base station operation through user qos-aware adaptive rf chain switching technique. In 2015 IEEE International Conference on Communications (ICC), pages 244–250. IEEE, 2015. 





[43] Ahmed Alkhateeb, Young-Han Nam, Jianzhong Zhang, and Robert W Heath. Massive mimo combining with switches. IEEE Wireless Communications Letters, 5(3):232–235, 2016. 





[44] Ranjini Guruprasad and Sujit Dey. User qos-aware adaptive rf chain switching for power eficient cooperative base stations. IEEE Transactions on Green Communications and Networking, 1(4):409–422, 2017. 





[45] Javed Akhtar, Ketan Rajawat, Vipul Gupta, and Ajit K Chaturvedi. Joint user and antenna selection in massive-mimo systems with qos constraints. IEEE Systems Journal, 15(1):497–508, 2020. 





[46] C Nicolas Barati, Sourjya Dutta, Sundeep Rangan, and Ashutosh Sabharwal. Energy and latency of beamforming architectures for initial access in mmwave wireless networks. Journal of the Indian Institute of Science, 100(2):281–302, 2020. 





[47] Muris Sarajlić, Liang Liu, and Ove Edfors. When are low resolution adcs energy eficient in massive mimo? IEEE access, 5:14837–14853, 2017. 





[48] Jiayi Zhang, Linglong Dai, Shengyang Sun, and Zhaocheng Wang. On the spectral eficiency of massive mimo systems with low-resolution adcs. IEEE Communications Letters, 20(5):842–845, 2016. 





[49] Christopher Mollen, Junil Choi, Erik G Larsson, and Robert W Heath. Uplink performance of wideband massive mimo with one-bit adcs. IEEE Transactions on Wireless Communications, 16(1):87–100, 2016. 





[50] Energy eficiency in next-generation mobile networks. https:// onestore.nokia.com/asset/212810. 





[51] Rf mixers, ali niknejad. http://rfic.eecs.berkeley.edu/~niknejad/ ee242/pdf/ee242_mixer_fund.pdf. 





[52] Understanding mixers and their parameters. https://www.mwrf. com/technologies/components/article/21846332/microwaves-rfunderstanding-mixers-and-their-parameters. 





[53] Pengyu Zhang, Dinesh Bharadia, Kiran Joshi, and Sachin Katti. Hitchhike: Practical backscatter using commodity wifi. In Proceedings of the 14th ACM Conference on Embedded Network Sensor Systems CD-ROM, pages 259–271, 2016. 





[54] Pengyu Zhang, Colleen Josephson, Dinesh Bharadia, and Sachin Katti. Freerider: Backscatter communication using commodity radios. In Proceedings of the 13th International Conference on emerging Networking EXperiments and Technologies, pages 389–401, 2017. 





[55] Manideep Dunna, Miao Meng, Po-Han Wang, Chi Zhang, Patrick P Mercier, and Dinesh Bharadia. Syncscatter: Enabling wifi like synchronization and range for wifi backscatter communication. In NSDI, pages 923–937, 2021. 





[56] Xin Liu, Zicheng Chi, Wei Wang, Yao Yao, and Ting Zhu. Vmscatter: A versatile {MIMO} backscatter. In 17th {USENIX} Symposium on Networked Systems Design and Implementation ({NSDI} 20), pages 895–909, 2020. 





[57] Bryce Kellogg, Aaron Parks, Shyamnath Gollakota, Joshua R Smith, and David Wetherall. Wi-fi backscatter: Internet connectivity for rf-powered devices. In Proceedings of the 2014 ACM Conference on SIGCOMM, pages 607–618, 2014. 





[58] Greenmo proofs. https://bit.ly/3Ad8pqW. 





[59] HMC197BE. https://www.analog.com/media/en/technicaldocumentation/data-sheets/hmc197b.pdf. 





[60] Cmod a7 15t. https://digilent.com/reference/programmable-logic/ cmod-a7/start. 





[61] Snr and mcs choice. https://www.gnswireless.com/info/signal-tonoise-ratio-snr. 





[62] MAX2829. https://datasheets.maximintegrated.com/en/ds/ MAX2828-MAX2829.pdf. 





[63] AD9963. https://www.analog.com/en/products/ad9963.html. 





[64] Gunther Auer, Vito Giannini, Claude Desset, Istvan Godor, Per Skillermark, Magnus Olsson, Muhammad Ali Imran, Dario Sabella, Manuel J Gonzalez, Oliver Blume, et al. How much energy is needed to run a wireless network? IEEE wireless communications, 18(5):40–49, 2011. 





[65] Jia Ge and Mable P Fok. Ultra high-speed radio frequency switch based on photonics. Scientific reports, 5(1):1–7, 2015. 





[66] Yiwei Xie, Leimeng Zhuang, Pengcheng Jiao, and Daoxin Dai. Sub-nanosecond-speed frequency-reconfigurable photonic radio frequency switch using a silicon modulator. Photonics Research, 8(6):852– 857, 2020. 





[67] Hengyun Jiang, Lianshan Yan, Wei Pan, Bing Luo, and Xihua Zou. Ultra-high speed RF filtering switch based on stimulated brillouin scattering. Optics letters, 43(2):279–282, 2018. 





[68] Hmmc2027 gaas rf switch. https://www.acalbfi.com/be/RFcomponents/Switches/p/DC---26-5-{GHz}-SPDT-Absorptive-GaAs-Switch-IC/0000000JUM. 





[69] Mswa2-50+ rf switch. https://www.minicircuits.com/pdfs/MSWA2- 50+.pdf. 





[70] ADC captures 1Gsps. https://www.maximintegrated.com/en/design/ technical-documents/app-notes/6/642.html. 





[71] 1 GHz ADC from TI. https://www.ti.com/lit/ug/tidubq0/tidubq0.pdf. 





[72] Saw filter qpq1906. https://www.crystek.com/microwave/specsheets/filter/CBPFS-2441.pdf. 





[73] Qorvo qpq1906. https://www.mouser.com/datasheet/2/412/ QPQ1906_Data_Sheet-1795086.pdf. 





[74] Umut Demirhan and Ahmed Alkhateeb. Radar aided 6g beam predic tion: Deep learning algorithms and real-world demonstration. In 2022 IEEE Wireless Communications and Networking Conference (WCNC), pages 2655–2660. IEEE, 2022. 





[75] Teng Wei, Anfu Zhou, and Xinyu Zhang. Facilitating robust 60 ghz network deployment by sensing ambient reflectors. In NSDI, pages 213–226, 2017. 





[76] Lu Wang, Luis F Abanto-Leon, and Arash Asadi. Joint communica tion and sensing in ris-enabled mmwave networks. arXiv preprint arXiv:2210.03685, 2022. 





[77] Wenjia Liu, Shengqian Han, Chenyang Yang, and Chengjun Sun. Massive mimo or small cell network: Who is more energy eficient? In 2013 IEEE Wireless Communications and Networking Conference Workshops (WCNCW), pages 24–29. IEEE, 2013. 





[78] Carmen D’Andrea, Adrian Garcia-Rodriguez, Giovanni Geraci, Lorenzo Galati Giordano, and Stefano Buzzi. Analysis of uav com munications in cell-free massive mimo systems. IEEE Open Journal of the Communications Society, 1:133–147, 2020. 





[79] Agrim Gupta, Ish Jain, and Dinesh Bharadia. Multiple smaller base stations are greener than a single powerful one: Densification of wireless cellular networks. 





[80] John Buczek, Lorenzo Bertizzolo, Stefano Basagni, and Tommaso Melodia. What is a wireless uav? a design blueprint for 6g flying wireless nodes. In Proceedings of the 15th ACM Workshop on Wireless Network Testbeds, Experimental evaluation & CHaracterization, pages 24–30, 2022. 





[81] Fred Tzeng, Amin Jahanian, Deyi Pi, and Payam Heydari. A cmos code-modulated path-sharing multi-antenna receiver front-end. IEEE journal of solid-state circuits, 44(5):1321–1335, 2009. 





[82] Manoj Johnson, Armagan Dascurcu, Kai Zhan, Arman Galioglu, Naresh Kumar Adepu, Sanket Jain, Harish Krishnaswamy, and Arun S Natarajan. Code-domain multiplexing for shared IF/LO interfaces in millimeter-wave MIMO arrays. IEEE Journal of Solid-State Circuits, 55(5):1270–1281, 2020. 





[83] Robin Garg, Gaurav Sharma, Ali Binaie, Sanket Jain, Sohail Ahasan, Armagan Dascurcu, Harish Krishnaswamy, and Arun S Natarajan. A 28-GHz beam-space MIMO RX with spatial filtering and frequency division multiplexing-based single-wire IF interface. IEEE Journal of Solid-State Circuits, 2020. 





[84] Sohrab Madani, Suraj Jog, Jesús Omar Lacruz, Joerg Widmer, and Haitham Hassanieh. Practical null steering in millimeter wave net works. In NSDI, pages 903–921, 2021. 





[85] Osama N Alrabadi, Chamath Divarathne, Philippos Tragas, Anto nis Kalis, Nicola Marchetti, Constantinos B Papadias, and Ramjee Prasad. Spatial multiplexing with a single radio: Proof-of-concept experiments in an indoor environment with a 2.6-GHz prototype. IEEE Communications Letters, 15(2):178–180, 2010. 





[86] Bo Han, Vlasis I Barousis, Constantinos B Papadias, Antonis Kalis, and Ramjee Prasad. MIMO over ESPAR with 16-QAM modulation. IEEE Wireless Communications Letters, 2(6):687–690, 2013. 





[87] Heung-Gyoon Ryu and Bong-Jun Kim. Beam space MIMO-OFDM system based on ESPAR antenna. In 2015 International Workshop on Antenna Technology (iWAT), pages 168–171. IEEE, 2015. 





[88] Yafei Hou, Rian Ferdian, Satoshi Denno, and Minoru Okada. Lowcomplexity implementation of channel estimation for ESPAR-OFDM receiver. IEEE Transactions on Broadcasting, 67(1):238–252, 2020. 





[89] Illsoo Sohn and Donghyuk Gwak. Single-RF MIMO-OFDM system with beam switching antenna. EURASIP Journal on Wireless Communications and Networking, 2016(1):1–14, 2016. 





[90] Junho Lee, Ju Yong Lee, and Yong H Lee. Spatial multiplexing of OFDM signals with QPSK modulation over ESPAR. IEEE Transactions on Vehicular Technology, 66(6):4914–4923, 2016. 





[91] Zixiang Han, Yujie Zhang, Shanpu Shen, Yue Li, Chi-Yuk Chiu, and Ross Murch. Characteristic mode analysis of ESPAR for single RF MIMO systems. IEEE Transactions on Wireless Communications, 20(4):2353–2367, 2020. 





[92] Jung-Nam Lee, Yong-Ho Lee, Kwang-Chun Lee, and Tae Joong Kim. <sup>??</sup>/64-spaced compact ESPAR antenna via analog RF switches for a single RF chain MIMO system. ETRI Journal, 41(4):536–548, 2019. 





[93] Gweondo Jo, Hyoung-Oh Bae, Donghyuk Gwak, and Jung-Hoon Oh. Demodulation of 4× 4 MIMO signal using single RF. In 2016 18th International Conference on Advanced Communication Technology (ICACT), pages 390–393. IEEE, 2016. 





[94] Grzegorz Bogdan, Konrad Godziszewski, and Yevhen Yashchyshyn. MIMO receiver with reduced number of RF chains based on 4D array and software defined radio. In 2019 27th European Signal Processing Conference (EUSIPCO), pages 1–5. IEEE, 2019. 





[95] Grzegorz Bogdan, Konrad Godziszewski, Yevhen Yashchyshyn, Cheol Ho Kim, and Seok-Bong Hyun. Time-modulated antenna array for real-time adaptation in wideband wireless systems–part i: Design and characterization. IEEE Transactions on Antennas and Propagation, 68(10):6964–6972, 2019. 





[96] Grzegorz Bogdan, Konrad Godziszewski, and Yevhen Yashchyshyn. Time-modulated antenna array for real-time adaptation in wideband wireless systems–part ii: Adaptation study. IEEE Transactions on Antennas and Propagation, 68(10):6973–6981, 2020. 





[97] José P González-Coma and Luis Castedo. Wideband hybrid precoding using time modulated arrays. IEEE Access, 8:144638–144653, 2020. 





[98] Grzegorz Bogdan, Konrad Godziszewski, and Yevhen Yashchyshyn. Time-modulated antenna array with beam-steering for low-power wide-area network receivers. IEEE Antennas and Wireless Propagation Letters, 19(11):1876–1880, 2020. 





[99] Wen-Qin Wang, Hing Cheung So, and Alfonso Farina. An overview on time/frequency modulated array processing. IEEE Journal of Selected Topics in Signal Processing, 11(2):228–246, 2016. 





[100] José P González-Coma, Roberto Maneiro-Catoira, and Luis Castedo. Hybrid precoding with time-modulated arrays for mmwave MIMO systems. IEEE Access, 6:59422–59437, 2018. 





[101] Avishek Chakraborty, Gopi Ram, and Durbadal Mandal. Timemodulated multibeam steered antenna array synthesis with optimally designed switching sequence. International Journal of Communication Systems, 34(9):e4828, 2021. 





[102] Chong He, Xianling Liang, Bin Zhou, Junping Geng, and Ronghong Jin. Space-division multiple access based on time-modulated array. IEEE Antennas and Wireless Propagation Letters, 14:610–613, 2014. 





[103] Roberto Maneiro-Catoira, Julio Brégains, José A García-Naya, and Luis Castedo. Time modulated arrays: From their origin to their utilization in wireless communication systems. Sensors, 17(3):590, 2017. 





[104] Grzegorz Bogdan, Miłosz Jarzynka, and Yevhen Yashchyshyn. Experimental study of signal reception by means of time-modulated antenna array. In 2016 21st International Conference on Microwave, Radar and Wireless Communications (MIKON), pages 1–4. IEEE, 2016. 





[105] Sanjib Sur, Teng Wei, and Xinyu Zhang. Bringing multi-antenna gain to energy-constrained wireless devices. In Proceedings of the 14th International Conference on Information Processing in Sensor Networks, pages 25–36, 2015. 





[106] Yaxiong Xie, Yanbo Zhang, Jansen Christian Liando, and Mo Li. Swan: Stitched wi-fi antennas. In Proceedings of the 24th Annual International Conference on Mobile Computing and Networking, pages 51–66, 2018. 





[107] Zhihao Gu, Taiwei He, Junwei Yin, Yuedong Xu, and Jun Wu. Tyrloc: a low-cost multi-technology mimo localization system with a single rf chain. In Proceedings of the 19th Annual International Conference on Mobile Systems, Applications, and Services, pages 228–240, 2021. 





[108] Milad Johnny and Alireza Vahid. Low-complexity blind interference suppression with reconfigurable antennas. IEEE Transactions on Wireless Communications, 21(4):2757–2768, 2021. 





[109] Sajjad Nassirpour, Agrim Gupta, Alireza Vahid, and Dinesh Bharadia. Power-eficient analog front-end interference suppression with binary antennas. IEEE Transactions on Wireless Communications, 2022. 





[110] Roi Méndez-Rial, Cristian Rusu, Nuria González-Prelcic, Ahmed Alkhateeb, and Robert W Heath. Hybrid mimo architectures for millimeter wave communications: Phase shifters or switches? IEEE access, 4:247–267, 2016. 





[111] Shyamnath Gollakota, Samuel David Perli, and Dina Katabi. Interfer ence alignment and cancellation. In Proceedings of the ACM SIGCOMM 2009 conference on Data communication, pages 159–170, 2009. 





[112] Fadel Adib, Swarun Kumar, Omid Aryan, Shyamnath Gollakota, and Dina Katabi. Interference alignment by motion. In Proceedings of the 19th annual international conference on Mobile computing & networking, pages 279–290, 2013. 





[113] Adriana B Flores, Sadia Quadri, and Edward W Knightly. A scalable multi-user uplink for Wi-Fi. In 13th {USENIX} Symposium on Networked Systems Design and Implementation ({NSDI} 16), pages 179–191, 2016. 





[114] Wi-Fi spectrum crunch: How to beat slow speeds in crowded areas. https://www.makeuseof.com/tag/wi-fi-spectrum-crunch/. 

