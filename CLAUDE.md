# CLAUDE.md

Context notes for future Claude (or human) sessions on this repo.

## Highlight recovery mode

LibRaw's `params.highlight` is currently hardcoded to `blend` (value 2) at
`lib/models/image_state.dart` via the `_highlightMode` constant. The full
machinery to expose it as a user preference is in place:

- `lib/models/highlight_mode.dart` — `HighlightMode` enum (clip / blend / reconstruct).
- `lib/ffi/raw/raw_processor_common.c` — native setter. For blend/reconstruct,
  auto-bright is left **off** (`no_auto_bright = 1`) and a fixed **+1.0 EV
  exposure correction** is applied via `params.exp_correc = 1`,
  `params.exp_shift = 2.0`, `params.exp_preser = 1.0`.
  Rationale (measured across 5 fixtures — Sony ARW + Fuji RAF):
  - `params.highlight = 2` (blend) alone darkens the image by ~45% on
    average because it pulls clipped-channel pixels below the output max.
    Opening a picture that suddenly looks dark is jarring.
  - LibRaw's auto-bright with default `auto_bright_thr = 0.01` re-creates
    the same 1%-of-pixels pile-up at 255 that blend was meant to eliminate.
  - `auto_bright_thr = 0` is scene-adaptive but wildly inconsistent: −6%
    on a sky photo, −47% on a dark low-key scene.
  - `params.bright` (output-space multiplier) brightens but loses highlight
    detail to clipping — an image with a lamp in a dim room gets a new
    90k-pixel spike at 255.
  - `exp_shift` with `exp_preser = 1.0` acts in linear light *before*
    gamma, compressing highlights instead of clipping them. +1.0 EV
    (exp_shift = 2.0) brings blend within -15% to +7% of clip's brightness
    across all tested fixtures, with zero re-introduced spikes.

  An earlier version used +0.7 EV (matching darktable's default), which
  left the image still ~25% darker than clip. +1.0 EV is the sweet spot
  where most scenes are indistinguishable from clip at import.
- `lib/services/raw_processor.dart` — plumbed through `loadRawFile(..., highlightMode:)`.

When a real settings panel is introduced:

1. Re-add `getHighlightMode` / `setHighlightMode` to `PreferencesService`
   (they were removed because nothing called them).
2. Load the preference in `ImageState` and expose a `setHighlightMode()`
   method that persists + reloads the current image.
3. Add the selector UI (radio list worked fine).
4. **Reconstruct mode is experimental**: it produces a noticeably darker
   image than clip/blend because libraw's auto-bright is computed from raw
   data stats and doesn't see reconstruct's downstream attenuation. A fixed
   `bright = 2.25` multiplier roughly compensated on the test fixture but is
   scene-dependent and therefore unprincipled. If reconstruct is exposed,
   either calibrate a per-image gain (measure post-decode max, scale to 255)
   or label it clearly as experimental.

## Exposure math

`Exposure` adjustments use linear-light EV: the CPU LUT in
`lib/services/optimized_processor.dart:generateExposureLUT` and the GPU path in
`linux/vulkan_processor/shaders/image_process.comp:applyExposure` both do
`sRGB decode -> * 2^EV -> sRGB encode`. An earlier version did the naive
`byte * 2^EV`, which wildly over-amplified midtones because sRGB is
gamma-encoded. If you touch either function, keep them in sync.

## Native RAW processor build paths

The canonical C source is `lib/ffi/raw/raw_processor_common.{c,h}`. Three
consumers include/compile it:

- Production Linux build (CMake) — `linux/raw_processor/raw_processor_wrapper.c`
  which `#include`s `../../lib/ffi/raw/raw_processor_common.c`.
- Test libraries (`scripts/build_test_libs.sh`) — same wrapper.
- Flatpak (`dev.myyc.aks.yaml`) — same wrapper.
- macOS (`macos/raw_processor/raw_processor.c`) — **standalone copy**, not
  wrapped. If you change the common source, mirror it here too or convert
  macOS to use a wrapper the same way.

All three Linux paths were consolidated onto the wrapper in the
`refactor/cleanup-and-imagestate` branch; prior to that, stale duplicates
at `linux/raw_processor/raw_processor.c` kept drifting.

## Histogram

`lib/widgets/histogram_widget.dart`: the painter caps the 0 / 255 edge bins
at `3 × maxValue` for display so clipped pixels don't dominate the chart.
That's deliberate visualisation, not a bug. The sampling stride is 2D
(`sqrt(cropPixels / target)`), not 1D — see the comment at line 108.
