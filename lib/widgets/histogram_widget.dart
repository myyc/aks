import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
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
    
    // Sample every nth pixel for performance
    final sampleRate = math.max(1, cropPixels ~/ 50000);
    
    // Calculate histograms
    // RGBA format: each pixel is 4 bytes [R, G, B, A]
    int pixelCount = 0;
    
    // Process only pixels within the crop area with sampling
    for (int y = cropTop; y < cropBottom; y += sampleRate) {
      for (int x = cropLeft; x < cropRight; x += sampleRate) {
        // Calculate byte index for this pixel
        final pixelIndex = y * imageWidth + x;
        final byteIndex = pixelIndex * 4;
        
        // Make sure we don't go out of bounds
        if (byteIndex + 3 >= bytes.length) continue;
        
        final r = bytes[byteIndex];
        final g = bytes[byteIndex + 1];
        final b = bytes[byteIndex + 2];
        final a = bytes[byteIndex + 3];
        
        // Skip fully transparent pixels
        if (a == 0) continue;
        
        pixelCount++;
        
        redHistogram[r]++;
        greenHistogram[g]++;
        blueHistogram[b]++;
        
        // Calculate luminance
        final lum = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        luminanceHistogram[lum]++;
      }
    }
    
    // Check for clipping in all channels
    int clippedRed = 0, clippedGreen = 0, clippedBlue = 0;
    int blackRed = 0, blackGreen = 0, blackBlue = 0;
    
    for (int i = 0; i < 256; i++) {
      if (i == 255) {
        clippedRed = redHistogram[i];
        clippedGreen = greenHistogram[i];
        clippedBlue = blueHistogram[i];
      }
      if (i == 0) {
        blackRed = redHistogram[i];
        blackGreen = greenHistogram[i];
        blackBlue = blueHistogram[i];
      }
    }
    
    // Calculate mean values for logging
    double meanRed = 0, meanGreen = 0, meanBlue = 0;
    int totalPixels = 0;
    for (int i = 0; i < 256; i++) {
      meanRed += i * redHistogram[i];
      meanGreen += i * greenHistogram[i];
      meanBlue += i * blueHistogram[i];
      totalPixels += redHistogram[i]; // All channels should have same count
    }
    
    if (totalPixels > 0) {
      meanRed /= totalPixels;
      meanGreen /= totalPixels;
      meanBlue /= totalPixels;
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
  
  HistogramData({
    required this.red,
    required this.green,
    required this.blue,
    required this.luminance,
  });
  
  factory HistogramData.empty() {
    return HistogramData(
      red: List<int>.filled(256, 0),
      green: List<int>.filled(256, 0),
      blue: List<int>.filled(256, 0),
      luminance: List<int>.filled(256, 0),
    );
  }
  
  int get maxValue {
    // Find the maximum value, but ignore extreme outliers at 0 and 255
    // which often represent clipped shadows/highlights
    int max = 0;
    for (int i = 1; i < 255; i++) {  // Skip 0 and 255
      max = math.max(max, red[i]);
      max = math.max(max, green[i]);
      max = math.max(max, blue[i]);
    }
    
    // Also consider 0 and 255 but cap them to not dominate
    final edge0 = math.max(red[0], math.max(green[0], blue[0]));
    final edge255 = math.max(red[255], math.max(green[255], blue[255]));
    
    // If edges are more than 3x the max, cap them
    if (edge0 > max * 3) {
      max = math.max(max, edge0 ~/ 3);
    } else {
      max = math.max(max, edge0);
    }
    
    if (edge255 > max * 3) {
      max = math.max(max, edge255 ~/ 3);
    } else {
      max = math.max(max, edge255);
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
      // Draw RGB channels
      _drawChannel(canvas, size, data.red, Colors.red.withOpacity(0.5), maxValue, binWidth);
      _drawChannel(canvas, size, data.green, Colors.green.withOpacity(0.5), maxValue, binWidth);
      _drawChannel(canvas, size, data.blue, Colors.blue.withOpacity(0.5), maxValue, binWidth);
    } else {
      // Draw luminance only
      _drawChannel(canvas, size, data.luminance, Colors.white.withOpacity(0.7), maxValue, binWidth);
    }
    
    // Draw grid lines
    _drawGrid(canvas, size);
  }
  
  void _drawChannel(Canvas canvas, Size size, List<int> histogram, Color color, int maxValue, double binWidth) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final path = Path();
    path.moveTo(0, size.height);
    
    for (int i = 0; i < 256; i++) {
      final x = i * binWidth;
      
      // Special handling for edge values (0 and 255) which often spike
      double displayValue = histogram[i].toDouble();
      if ((i == 0 || i == 255) && histogram[i] > maxValue * 3) {
        // Cap extreme spikes at the edges for better visualization
        displayValue = maxValue * 3.0;
      }
      
      final height = (displayValue / maxValue) * size.height * 0.9; // 90% max height
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