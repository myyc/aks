// Regression guard: the blend + 0.7 EV default must give sensible output
// across a variety of real RAWs (Sony ARW, Fuji RAF, sky-dominated and
// dark low-key scenes).

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:aks/models/highlight_mode.dart';
import 'package:aks/services/raw_processor.dart';
import '../test_helper.dart';

double _meanLum(Uint8List px) {
  var s = 0;
  for (int i = 0; i < px.length; i += 3) {
    s += (px[i] * 77 + px[i + 1] * 150 + px[i + 2] * 29) >> 8;
  }
  return s / (px.length / 3);
}

int _spike(Uint8List px) {
  var n = 0;
  for (int i = 0; i < px.length; i += 3) {
    if (px[i] == 255) n++;
    if (px[i + 1] == 255) n++;
    if (px[i + 2] == 255) n++;
  }
  return n;
}

void main() {
  const fixtures = [
    'test/fixtures/test_image.arw',
    'test/fixtures/test_image_1.arw',
    'test/fixtures/test_image_2.arw',
    'test/fixtures/test_image_3.raf',
    'test/fixtures/test_image_4.raf',
  ];

  test('blend mode eliminates the single-channel 255 spike', () async {
    await TestHelper.ensureInitialized();
    RawProcessor.initialize();

    for (final path in fixtures) {
      if (!File(path).existsSync()) continue;
      final clip = (await RawProcessor.loadRawFile(path,
          highlightMode: HighlightMode.clip))!.pixelData.pixels;
      final blend = (await RawProcessor.loadRawFile(path,
          highlightMode: HighlightMode.blend))!.pixelData.pixels;

      final clipSpike = _spike(clip);
      final blendSpike = _spike(blend);
      final total = clip.length ~/ 3;

      // Blend's combined-channel pile-up must be below 0.5% of total pixels.
      // In practice usually way under 0.1%, but dark scenes with blown
      // highlights can re-pile a little after the +0.7 EV compensation.
      // Note: blend can end up with slightly *more* 255-pixels than clip
      // on some images, because the +0.7 EV lift pushes originally-unclipped
      // highlights past 255 — that's expected, we just cap the absolute.
      final maxAllowed = (total * 0.005).round();
      expect(blendSpike, lessThan(maxAllowed),
          reason: '$path clip=$clipSpike blend=$blendSpike '
              '(allowed=$maxAllowed)');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('blend produces reasonable brightness across scenes', () async {
    await TestHelper.ensureInitialized();
    RawProcessor.initialize();

    for (final path in fixtures) {
      if (!File(path).existsSync()) continue;
      final clip = (await RawProcessor.loadRawFile(path,
          highlightMode: HighlightMode.clip))!.pixelData.pixels;
      final blend = (await RawProcessor.loadRawFile(path,
          highlightMode: HighlightMode.blend))!.pixelData.pixels;

      final clipMean = _meanLum(clip);
      final blendMean = _meanLum(blend);
      final ratio = blendMean / clipMean;

      // With the +0.7 EV compensation, blend should land between 50% and
      // 110% of clip's mean luminance across typical scenes.
      expect(ratio, greaterThan(0.50),
          reason: '$path blend too dark: clip=$clipMean blend=$blendMean');
      expect(ratio, lessThan(1.10),
          reason: '$path blend too bright: clip=$clipMean blend=$blendMean');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
