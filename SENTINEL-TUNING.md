# Sentinel — Ultimate Sunshine (GPU-less, low-latency fork)

This fork is tuned for **one exact machine**: an AWS EC2 `m7i.xlarge` —
4 vCPU Intel Xeon Sapphire Rapids (AVX-512), **no GPU of any kind**
(`/dev/dri/card0` is only a `simple-framebuffer`). All video is encoded in
**software (libx264)**. The goal is the lowest achievable latency and the
most "native" feel that a CPU-only encoder can deliver over a WAN link.

## Why software, and why H.264 only
Measured encode ceilings on this box (synthetic full-motion 1080p60, 4 threads):

| Codec | 1080p60 ceiling | Notes |
|-------|-----------------|-------|
| **H.264** (libx264 ultrafast/zerolatency) | **~309 fps** | huge headroom |
| HEVC (libx265 ultrafast) | ~65 fps | barely realtime, stutters on spikes |
| AV1 (libsvtav1) | sub-realtime | unusable live |

So the host is configured to advertise **H.264 only** (`hevc_mode=1`,
`av1_mode=1`). Real desktop content is lighter than the synthetic test, so the
H.264 headroom in practice is even larger.

## Source modifications (vs upstream)

### 1. Periodic intra-refresh for the software H.264 encoder (`src/video.cpp`)
Upstream's libx264 path only sets `preset` + `tune`. It therefore emits full
**IDR keyframes**, which cause a periodic bitrate spike. On a constrained/WAN
link that spike is exactly what produces the recurring micro-stutter and latency
bumps users feel.

This fork enables **periodic intra-refresh**: the intra (I) blocks are spread
across a moving "wave" so the bitrate stays flat — no keyframe spikes, smoother
pacing, lower peak latency. The refresh period is computed from the negotiated
framerate (≈1 second wave), via the existing config-aware option lambda:

```cpp
{"x264-params"s, [](const config_t &cfg) {
   int period = cfg.framerate >= 30 ? cfg.framerate : 30;
   std::string p = std::to_string(period);
   return "intra-refresh=1:scenecut=0:keyint=" + p + ":min-keyint=" + p;
 }},
```
`scenecut=0` is mandatory with intra-refresh; B-frames are already disabled by
`tune=zerolatency`. On-demand keyframe requests from Moonlight start a new
refresh wave, so loss recovery still works (bounded by the ~1s wave) without the
spike of a full IDR.

### 2. Cheaper color conversion (`src/video.cpp`)
Upstream uses `SWS_LANCZOS | SWS_ACCURATE_RND` for the RGB→YUV swscale step.
On a GPU-less box that is wasted CPU; this fork uses `SWS_FAST_BILINEAR`. The
visual difference is imperceptible at video frame rates, and it frees CPU for
the encoder.

## Runtime configuration (host `sunshine.conf`)
```
encoder = software
capture = x11
sw_preset = superfast      # 3.1x encode headroom at 1080p60; ~20-25% better compression than ultrafast
sw_tune = zerolatency
hevc_mode = 1              # advertise H.264 ONLY
av1_mode = 1
min_threads = 4            # use all 4 vCPUs as parallel encode slices
fec_percentage = 15        # trimmed FEC overhead for constrained uplinks
system_tray = disabled     # headless box: tray D-Bus call otherwise hangs 25s
# plus systemd Nice=-10 on the service (drop-in) for scheduling priority on the 4-core box
```

## The one knob that still matters: client bitrate
Sunshine/Moonlight uses a **fixed** bitrate (no WebRTC-style congestion control).
Set the Moonlight client bitrate to match your **download** speed (start
10–15 Mbps, not 30–50) at 1080p / 60fps / H.264. This is the dominant lever for
smoothness on a weak link.

## Build
See `packaging/sentinel/build-fedora.sh` — builds with gcc14 (Sunshine's
expected toolchain), `-march=native` for Sapphire Rapids, CUDA disabled, into an
isolated prefix so the stock binary remains an instant rollback.
