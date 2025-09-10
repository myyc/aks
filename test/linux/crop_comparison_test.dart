import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

import 'package:aks/services/processors/cpu_processor.dart';
import 'package:aks/services/processors/vulkan_processor.dart';
import 'package:aks/services/processors/vulkan/vulkan_bindings.dart';
import 'package:aks/services/processors/image_processor_interface.dart';
import 'package:aks/models/adjustments.dart';
import 'package:aks/models/crop_state.dart';
import 'package:aks/services/raw_processor.dart';
import 'package:aks/services/image_processor.dart';
import '../test_helper.dart';

void main() {
  group('CPU vs GPU Crop Comparison Tests', () {
    late Uint8List testPixels;
    late int imageWidth;
    late int imageHeight;
    
    setUpAll(() async {
      await TestHelper.ensureInitialized();
      
      // Create a test image with known pattern for verification
      // Landscape image: 1000x600
      imageWidth = 1000;
      imageHeight = 600;
      final pixelCount = imageWidth * imageHeight;
      testPixels = Uint8List(pixelCount * 3); // RGB
      
      // Create a gradient pattern for easy verification
      // Red increases left to right, Green increases top to bottom
      for (int y = 0; y < imageHeight; y++) {
        for (int x = 0; x < imageWidth; x++) {
          final idx = (y * imageWidth + x) * 3;
          testPixels[idx] = (x * 255 ~/ imageWidth);     // R: horizontal gradient
          testPixels[idx + 1] = (y * 255 ~/ imageHeight); // G: vertical gradient
          testPixels[idx + 2] = 128;                      // B: constant
        }
      }
      
      print('Test image created: ${imageWidth}x${imageHeight}');
    });
    
    Future<ProcessorResult> processCropWithCPU(
      Uint8List pixels,
      int width,
      int height,
      CropRect cropRect,
    ) async {
      final rawData = RawPixelData(
        pixels: pixels,
        width: width,
        height: height,
      );
      
      // Apply crop
      final croppedData = BaseImageProcessor.applyCrop(rawData, cropRect);
      
      // Convert to RGBA for consistency
      final rgbaPixels = Uint8List(croppedData.width * croppedData.height * 4);
      int srcIdx = 0;
      int dstIdx = 0;
      for (int i = 0; i < croppedData.width * croppedData.height; i++) {
        rgbaPixels[dstIdx++] = croppedData.pixels[srcIdx++]; // R
        rgbaPixels[dstIdx++] = croppedData.pixels[srcIdx++]; // G
        rgbaPixels[dstIdx++] = croppedData.pixels[srcIdx++]; // B
        rgbaPixels[dstIdx++] = 255; // A
      }
      
      return ProcessorResult(
        pixels: rgbaPixels,
        width: croppedData.width,
        height: croppedData.height,
      );
    }
    
    Future<ProcessorResult?> processCropWithGPU(
      Uint8List pixels,
      int width,
      int height,
      CropRect cropRect,
    ) async {
      if (!await VulkanProcessor.isAvailable()) {
        return null;
      }
      
      VulkanBindings.initialize();
      
      // Process with GPU
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
      
      if (result == null) return null;
      
      return ProcessorResult(
        pixels: result.pixels,
        width: result.width,
        height: result.height,
      );
    }
    
    void verifyDimensions(ProcessorResult cpu, ProcessorResult gpu, String testName) {
      print('\n$testName:');
      print('  CPU: ${cpu.width}x${cpu.height}');
      print('  GPU: ${gpu.width}x${gpu.height}');
      
      expect(gpu.width, equals(cpu.width), 
        reason: '$testName: Width mismatch - CPU: ${cpu.width}, GPU: ${gpu.width}');
      expect(gpu.height, equals(cpu.height),
        reason: '$testName: Height mismatch - CPU: ${cpu.height}, GPU: ${gpu.height}');
    }
    
    void verifyAspectRatio(ProcessorResult result, double expectedRatio, String testName) {
      final actualRatio = result.width / result.height;
      expect(actualRatio, closeTo(expectedRatio, 0.01),
        reason: '$testName: Aspect ratio mismatch - Expected: $expectedRatio, Actual: $actualRatio');
    }
    
    void verifyPortraitOrientation(ProcessorResult result, String testName) {
      expect(result.height > result.width, isTrue,
        reason: '$testName: Should be portrait (height > width) but got ${result.width}x${result.height}');
    }
    
    void verifyLandscapeOrientation(ProcessorResult result, String testName) {
      expect(result.width > result.height, isTrue,
        reason: '$testName: Should be landscape (width > height) but got ${result.width}x${result.height}');
    }
    
    void verifyPixelContent(ProcessorResult cpu, ProcessorResult gpu, String testName, {int sampleCount = 100}) {
      print('  Verifying pixel content ($sampleCount samples)...');
      
      final random = math.Random(42); // Fixed seed for reproducibility
      int maxDiff = 0;
      int totalDiff = 0;
      int diffCount = 0;
      
      for (int i = 0; i < sampleCount; i++) {
        // Sample random positions
        final x = random.nextInt(math.min(cpu.width, gpu.width));
        final y = random.nextInt(math.min(cpu.height, gpu.height));
        final pixelIdx = (y * cpu.width + x) * 4;
        
        if (pixelIdx + 3 < cpu.pixels.length && pixelIdx + 3 < gpu.pixels.length) {
          final cpuR = cpu.pixels[pixelIdx];
          final cpuG = cpu.pixels[pixelIdx + 1];
          final cpuB = cpu.pixels[pixelIdx + 2];
          
          final gpuR = gpu.pixels[pixelIdx];
          final gpuG = gpu.pixels[pixelIdx + 1];
          final gpuB = gpu.pixels[pixelIdx + 2];
          
          final diffR = (cpuR - gpuR).abs();
          final diffG = (cpuG - gpuG).abs();
          final diffB = (cpuB - gpuB).abs();
          
          final diff = math.max(diffR, math.max(diffG, diffB));
          maxDiff = math.max(maxDiff, diff);
          totalDiff += diff;
          if (diff > 1) diffCount++;
          
          // Fail if difference is too large
          if (diff > 5) {
            fail('$testName: Pixel content mismatch at ($x, $y): '
                 'CPU($cpuR,$cpuG,$cpuB) vs GPU($gpuR,$gpuG,$gpuB), diff=$diff');
          }
        }
      }
      
      print('  Max pixel difference: $maxDiff');
      print('  Average difference: ${totalDiff / sampleCount}');
      print('  Pixels with diff > 1: $diffCount');
    }
    
    test('Portrait crop region on landscape image', () async {
      // Portrait crop region (full height, center 30%)
      final cropRect = CropRect(
        left: 0.35,
        top: 0.0,
        right: 0.65,
        bottom: 1.0,
      );
      
      print('\n=== Testing Portrait Crop (2:3) on Landscape Image ===');
      print('Input: ${imageWidth}x${imageHeight} (landscape)');
      print('Crop: left=${cropRect.left}, top=${cropRect.top}, right=${cropRect.right}, bottom=${cropRect.bottom}');
      
      final cpuResult = await processCropWithCPU(testPixels, imageWidth, imageHeight, cropRect);
      final gpuResult = await processCropWithGPU(testPixels, imageWidth, imageHeight, cropRect);
      
      if (gpuResult == null) {
        print('SKIPPED: GPU not available');
        return;
      }
      
      // Verify dimensions match
      verifyDimensions(cpuResult, gpuResult, 'Portrait crop 2:3');
      
      // Verify portrait orientation
      verifyPortraitOrientation(cpuResult, 'CPU Portrait crop');
      verifyPortraitOrientation(gpuResult, 'GPU Portrait crop');
      
      // Verify aspect ratio (should be 300x600 = 0.5)
      verifyAspectRatio(cpuResult, 0.5, 'CPU Portrait crop');
      verifyAspectRatio(gpuResult, 0.5, 'GPU Portrait crop');
      
      // Verify pixel content
      verifyPixelContent(cpuResult, gpuResult, 'Portrait crop content');
    });
    
    test('Landscape crop (3:2) on landscape image', () async {
      final cropRect = CropRect(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.7,
      );
      
      print('\n=== Testing Landscape Crop (3:2) on Landscape Image ===');
      
      final cpuResult = await processCropWithCPU(testPixels, imageWidth, imageHeight, cropRect);
      final gpuResult = await processCropWithGPU(testPixels, imageWidth, imageHeight, cropRect);
      
      if (gpuResult == null) {
        print('SKIPPED: GPU not available');
        return;
      }
      
      verifyDimensions(cpuResult, gpuResult, 'Landscape crop 3:2');
      verifyLandscapeOrientation(cpuResult, 'CPU Landscape crop');
      verifyLandscapeOrientation(gpuResult, 'GPU Landscape crop');
      verifyPixelContent(cpuResult, gpuResult, 'Landscape crop content');
    });
    
    test('Square crop region on landscape image', () async {
      // For a square crop on 1000x600, we need equal width and height
      // Let's make it 400x400: width=40% (0.3-0.7), height=66.7% (0.1667-0.8333)
      final cropRect = CropRect(
        left: 0.3,
        top: 0.1667,
        right: 0.7,
        bottom: 0.8333,
      );
      
      print('\n=== Testing Square Crop Region on Landscape Image ===');
      
      final cpuResult = await processCropWithCPU(testPixels, imageWidth, imageHeight, cropRect);
      final gpuResult = await processCropWithGPU(testPixels, imageWidth, imageHeight, cropRect);
      
      if (gpuResult == null) {
        print('SKIPPED: GPU not available');
        return;
      }
      
      verifyDimensions(cpuResult, gpuResult, 'Square crop');
      verifyAspectRatio(cpuResult, 1.0, 'CPU Square crop');
      verifyAspectRatio(gpuResult, 1.0, 'GPU Square crop');
      verifyPixelContent(cpuResult, gpuResult, 'Square crop content');
    });
    
    test('Ultra-wide crop (21:9) on landscape image', () async {
      final cropRect = CropRect(
        left: 0.0,
        top: 0.35,
        right: 1.0,
        bottom: 0.65,
      );
      
      print('\n=== Testing Ultra-wide Crop (21:9) on Landscape Image ===');
      
      final cpuResult = await processCropWithCPU(testPixels, imageWidth, imageHeight, cropRect);
      final gpuResult = await processCropWithGPU(testPixels, imageWidth, imageHeight, cropRect);
      
      if (gpuResult == null) {
        print('SKIPPED: GPU not available');
        return;
      }
      
      verifyDimensions(cpuResult, gpuResult, 'Ultra-wide crop');
      verifyLandscapeOrientation(cpuResult, 'CPU Ultra-wide crop');
      verifyLandscapeOrientation(gpuResult, 'GPU Ultra-wide crop');
      verifyPixelContent(cpuResult, gpuResult, 'Ultra-wide crop content');
    });
    
    test('Edge case: Top-left corner crop', () async {
      final cropRect = CropRect(
        left: 0.0,
        top: 0.0,
        right: 0.3,
        bottom: 0.4,
      );
      
      print('\n=== Testing Top-left Corner Crop ===');
      
      final cpuResult = await processCropWithCPU(testPixels, imageWidth, imageHeight, cropRect);
      final gpuResult = await processCropWithGPU(testPixels, imageWidth, imageHeight, cropRect);
      
      if (gpuResult == null) {
        print('SKIPPED: GPU not available');
        return;
      }
      
      verifyDimensions(cpuResult, gpuResult, 'Top-left corner crop');
      verifyPixelContent(cpuResult, gpuResult, 'Top-left corner content');
      
      // Verify that top-left pixel is from original (0,0)
      expect(cpuResult.pixels[0], equals(0), reason: 'CPU: First pixel R should be 0');
      expect(cpuResult.pixels[1], equals(0), reason: 'CPU: First pixel G should be 0');
      expect(gpuResult.pixels[0], equals(0), reason: 'GPU: First pixel R should be 0');
      expect(gpuResult.pixels[1], equals(0), reason: 'GPU: First pixel G should be 0');
    });
    
    test('Edge case: Bottom-right corner crop', () async {
      final cropRect = CropRect(
        left: 0.7,
        top: 0.6,
        right: 1.0,
        bottom: 1.0,
      );
      
      print('\n=== Testing Bottom-right Corner Crop ===');
      
      final cpuResult = await processCropWithCPU(testPixels, imageWidth, imageHeight, cropRect);
      final gpuResult = await processCropWithGPU(testPixels, imageWidth, imageHeight, cropRect);
      
      if (gpuResult == null) {
        print('SKIPPED: GPU not available');
        return;
      }
      
      verifyDimensions(cpuResult, gpuResult, 'Bottom-right corner crop');
      verifyPixelContent(cpuResult, gpuResult, 'Bottom-right corner content');
    });
    
    test('Story/Instagram portrait (9:16) on landscape image', () async {
      // Very tall portrait crop
      final cropRect = CropRect(
        left: 0.4,
        top: 0.0,
        right: 0.6,
        bottom: 1.0,
      );
      
      print('\n=== Testing Story Portrait Crop (9:16) on Landscape Image ===');
      
      final cpuResult = await processCropWithCPU(testPixels, imageWidth, imageHeight, cropRect);
      final gpuResult = await processCropWithGPU(testPixels, imageWidth, imageHeight, cropRect);
      
      if (gpuResult == null) {
        print('SKIPPED: GPU not available');
        return;
      }
      
      verifyDimensions(cpuResult, gpuResult, 'Story portrait crop');
      verifyPortraitOrientation(cpuResult, 'CPU Story portrait');
      verifyPortraitOrientation(gpuResult, 'GPU Story portrait');
      verifyPixelContent(cpuResult, gpuResult, 'Story portrait content');
    });
  });
}

class ProcessorResult {
  final Uint8List pixels;
  final int width;
  final int height;
  
  ProcessorResult({
    required this.pixels,
    required this.width,
    required this.height,
  });
}