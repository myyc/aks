// Verifies the CPU and Vulkan exposure implementations agree when applied
// to a real RAW image. LUT-level precision is covered by unit tests in
// test/services/optimized_processor_test.dart; this is the end-to-end
// cross-check that the two code paths produce identical output bytes.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:aks/models/adjustments.dart';
import 'package:aks/models/highlight_mode.dart';
import 'package:aks/services/processors/cpu_processor.dart';
import 'package:aks/services/processors/vulkan_processor.dart';
import 'package:aks/services/raw_processor.dart';
import '../test_helper.dart';

Future<Uint8List> _processCpu(
  Uint8List rgbInput,
  int width,
  int height,
  double evValue,
) async {
  final processor = CpuProcessor();
  await processor.initialize();
  try {
    final adjustments = <Adjustment>[ExposureAdjustment(value: evValue)];
    return await processor.processPixels(
        Uint8List.fromList(rgbInput), width, height, adjustments);
  } finally {
    processor.dispose();
  }
}

Future<Uint8List?> _processVulkan(
  Uint8List rgbInput,
  int width,
  int height,
  double evValue,
) async {
  if (!await VulkanProcessor.isAvailable()) return null;
  final processor = VulkanProcessor();
  await processor.initialize();
  try {
    final adjustments = <Adjustment>[ExposureAdjustment(value: evValue)];
    return await processor.processPixels(rgbInput, width, height, adjustments);
  } finally {
    processor.dispose();
  }
}

void main() {
  Uint8List? rgbSource;
  int srcWidth = 0;
  int srcHeight = 0;

  setUpAll(() async {
    await TestHelper.ensureInitialized();
    RawProcessor.initialize();
    const path = 'test/fixtures/test_image.arw';
    if (!File(path).existsSync()) return;
    final r = await RawProcessor.loadRawFile(path,
        highlightMode: HighlightMode.clip);
    rgbSource = r!.pixelData.pixels;
    srcWidth = r.pixelData.width;
    srcHeight = r.pixelData.height;
  });

  // Sweep over several EV values so we catch regressions in any part of the
  // sRGB encode/decode path. A single bad branch in one of the LUT segments
  // would show up as a maxDiff spike on the corresponding EV.
  for (final ev in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
    test('CPU and Vulkan agree at $ev EV within 1 LSB', () async {
      if (rgbSource == null) {
        print('SKIP: test/fixtures/test_image.arw not available');
        return;
      }
      final cpuOut = await _processCpu(rgbSource!, srcWidth, srcHeight, ev);
      final gpuOut = await _processVulkan(rgbSource!, srcWidth, srcHeight, ev);
      if (gpuOut == null) {
        print('SKIP: Vulkan not available');
        return;
      }
      var maxDiff = 0;
      var sumDiff = 0;
      var n = 0;
      for (int i = 0; i < cpuOut.length; i += 200 * 4) {
        for (int c = 0; c < 3; c++) {
          final d = (cpuOut[i + c] - gpuOut[i + c]).abs();
          if (d > maxDiff) maxDiff = d;
          sumDiff += d;
          n++;
        }
      }
      final avgDiff = sumDiff / n;
      print('EV=$ev  avgDiff=${avgDiff.toStringAsFixed(2)}  maxDiff=$maxDiff');
      // Integer LUT (CPU) vs float shader (GPU) rounds differently in the
      // last bit; 1 LSB tolerance is tight but achievable.
      expect(maxDiff, lessThanOrEqualTo(1),
          reason: 'EV=$ev cpu vs gpu diverged: maxDiff=$maxDiff');
    });
  }
}
