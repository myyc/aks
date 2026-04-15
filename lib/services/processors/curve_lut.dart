import 'dart:typed_data';
import '../../models/adjustments.dart';

/// Build a 256-entry lookup table from a tone curve's control points.
///
/// Points are sorted by x. The returned LUT interpolates linearly between
/// adjacent points and clamps beyond the endpoints. An identity curve
/// `[(0,0), (255,255)]` (or fewer than two points) produces an identity LUT.
Uint8List generateCurveLookupTable(List<CurvePoint> points) {
  final lut = Uint8List(256);

  if (points.length < 2) {
    for (int i = 0; i < 256; i++) {
      lut[i] = i;
    }
    return lut;
  }

  final sortedPoints = List<CurvePoint>.from(points)
    ..sort((a, b) => a.x.compareTo(b.x));

  if (sortedPoints.length == 2 &&
      sortedPoints[0].x == 0 && sortedPoints[0].y == 0 &&
      sortedPoints[1].x == 255 && sortedPoints[1].y == 255) {
    for (int i = 0; i < 256; i++) {
      lut[i] = i;
    }
    return lut;
  }

  for (int i = 0; i < sortedPoints[0].x.round() && i < 256; i++) {
    lut[i] = sortedPoints[0].y.round().clamp(0, 255);
  }

  for (int i = 0; i < sortedPoints.length - 1; i++) {
    final p1 = sortedPoints[i];
    final p2 = sortedPoints[i + 1];
    final x1 = p1.x.round().clamp(0, 255);
    final x2 = p2.x.round().clamp(0, 255);

    for (int x = x1; x <= x2 && x < 256; x++) {
      if (p2.x - p1.x != 0) {
        final t = (x - p1.x) / (p2.x - p1.x);
        final y = p1.y + (p2.y - p1.y) * t;
        lut[x] = y.round().clamp(0, 255);
      } else {
        lut[x] = p1.y.round().clamp(0, 255);
      }
    }
  }

  final lastX = sortedPoints.last.x.round().clamp(0, 255);
  for (int i = lastX + 1; i < 256; i++) {
    lut[i] = sortedPoints.last.y.round().clamp(0, 255);
  }

  return lut;
}
