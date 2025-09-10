import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aks/services/processors/vulkan_processor.dart';
import 'package:aks/services/processors/vulkan/vulkan_bindings.dart';
import 'package:aks/models/crop_state.dart';
import 'package:aks/services/processors/image_processor_interface.dart';
import 'package:aks/services/raw_processor.dart';
import '../test_helper.dart';

void main() {
  test('Debug crop calculations', () async {
    await TestHelper.ensureInitialized();
    
    // Test case: Portrait crop (0.35 to 0.65) on 1000x600
    final width = 1000;
    final height = 600;
    final cropRect = CropRect(left: 0.35, top: 0.0, right: 0.65, bottom: 1.0);
    
    print('\n=== Debug Crop Calculations ===');
    print('Image: ${width}x${height}');
    print('Crop: left=${cropRect.left}, top=${cropRect.top}, right=${cropRect.right}, bottom=${cropRect.bottom}');
    
    // CPU calculation (Dart)
    final cropLeft = (width * cropRect.left).round();
    final cropTop = (height * cropRect.top).round();
    final cropRight = (width * cropRect.right).round();
    final cropBottom = (height * cropRect.bottom).round();
    
    print('\nCPU (Dart .round()):');
    print('  left: ${width} * ${cropRect.left} = ${width * cropRect.left} -> round() = $cropLeft');
    print('  right: ${width} * ${cropRect.right} = ${width * cropRect.right} -> round() = $cropRight');
    print('  top: ${height} * ${cropRect.top} = ${height * cropRect.top} -> round() = $cropTop');
    print('  bottom: ${height} * ${cropRect.bottom} = ${height * cropRect.bottom} -> round() = $cropBottom');
    print('  width: $cropRight - $cropLeft = ${cropRight - cropLeft}');
    print('  height: $cropBottom - $cropTop = ${cropBottom - cropTop}');
    
    // Test different rounding methods
    print('\nAlternative calculations:');
    print('  Using truncate: left=${(width * cropRect.left).truncate()}, right=${(width * cropRect.right).truncate()}');
    print('  Using floor: left=${(width * cropRect.left).floor()}, right=${(width * cropRect.right).floor()}');
    print('  Using ceil: left=${(width * cropRect.left).ceil()}, right=${(width * cropRect.right).ceil()}');
    
    // Direct calculation like GPU was doing
    final directWidth = ((cropRect.right - cropRect.left) * width);
    print('\nDirect calculation (old GPU method):');
    print('  (${cropRect.right} - ${cropRect.left}) * $width = ${cropRect.right - cropRect.left} * $width = $directWidth');
    print('  truncate: ${directWidth.truncate()}');
    print('  round: ${directWidth.round()}');
    
    // Test with actual GPU if available
    if (await VulkanProcessor.isAvailable()) {
      VulkanBindings.initialize();
      
      // Create test pixels
      final pixels = Uint8List(width * height * 3);
      
      final result = VulkanBindings.processImageWithCrop(
        pixels,
        width,
        height,
        Float32List.fromList([
          5500, 0,    // White balance
          0, 0,       // Exposure, Contrast
          0, 0,       // Highlights, Shadows
          0, 0,       // Blacks, Whites
          0, 0,       // Saturation, Vibrance
          0,          // Tone curve enabled
          width.toDouble(),
          height.toDouble(),
        ]),
        cropRect.left,
        cropRect.top,
        cropRect.right,
        cropRect.bottom,
      );
      
      if (result != null) {
        print('\nGPU actual result: ${result.width}x${result.height}');
      }
    }
    
    // Test edge case with 0.1 increments
    print('\n=== Testing crop boundaries ===');
    for (double left in [0.1, 0.2, 0.3, 0.35, 0.351]) {
      for (double right in [0.6, 0.65, 0.651, 0.7]) {
        final l = (1000 * left).round();
        final r = (1000 * right).round();
        final w = r - l;
        print('Crop $left-$right: left=$l, right=$r, width=$w');
      }
    }
  });
}