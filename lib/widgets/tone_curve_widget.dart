import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/adjustments.dart';

enum CurveChannel { rgb, red, green, blue }

class ToneCurveWidget extends StatefulWidget {
  final ToneCurveAdjustment adjustment;
  final Function(ToneCurveAdjustment) onChanged;
  final double size;
  
  const ToneCurveWidget({
    Key? key,
    required this.adjustment,
    required this.onChanged,
    this.size = 250,
  }) : super(key: key);
  
  @override
  State<ToneCurveWidget> createState() => _ToneCurveWidgetState();
}

class _ToneCurveWidgetState extends State<ToneCurveWidget> {
  CurveChannel _selectedChannel = CurveChannel.rgb;
  int? _selectedPointIndex;
  
  List<CurvePoint> get _currentCurve {
    switch (_selectedChannel) {
      case CurveChannel.rgb:
        return widget.adjustment.rgbCurve;
      case CurveChannel.red:
        return widget.adjustment.redCurve;
      case CurveChannel.green:
        return widget.adjustment.greenCurve;
      case CurveChannel.blue:
        return widget.adjustment.blueCurve;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Channel selector and reset
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Channel buttons
            Row(
              children: [
                _buildChannelButton(CurveChannel.rgb, 'RGB', Colors.white),
                const SizedBox(width: 8),
                _buildChannelButton(CurveChannel.red, 'R', Colors.red),
                const SizedBox(width: 8),
                _buildChannelButton(CurveChannel.green, 'G', Colors.green),
                const SizedBox(width: 8),
                _buildChannelButton(CurveChannel.blue, 'B', Colors.blue),
              ],
            ),
            // Reset button
            InkWell(
              onTap: _resetCurve,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.refresh,
                  size: 16,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Curve editor
        GestureDetector(
          onPanDown: (details) => _handlePanDown(details.localPosition),
          onPanUpdate: (details) => _handlePanUpdate(details.localPosition),
          onSecondaryTapDown: (details) => _handleRightClick(details.localPosition),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A3A3A)),
            ),
            child: CustomPaint(
              painter: ToneCurvePainter(
                curve: _currentCurve,
                selectedPointIndex: _selectedPointIndex,
                channel: _selectedChannel,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Preset buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _applyLinearPreset,
              child: const Text('Linear', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: _applySCurvePreset,
              child: const Text('S-Curve', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: _applyFadePreset,
              child: const Text('Fade', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildChannelButton(CurveChannel channel, String label, Color color) {
    final isSelected = _selectedChannel == channel;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedChannel = channel);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          border: Border.all(
            color: isSelected ? color : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.white54,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  void _handlePanDown(Offset position) {
    final point = _positionToPoint(position);
    final curve = List<CurvePoint>.from(_currentCurve);
    
    // Check if we're near an existing point
    for (int i = 0; i < curve.length; i++) {
      final distance = (curve[i].x - point.x).abs() + (curve[i].y - point.y).abs();
      if (distance < 20) {
        setState(() => _selectedPointIndex = i);
        return;
      }
    }
    
    // Add new point
    curve.add(point);
    curve.sort((a, b) => a.x.compareTo(b.x));
    _updateCurve(curve);
    
    // Select the new point
    for (int i = 0; i < curve.length; i++) {
      if (curve[i] == point) {
        setState(() => _selectedPointIndex = i);
        break;
      }
    }
  }
  
  void _handlePanUpdate(Offset position) {
    if (_selectedPointIndex == null) return;
    
    final curve = List<CurvePoint>.from(_currentCurve);
    final oldPoint = curve[_selectedPointIndex!];
    final point = _positionToPoint(position);
    
    // Don't allow moving the first and last points horizontally
    if (_selectedPointIndex == 0) {
      curve[0] = CurvePoint(0, point.y.clamp(0, 255));
    } else if (_selectedPointIndex == curve.length - 1) {
      curve[curve.length - 1] = CurvePoint(255, point.y.clamp(0, 255));
    } else {
      // Ensure point doesn't cross neighbors
      final minX = curve[_selectedPointIndex! - 1].x + 1;
      final maxX = curve[_selectedPointIndex! + 1].x - 1;
      curve[_selectedPointIndex!] = CurvePoint(
        point.x.clamp(minX, maxX),
        point.y.clamp(0, 255),
      );
    }
    
    _updateCurve(curve);
  }
  
  void _handleRightClick(Offset position) {
    final point = _positionToPoint(position);
    final curve = List<CurvePoint>.from(_currentCurve);
    
    // Find the closest point to remove
    int? pointToRemove;
    double minDistance = double.infinity;
    
    for (int i = 0; i < curve.length; i++) {
      // Don't allow removing the first and last points (endpoints)
      if (i == 0 || i == curve.length - 1) continue;
      
      final distance = (curve[i].x - point.x).abs() + (curve[i].y - point.y).abs();
      if (distance < 20 && distance < minDistance) {
        minDistance = distance;
        pointToRemove = i;
      }
    }
    
    // Remove the point if found
    if (pointToRemove != null) {
      final removedPoint = curve[pointToRemove];
      curve.removeAt(pointToRemove);
      _updateCurve(curve);
      setState(() => _selectedPointIndex = null);
    } else {
      // Try to add a new point if not removing
      if (curve.length < 10) {
        curve.add(CurvePoint(point.x, point.y));
        curve.sort((a, b) => a.x.compareTo(b.x));
        _updateCurve(curve);
      }
    }
  }
  
  CurvePoint _positionToPoint(Offset position) {
    final x = (position.dx / widget.size * 255).clamp(0, 255).toDouble();
    final y = ((1 - position.dy / widget.size) * 255).clamp(0, 255).toDouble();
    
    // Snap to diagonal if close (within 5 units)
    const snapThreshold = 5.0;
    if ((x - y).abs() < snapThreshold) {
      return CurvePoint(x, x);
    }
    
    return CurvePoint(x, y);
  }
  
  void _updateCurve(List<CurvePoint> curve) {
    final newAdjustment = widget.adjustment.copyWith(
      rgbCurve: _selectedChannel == CurveChannel.rgb ? curve : null,
      redCurve: _selectedChannel == CurveChannel.red ? curve : null,
      greenCurve: _selectedChannel == CurveChannel.green ? curve : null,
      blueCurve: _selectedChannel == CurveChannel.blue ? curve : null,
    );
    widget.onChanged(newAdjustment);
  }
  
  void _resetCurve() {
    // Reset only the current channel to default linear
    final defaultCurve = [CurvePoint(0, 0), CurvePoint(255, 255)];
    
    final newAdjustment = ToneCurveAdjustment(
      rgbCurve: _selectedChannel == CurveChannel.rgb ? defaultCurve : widget.adjustment.rgbCurve,
      redCurve: _selectedChannel == CurveChannel.red ? defaultCurve : widget.adjustment.redCurve,
      greenCurve: _selectedChannel == CurveChannel.green ? defaultCurve : widget.adjustment.greenCurve,
      blueCurve: _selectedChannel == CurveChannel.blue ? defaultCurve : widget.adjustment.blueCurve,
    );
    
    widget.onChanged(newAdjustment);
    setState(() => _selectedPointIndex = null);
  }
  
  void _applyLinearPreset() {
    _updateCurve([CurvePoint(0, 0), CurvePoint(255, 255)]);
  }
  
  void _applySCurvePreset() {
    _updateCurve([
      CurvePoint(0, 0),
      CurvePoint(64, 48),
      CurvePoint(192, 208),
      CurvePoint(255, 255),
    ]);
  }
  
  void _applyFadePreset() {
    _updateCurve([
      CurvePoint(0, 20),
      CurvePoint(255, 235),
    ]);
  }
}

class ToneCurvePainter extends CustomPainter {
  final List<CurvePoint> curve;
  final int? selectedPointIndex;
  final CurveChannel channel;
  
  ToneCurvePainter({
    required this.curve,
    this.selectedPointIndex,
    required this.channel,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 0.5;
    
    for (int i = 1; i < 4; i++) {
      final pos = size.width * i / 4;
      canvas.drawLine(Offset(pos, 0), Offset(pos, size.height), gridPaint);
      canvas.drawLine(Offset(0, pos), Offset(size.width, pos), gridPaint);
    }
    
    // Draw diagonal reference line
    final diagonalPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      diagonalPaint,
    );
    
    // Generate interpolated curve
    final lookupTable = _generateLookupTable(curve);
    
    // Draw curve
    final curvePaint = Paint()
      ..color = _getChannelColor()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    for (int i = 0; i < 256; i++) {
      final x = i / 255 * size.width;
      final y = (1 - lookupTable[i] / 255) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, curvePaint);
    
    // Draw control points
    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    for (int i = 0; i < curve.length; i++) {
      final x = curve[i].x / 255 * size.width;
      final y = (1 - curve[i].y / 255) * size.height;
      
      if (i == selectedPointIndex) {
        // Draw selected point larger
        canvas.drawCircle(Offset(x, y), 6, pointPaint);
        canvas.drawCircle(
          Offset(x, y),
          6,
          Paint()
            ..color = _getChannelColor()
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      } else {
        canvas.drawCircle(Offset(x, y), 4, pointPaint);
      }
    }
  }
  
  Color _getChannelColor() {
    switch (channel) {
      case CurveChannel.rgb:
        return Colors.white;
      case CurveChannel.red:
        return Colors.red;
      case CurveChannel.green:
        return Colors.green;
      case CurveChannel.blue:
        return Colors.blue;
    }
  }
  
  // Generate lookup table using appropriate interpolation
  List<double> _generateLookupTable(List<CurvePoint> points) {
    if (points.length < 2) {
      return List.generate(256, (i) => i.toDouble());
    }
    
    final lut = List<double>.filled(256, 0);
    
    // Handle points before first control point
    for (int i = 0; i <= points[0].x; i++) {
      lut[i] = points[0].y;
    }
    
    // Use linear interpolation for 2 points, Catmull-Rom for 3+
    if (points.length == 2) {
      // Simple linear interpolation between two points
      final p1 = points[0];
      final p2 = points[1];
      for (int x = p1.x.round(); x <= p2.x.round(); x++) {
        final t = (x - p1.x) / (p2.x - p1.x);
        final y = p1.y + (p2.y - p1.y) * t;
        lut[x] = y.clamp(0, 255);
      }
    } else {
      // Use Catmull-Rom spline for smooth curves with 3+ points
      for (int i = 0; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        
        // Get control points for Catmull-Rom
        final p0 = i > 0 ? points[i - 1] : p1;
        final p3 = i < points.length - 2 ? points[i + 2] : p2;
        
        for (int x = p1.x.round(); x <= p2.x.round(); x++) {
          final t = (x - p1.x) / (p2.x - p1.x);
          final y = _catmullRom(p0.y, p1.y, p2.y, p3.y, t);
          lut[x] = y.clamp(0, 255);
        }
      }
    }
    
    // Handle points after last control point
    for (int i = points.last.x.round(); i < 256; i++) {
      lut[i] = points.last.y;
    }
    
    return lut;
  }
  
  double _catmullRom(double p0, double p1, double p2, double p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    
    return 0.5 * (
      2 * p1 +
      (-p0 + p2) * t +
      (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
      (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    );
  }
  
  @override
  bool shouldRepaint(ToneCurvePainter oldDelegate) {
    return curve != oldDelegate.curve ||
           selectedPointIndex != oldDelegate.selectedPointIndex ||
           channel != oldDelegate.channel;
  }
}