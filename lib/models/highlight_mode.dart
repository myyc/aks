/// How to handle channel-level highlight clipping during RAW decode.
///
/// Applied inside libraw (params.highlight) before demosaic/colour-space
/// conversion. The value is fixed per decode — changing it requires
/// re-decoding the RAW file.
enum HighlightMode {
  /// Hard-clip clipped channels to the output maximum.
  ///
  /// Cheapest, preserves channel values exactly where nothing clipped, but
  /// produces a sharp pile-up at 255 on any channel that did clip.
  /// Libraw value: 0.
  clip(0, 'Clip'),

  /// Blend clipped channel values toward the mean of the unclipped channels.
  ///
  /// Keeps the local colour cast instead of going white, and smooths out
  /// the histogram spike. Libraw value: 2.
  blend(2, 'Blend'),

  /// Iteratively reconstruct highlight detail from surrounding pixels.
  ///
  /// Best visual result on sky / window / lamp highlights at the cost of
  /// more decode time. Libraw value: 3.
  reconstruct(3, 'Reconstruct');

  final int librawValue;
  final String label;
  const HighlightMode(this.librawValue, this.label);

  static HighlightMode fromLibrawValue(int value) {
    for (final mode in HighlightMode.values) {
      if (mode.librawValue == value) return mode;
    }
    return HighlightMode.clip;
  }
}
