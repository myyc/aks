import 'package:flutter_test/flutter_test.dart';

import 'package:aks/models/adjustments.dart';
import 'package:aks/models/crop_state.dart';
import 'package:aks/models/edit_pipeline.dart';

EditPipeline _loaded(EditPipeline source) {
  final clone = EditPipeline();
  clone.fromJson(source.toJson());
  return clone;
}

T _findAdjustment<T extends Adjustment>(EditPipeline p, String type) =>
    p.adjustments.firstWhere((a) => a.type == type) as T;

void main() {
  group('EditPipeline.toJson/fromJson', () {
    test('default pipeline roundtrips to default pipeline', () {
      final p = EditPipeline()..initialize('/tmp/x.cr2');
      final loaded = _loaded(p);
      expect(loaded.sourceFile, p.sourceFile);
      expect(loaded.adjustments.length, p.adjustments.length);
      expect(loaded.cropRect, null);
      expect(loaded.hasAdjustments, false);
    });

    test('all 7 adjustment values roundtrip', () {
      final p = EditPipeline()..initialize('/tmp/x.cr2');
      p.updateAdjustment(WhiteBalanceAdjustment(temperature: 4200, tint: -25));
      p.updateAdjustment(ExposureAdjustment(value: 1.25));
      p.updateAdjustment(ContrastAdjustment(value: -30));
      p.updateAdjustment(HighlightsShadowsAdjustment(highlights: -50, shadows: 40));
      p.updateAdjustment(BlacksWhitesAdjustment(blacks: 20, whites: -10));
      p.updateAdjustment(SaturationVibranceAdjustment(saturation: 15, vibrance: 30));
      p.updateAdjustment(ToneCurveAdjustment(
        rgbCurve: const [CurvePoint(0, 0), CurvePoint(128, 180), CurvePoint(255, 255)],
      ));

      final loaded = _loaded(p);

      final wb = _findAdjustment<WhiteBalanceAdjustment>(loaded, 'white_balance');
      expect(wb.temperature, 4200);
      expect(wb.tint, -25);

      final exp = _findAdjustment<ExposureAdjustment>(loaded, 'exposure');
      expect(exp.value, 1.25);

      final con = _findAdjustment<ContrastAdjustment>(loaded, 'contrast');
      expect(con.value, -30);

      final hs = _findAdjustment<HighlightsShadowsAdjustment>(loaded, 'highlights_shadows');
      expect(hs.highlights, -50);
      expect(hs.shadows, 40);

      final bw = _findAdjustment<BlacksWhitesAdjustment>(loaded, 'blacks_whites');
      expect(bw.blacks, 20);
      expect(bw.whites, -10);

      final sv = _findAdjustment<SaturationVibranceAdjustment>(loaded, 'saturation_vibrance');
      expect(sv.saturation, 15);
      expect(sv.vibrance, 30);

      final tc = _findAdjustment<ToneCurveAdjustment>(loaded, 'tone_curve');
      expect(tc.rgbCurve.length, 3);
      expect(tc.rgbCurve[1], const CurvePoint(128, 180));
    });

    test('crop rect roundtrips', () {
      final p = EditPipeline()..initialize('/tmp/x.cr2');
      p.setCropRect(CropRect(left: 0.1, top: 0.2, right: 0.8, bottom: 0.9));
      final loaded = _loaded(p);
      expect(loaded.cropRect, isNotNull);
      expect(loaded.cropRect!.left, 0.1);
      expect(loaded.cropRect!.top, 0.2);
      expect(loaded.cropRect!.right, 0.8);
      expect(loaded.cropRect!.bottom, 0.9);
    });

    test('unknown fields in JSON are ignored (forward compat)', () {
      final p = EditPipeline()..initialize('/tmp/x.cr2');
      p.updateAdjustment(ExposureAdjustment(value: 1.0));
      final json = p.toJson();
      json['future_field'] = 'ignored';
      final loaded = EditPipeline()..fromJson(json);
      final exp = _findAdjustment<ExposureAdjustment>(loaded, 'exposure');
      expect(exp.value, 1.0);
    });

    test('missing adjustments keep defaults', () {
      final loaded = EditPipeline()
        ..fromJson({'version': '1.0', 'source_file': '/tmp/x.cr2'});
      expect(loaded.sourceFile, '/tmp/x.cr2');
      expect(loaded.adjustments.length, greaterThan(0));
      expect(loaded.hasAdjustments, false);
    });

    test('resetAll clears crop and zeros adjustments', () {
      final p = EditPipeline()..initialize('/tmp/x.cr2');
      p.updateAdjustment(ExposureAdjustment(value: 2.5));
      p.setCropRect(CropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9));
      expect(p.hasAdjustments, true);
      p.resetAll();
      expect(p.cropRect, null);
      expect(p.hasAdjustments, false);
    });
  });
}
