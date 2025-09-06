import 'package:flutter/material.dart';
import '../models/crop_state.dart';

/// Displays a permanent overlay for an applied crop
/// Shows darkened area outside the crop region
class AppliedCropOverlay extends StatelessWidget {
  final Size imageSize;
  final CropRect cropRect;
  final double overlayOpacity;
  
  const AppliedCropOverlay({
    Key? key,
    required this.imageSize,
    required this.cropRect,
    this.overlayOpacity = 0.7,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: imageSize,
        painter: AppliedCropPainter(
          cropRect: cropRect,
          overlayOpacity: overlayOpacity,
        ),
      ),
    );
  }
}

class AppliedCropPainter extends CustomPainter {
  final CropRect cropRect;
  final double overlayOpacity;
  
  AppliedCropPainter({
    required this.cropRect,
    required this.overlayOpacity,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final rect = cropRect.toPixelRect(size.width, size.height);
    
    // Draw dark overlay outside crop area
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(overlayOpacity)
      ..style = PaintingStyle.fill;
    
    // Create path with hole for crop area
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, overlayPaint);
    
    // Draw subtle border around crop area
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    canvas.drawRect(rect, borderPaint);
  }
  
  @override
  bool shouldRepaint(AppliedCropPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect || 
           oldDelegate.overlayOpacity != overlayOpacity;
  }
}