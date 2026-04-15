import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../models/crop_state.dart';

class HistogramWidget extends StatelessWidget {
  final ui.Image? image;
  final double width;
  final double height;
  final bool showRGB;
  final CropRect? cropRect;
  
  const HistogramWidget({
    Key? key,
    required this.image,
    this.width = 256,
    this.height = 100,
    this.showRGB = true,
    this.cropRect,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return const SizedBox.shrink();
    }
    
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: FutureBuilder<HistogramData>(
          future: _calculateHistogram(image!, cropRect),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white30),
                  ),
                ),
              );
            }
            
            return CustomPaint(
              painter: HistogramPainter(
                data: snapshot.data!,
                showRGB: showRGB,
              ),
            );
          },
        ),
      ),
    );
  }
  
  Future<HistogramData> _calculateHistogram(ui.Image image, CropRect? cropRect) async {
    // Get image bytes
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return HistogramData.empty();
    }
    
    final bytes = byteData.buffer.asUint8List();
    
    
    // Initialize histogram arrays
    final redHistogram = List<int>.filled(256, 0);
    final greenHistogram = List<int>.filled(256, 0);
    final blueHistogram = List<int>.filled(256, 0);
    final luminanceHistogram = List<int>.filled(256, 0);
    
    // Calculate crop bounds in pixels
    final imageWidth = image.width;
    final imageHeight = image.height;
    int cropLeft = 0;
    int cropTop = 0;
    int cropRight = imageWidth;
    int cropBottom = imageHeight;
    
    if (cropRect != null) {
      cropLeft = (cropRect.left * imageWidth).round();
      cropTop = (cropRect.top * imageHeight).round();
      cropRight = (cropRect.right * imageWidth).round();
      cropBottom = (cropRect.bottom * imageHeight).round();
    }
    
    // Calculate crop area size for sampling
    final cropWidth = cropRight - cropLeft;
    final cropHeight = cropBottom - cropTop;
    final cropPixels = cropWidth * cropHeight;

    // Sample target: ~50000 pixels. sampleRate is a 2D step (applied in both
    // x and y), so the stride is sqrt(total / target) — not total / target.
    const sampleTarget = 50000;
    final sampleRate = cropPixels <= sampleTarget
        ? 1
        : math.max(1, math.sqrt(cropPixels / sampleTarget).round());
    
    // Calculate histograms. RGBA format: each pixel is 4 bytes [R, G, B, A].
    for (int y = cropTop; y < cropBottom; y += sampleRate) {
      for (int x = cropLeft; x < cropRight; x += sampleRate) {
        final pixelIndex = y * imageWidth + x;
        final byteIndex = pixelIndex * 4;

        if (byteIndex + 3 >= bytes.length) continue;

        final r = bytes[byteIndex];
        final g = bytes[byteIndex + 1];
        final b = bytes[byteIndex + 2];
        final a = bytes[byteIndex + 3];

        if (a == 0) continue;

        redHistogram[r]++;
        greenHistogram[g]++;
        blueHistogram[b]++;

        final lum = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        luminanceHistogram[lum]++;
      }
    }
    
    return HistogramData(
      red: redHistogram,
      green: greenHistogram,
      blue: blueHistogram,
      luminance: luminanceHistogram,
    );
  }
}

class HistogramData {
  final List<int> red;
  final List<int> green;
  final List<int> blue;
  final List<int> luminance;

  /// Smoothed versions of the raw counts, used for display. The painter reads
  /// from these so visual noise (per-bin quantisation spikes, isolated ticks
  /// caused by integer rounding through adjustment LUTs) is damped out.
  /// Lightroom / Darktable do the same — the histogram is for at-a-glance
  /// tonal assessment, not per-bin pixel counts.
  late final List<double> redSmooth;
  late final List<double> greenSmooth;
  late final List<double> blueSmooth;
  late final List<double> luminanceSmooth;

  HistogramData({
    required this.red,
    required this.green,
    required this.blue,
    required this.luminance,
  }) {
    redSmooth = _smooth(red);
    greenSmooth = _smooth(green);
    blueSmooth = _smooth(blue);
    luminanceSmooth = _smooth(luminance);
  }

  factory HistogramData.empty() {
    return HistogramData(
      red: List<int>.filled(256, 0),
      green: List<int>.filled(256, 0),
      blue: List<int>.filled(256, 0),
      luminance: List<int>.filled(256, 0),
    );
  }

  /// Gaussian-ish blur (5-tap binomial kernel [1,4,6,4,1]/16) applied twice
  /// — equivalent to a sigma ≈ 1.4 blur. Soft enough to keep the overall
  /// shape, strong enough to fuse single-bin spikes with their neighbours.
  static List<double> _smooth(List<int> histogram) {
    const kernel = [1.0, 4.0, 6.0, 4.0, 1.0];
    const sum = 16.0;

    List<double> pass(List<double> src) {
      final out = List<double>.filled(src.length, 0);
      for (int i = 0; i < src.length; i++) {
        double acc = 0;
        for (int k = -2; k <= 2; k++) {
          // Clamp-at-edge sampling.
          final j = (i + k).clamp(0, src.length - 1);
          acc += src[j] * kernel[k + 2];
        }
        out[i] = acc / sum;
      }
      return out;
    }

    final first = pass(histogram.map((v) => v.toDouble()).toList());
    return pass(first);
  }

  /// Max over the smoothed RGB channels, used to scale the painter's y-axis.
  /// Operates on smoothed data so the scale matches what's drawn.
  double get maxValue {
    double max = 0;
    for (int i = 0; i < 256; i++) {
      if (redSmooth[i] > max) max = redSmooth[i];
      if (greenSmooth[i] > max) max = greenSmooth[i];
      if (blueSmooth[i] > max) max = blueSmooth[i];
    }
    return max;
  }
}

class HistogramPainter extends CustomPainter {
  final HistogramData data;
  final bool showRGB;
  
  HistogramPainter({
    required this.data,
    required this.showRGB,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = data.maxValue;
    if (maxValue == 0) return;

    final binWidth = size.width / 256;

    if (showRGB) {
      _drawChannel(canvas, size, data.redSmooth,
          Colors.red.withOpacity(0.5), maxValue, binWidth);
      _drawChannel(canvas, size, data.greenSmooth,
          Colors.green.withOpacity(0.5), maxValue, binWidth);
      _drawChannel(canvas, size, data.blueSmooth,
          Colors.blue.withOpacity(0.5), maxValue, binWidth);
    } else {
      _drawChannel(canvas, size, data.luminanceSmooth,
          Colors.white.withOpacity(0.7), maxValue, binWidth);
    }

    _drawGrid(canvas, size);
  }

  void _drawChannel(Canvas canvas, Size size, List<double> histogram,
      Color color, double maxValue, double binWidth) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height);

    for (int i = 0; i < 256; i++) {
      final x = i * binWidth;
      final height = (histogram[i] / maxValue) * size.height * 0.9;
      final y = size.height - height;

      if (i == 0) {
        path.lineTo(x, y);
      } else {
        // Smooth curve
        final prevX = (i - 1) * binWidth;
        final controlX = (prevX + x) / 2;
        path.quadraticBezierTo(controlX, y, x, y);
      }
    }
    
    path.lineTo(size.width, size.height);
    path.close();
    
    canvas.drawPath(path, paint);
  }
  
  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    
    // Vertical lines at quarters
    for (int i = 1; i < 4; i++) {
      final x = (size.width / 4) * i;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
    
    // Horizontal line at middle
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }
  
  @override
  bool shouldRepaint(HistogramPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.showRGB != showRGB;
  }
}