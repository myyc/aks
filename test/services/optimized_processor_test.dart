import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:aks/services/optimized_processor.dart';

Uint8List _pixels(List<int> rgb) => Uint8List.fromList(rgb);

void main() {
  setUp(OptimizedProcessor.clearCache);

  group('generateExposureLUT', () {
    test('zero exposure is identity', () {
      final lut = OptimizedProcessor.generateExposureLUT(0);
      for (int i = 0; i < 256; i++) {
        expect(lut[i], i);
      }
    });

    // Exposure is applied in linear light (sRGB decode -> *2^EV -> encode).
    // The sRGB encoding is non-linear, so sRGB-byte values do NOT scale
    // linearly with the EV factor. Expectations below come from the sRGB
    // piecewise curve.

    test('+1 EV: mid-tones lift but do not clip', () {
      final lut = OptimizedProcessor.generateExposureLUT(1);
      expect(lut[0], 0);
      // sRGB 128 -> linear ~0.216 -> x2 = 0.432 -> sRGB ~0.701 -> byte ~179.
      expect(lut[128], closeTo(179, 4));
      // sRGB 255 -> linear 1.0 -> x2 saturates -> sRGB 255.
      expect(lut[255], 255);
      // +1 EV must be monotonic and strictly brighter than identity
      // everywhere except endpoints.
      for (int i = 1; i < 255; i++) {
        expect(lut[i], greaterThan(i));
      }
    });

    test('-1 EV: mid-tones darken without crushing', () {
      final lut = OptimizedProcessor.generateExposureLUT(-1);
      expect(lut[0], 0);
      // sRGB 128 -> linear ~0.216 -> /2 = 0.108 -> sRGB ~0.373 -> byte ~95.
      expect(lut[128], closeTo(95, 4));
      // sRGB 255 -> linear 1.0 -> /2 = 0.5 -> sRGB ~0.735 -> byte ~188.
      expect(lut[255], closeTo(188, 4));
      // Skip deep shadows where rounding can pin the byte to its input.
      for (int i = 5; i < 255; i++) {
        expect(lut[i], lessThan(i),
            reason: '-1 EV should darken byte $i, got ${lut[i]}');
      }
    });

    test('+1 EV then -1 EV round-trips within rounding', () {
      final up = OptimizedProcessor.generateExposureLUT(1);
      final down = OptimizedProcessor.generateExposureLUT(-1);
      for (int i = 0; i < 256; i++) {
        final back = down[up[i]];
        // Allow 2-step drift from double rounding through both LUTs, plus
        // the one-sided loss near saturation.
        if (up[i] == 255) continue;
        expect((back - i).abs(), lessThanOrEqualTo(2));
      }
    });
  });

  group('generateContrastLUT', () {
    test('zero contrast is identity', () {
      final lut = OptimizedProcessor.generateContrastLUT(0);
      for (int i = 0; i < 256; i++) {
        expect(lut[i], i);
      }
    });

    test('positive contrast pushes away from 128', () {
      final lut = OptimizedProcessor.generateContrastLUT(50);
      expect(lut[128], 128);
      expect(lut[0], 0); // (0-128)*1.5+128 = -64 → 0
      expect(lut[255], 255);
      expect(lut[64], lessThan(64));
      expect(lut[192], greaterThan(192));
    });
  });

  group('applyWhiteBalanceFast', () {
    test('neutral (5500K, 0 tint) is a no-op', () {
      final p = _pixels([100, 150, 200]);
      OptimizedProcessor.applyWhiteBalanceFast(p, 5500, 0);
      expect(p, [100, 150, 200]);
    });

    test('warmer temperature boosts red, reduces blue', () {
      final p = _pixels([100, 100, 100]);
      OptimizedProcessor.applyWhiteBalanceFast(p, 3000, 0);
      expect(p[0], greaterThan(100));
      expect(p[2], lessThan(100));
    });

    test('cooler temperature boosts blue, reduces red', () {
      final p = _pixels([100, 100, 100]);
      OptimizedProcessor.applyWhiteBalanceFast(p, 8000, 0);
      expect(p[0], lessThan(100));
      expect(p[2], greaterThan(100));
    });
  });

  group('applySaturationFast', () {
    test('zero saturation is a no-op', () {
      final p = _pixels([120, 40, 200]);
      final copy = Uint8List.fromList(p);
      OptimizedProcessor.applySaturationFast(p, 0);
      expect(p, copy);
    });

    test('-100 saturation collapses to gray', () {
      final p = _pixels([200, 100, 50]);
      OptimizedProcessor.applySaturationFast(p, -100);
      // All three channels should converge (within 1 of each other).
      expect((p[0] - p[1]).abs(), lessThanOrEqualTo(2));
      expect((p[1] - p[2]).abs(), lessThanOrEqualTo(2));
    });

    test('+100 saturation pushes channels further from gray', () {
      final p = _pixels([180, 120, 60]);
      final before = (p[0] - p[2]).abs();
      OptimizedProcessor.applySaturationFast(p, 100);
      final after = (p[0] - p[2]).abs();
      expect(after, greaterThan(before));
    });
  });

  group('applyVibranceFast', () {
    test('zero vibrance is a no-op', () {
      final p = _pixels([120, 40, 200]);
      final copy = Uint8List.fromList(p);
      OptimizedProcessor.applyVibranceFast(p, 0);
      expect(p, copy);
    });

    test('positive vibrance increases distance from gray for low-sat pixels', () {
      final lowSat = _pixels([130, 125, 120]);
      final before = (lowSat[0] - lowSat[2]).abs();
      OptimizedProcessor.applyVibranceFast(lowSat, 50);
      final after = (lowSat[0] - lowSat[2]).abs();
      expect(after, greaterThan(before));
    });

    test('positive vibrance boosts low-sat pixels by a higher ratio than high-sat', () {
      // Vibrance is designed so the *relative* factor is bigger for low-sat
      // pixels (it protects already-saturated colors). Absolute deltas still
      // scale with the pixel's distance from gray, so we compare ratios.
      final lowSat = _pixels([130, 125, 120]);
      final highSat = _pixels([220, 110, 30]);
      final lowBefore = (lowSat[0] - lowSat[2]).abs();
      final highBefore = (highSat[0] - highSat[2]).abs();

      OptimizedProcessor.applyVibranceFast(lowSat, 50);
      OptimizedProcessor.applyVibranceFast(highSat, 50);

      final lowRatio = (lowSat[0] - lowSat[2]).abs() / lowBefore;
      final highRatio = (highSat[0] - highSat[2]).abs() / highBefore;

      expect(lowRatio, greaterThan(highRatio));
    });
  });

  group('applyHighlightsShadowsLUT', () {
    test('neutral (0, 0) is a no-op', () {
      final p = _pixels([50, 128, 220]);
      final copy = Uint8List.fromList(p);
      OptimizedProcessor.applyHighlightsShadowsLUT(p, 0, 0);
      expect(p, copy);
    });

    test('positive shadows lifts dark pixels', () {
      final dark = _pixels([30, 30, 30]);
      OptimizedProcessor.applyHighlightsShadowsLUT(dark, 0, 100);
      expect(dark[0], greaterThan(30));
    });

    test('negative highlights darkens bright pixels', () {
      final bright = _pixels([220, 220, 220]);
      OptimizedProcessor.applyHighlightsShadowsLUT(bright, -100, 0);
      expect(bright[0], lessThan(220));
    });
  });
}
