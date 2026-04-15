import 'package:flutter_test/flutter_test.dart';

import 'package:aks/models/adjustments.dart';
import 'package:aks/services/processors/curve_lut.dart';

void main() {
  group('generateCurveLookupTable', () {
    test('identity curve produces identity LUT', () {
      final lut = generateCurveLookupTable([
        const CurvePoint(0, 0),
        const CurvePoint(255, 255),
      ]);
      expect(lut.length, 256);
      for (int i = 0; i < 256; i++) {
        expect(lut[i], i);
      }
    });

    test('empty / single-point input produces identity', () {
      final empty = generateCurveLookupTable([]);
      final single = generateCurveLookupTable([const CurvePoint(128, 200)]);
      for (int i = 0; i < 256; i++) {
        expect(empty[i], i);
        expect(single[i], i);
      }
    });

    test('midpoint shift lifts or darkens accordingly', () {
      // Raising the midpoint lifts mids towards white.
      final lifted = generateCurveLookupTable([
        const CurvePoint(0, 0),
        const CurvePoint(128, 192),
        const CurvePoint(255, 255),
      ]);
      expect(lifted[0], 0);
      expect(lifted[128], 192);
      expect(lifted[255], 255);
      // Interpolated midway between 0 and 128 → ~96
      expect(lifted[64], closeTo(96, 1));
    });

    test('out-of-order control points are sorted by x', () {
      final a = generateCurveLookupTable([
        const CurvePoint(255, 255),
        const CurvePoint(0, 0),
        const CurvePoint(128, 100),
      ]);
      final b = generateCurveLookupTable([
        const CurvePoint(0, 0),
        const CurvePoint(128, 100),
        const CurvePoint(255, 255),
      ]);
      for (int i = 0; i < 256; i++) {
        expect(a[i], b[i]);
      }
    });

    test('values before first point are clamped to first point y', () {
      final lut = generateCurveLookupTable([
        const CurvePoint(50, 100),
        const CurvePoint(200, 220),
      ]);
      // Before x=50, y is flat at 100.
      expect(lut[0], 100);
      expect(lut[25], 100);
      // After x=200, y is flat at 220.
      expect(lut[220], 220);
      expect(lut[255], 220);
      // Between 50 and 200, interpolates.
      expect(lut[125], closeTo(160, 1));
    });

    test('output is always clamped to [0, 255]', () {
      final lut = generateCurveLookupTable([
        const CurvePoint(0, -50),
        const CurvePoint(255, 400),
      ]);
      for (int i = 0; i < 256; i++) {
        expect(lut[i], inInclusiveRange(0, 255));
      }
    });
  });
}
