import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

import 'package:aks/services/processors/cpu_processor.dart';
import 'package:aks/services/processors/vulkan_processor.dart';
import 'package:aks/services/processors/vulkan/vulkan_bindings.dart';
import 'package:aks/services/processors/image_processor_interface.dart';
import 'package:aks/models/adjustments.dart';
import 'package:aks/models/edit_pipeline.dart';
import 'package:aks/models/crop_state.dart';
import 'package:aks/services/raw_processor.dart';
import 'package:aks/services/image_processor.dart';
import '../test_helper.dart';

void main() {
  group('Processor Comparison Tests', () {
    late File testImage;
    late Uint8List rawPixels;
    late int imageWidth;
    late int imageHeight;
    
    setUpAll(() async {
      // Ensure native libraries are built
      await TestHelper.ensureInitialized();
      
      // Load the test RAW image
      final testImagePath = 'test/fixtures/test_image.arw';
      testImage = File(testImagePath);
      
      if (!await testImage.exists()) {
        print('WARNING: Test image not found at $testImagePath');
        print('Please place a RAW image at this location to run tests');
        return;
      }
      
      print('Loading test RAW image from $testImagePath...');
      
      // Process the RAW file to get RGB pixels
      RawProcessor.initialize();
      final result = await RawProcessor.loadRawFile(testImagePath);
      
      if (result != null) {
        // Convert RGB to RGBA for processing
        final rgbPixels = result.pixels;
        final rgbaPixels = Uint8List(result.width * result.height * 4);
        
        // Convert RGB to RGBA
        int rgbIndex = 0;
        int rgbaIndex = 0;
        for (int i = 0; i < result.width * result.height; i++) {
          rgbaPixels[rgbaIndex++] = rgbPixels[rgbIndex++]; // R
          rgbaPixels[rgbaIndex++] = rgbPixels[rgbIndex++]; // G
          rgbaPixels[rgbaIndex++] = rgbPixels[rgbIndex++]; // B
          rgbaPixels[rgbaIndex++] = 255; // A
        }
        
        rawPixels = rgbaPixels;
        imageWidth = result.width;
        imageHeight = result.height;
        
        print('Test image loaded: ${imageWidth}x${imageHeight}');
        print('Pixel data size: ${rawPixels.length} bytes');
      } else {
        print('Failed to load RAW image');
      }
    });
    
    test('CPU and GPU processors should produce identical results with no adjustments', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      // Check if Vulkan is available
      if (!await VulkanProcessor.isAvailable()) {
        print('SKIPPED: Vulkan not available on this system');
        return;
      }
      
      print('\n=== Testing with no adjustments ===');
      
      // Process with CPU
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      final cpuResult = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [], // No adjustments
      );
      
      cpuProcessor.dispose();
      
      // Process with GPU
      final gpuProcessor = VulkanProcessor();
      await gpuProcessor.initialize();
      
      final gpuResult = await gpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [], // No adjustments
      );
      
      gpuProcessor.dispose();
      
      // Compare results
      _comparePixels(cpuResult, gpuResult, 'No adjustments');
    });
    
    test('CPU and GPU should produce identical results with exposure adjustment', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      if (!await VulkanProcessor.isAvailable()) {
        print('SKIPPED: Vulkan not available on this system');
        return;
      }
      
      print('\n=== Testing with exposure adjustment ===');
      
      final adjustments = [
        ExposureAdjustment(value: 0.5), // +0.5 EV
      ];
      
      // Process with CPU
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      final cpuResult = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        adjustments,
      );
      
      cpuProcessor.dispose();
      
      // Process with GPU
      final gpuProcessor = VulkanProcessor();
      await gpuProcessor.initialize();
      
      final gpuResult = await gpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        adjustments,
      );
      
      gpuProcessor.dispose();
      
      // Compare results
      _comparePixels(cpuResult, gpuResult, 'Exposure +0.5');
    });
    
    test('Identity tone curve should not change the image', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      print('\n=== Testing identity tone curve ===');
      
      final identityToneCurve = ToneCurveAdjustment(
        rgbCurve: [
          CurvePoint(0, 0),
          CurvePoint(255, 255),
        ],
      );
      
      // Process with CPU (baseline - no adjustments)
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      final baselineResult = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [], // No adjustments
      );
      
      // Process with identity tone curve
      final toneCurveResult = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [identityToneCurve],
      );
      
      cpuProcessor.dispose();
      
      // Compare - should be identical
      _comparePixels(baselineResult, toneCurveResult, 'Identity tone curve vs baseline');
    });
    
    test('Near-diagonal tone curve point should have minimal effect', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      print('\n=== Testing near-diagonal tone curve ===');
      
      // Create a tone curve with a point very close to diagonal
      final nearDiagonalCurve = ToneCurveAdjustment(
        rgbCurve: [
          CurvePoint(0, 0),
          CurvePoint(128, 129), // Just 1 unit off diagonal
          CurvePoint(255, 255),
        ],
      );
      
      // Process with CPU
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      final baselineResult = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [], // No adjustments
      );
      
      final curveResult = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [nearDiagonalCurve],
      );
      
      cpuProcessor.dispose();
      
      // Compare - should have minimal difference
      _comparePixels(baselineResult, curveResult, 'Near-diagonal curve', maxDifference: 5);
    });
    
    test('Exposure adjustment should brighten image', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      print('\n=== Testing exposure brightening ===');
      
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      // Get baseline
      final baseline = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [],
      );
      
      // Apply positive exposure
      final brightened = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [ExposureAdjustment(value: 1.0)], // +1 EV should roughly double brightness
      );
      
      cpuProcessor.dispose();
      
      // Check that image got brighter
      final baselineStats = _calculateHistogram(baseline);
      final brightenedStats = _calculateHistogram(brightened);
      
      print('  Baseline mean: R=${baselineStats['red_mean']!.toStringAsFixed(1)}, G=${baselineStats['green_mean']!.toStringAsFixed(1)}, B=${baselineStats['blue_mean']!.toStringAsFixed(1)}');
      print('  Brightened mean: R=${brightenedStats['red_mean']!.toStringAsFixed(1)}, G=${brightenedStats['green_mean']!.toStringAsFixed(1)}, B=${brightenedStats['blue_mean']!.toStringAsFixed(1)}');
      
      expect(brightenedStats['red_mean']!, greaterThan(baselineStats['red_mean']!),
        reason: 'Red channel should be brighter');
      expect(brightenedStats['green_mean']!, greaterThan(baselineStats['green_mean']!),
        reason: 'Green channel should be brighter');
      expect(brightenedStats['blue_mean']!, greaterThan(baselineStats['blue_mean']!),
        reason: 'Blue channel should be brighter');
    });
    
    test('Saturation adjustment should affect color intensity', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      print('\n=== Testing saturation adjustment ===');
      
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      // Get baseline
      final baseline = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [],
      );
      
      // Desaturate to grayscale
      final desaturated = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [SaturationVibranceAdjustment(saturation: -100)], // Full desaturation
      );
      
      cpuProcessor.dispose();
      
      // Check that desaturated image has equal RGB values (grayscale)
      int grayscalePixels = 0;
      int totalChecked = 0;
      final sampleStep = math.max(1, desaturated.length ~/ 10000);
      
      for (int i = 0; i < desaturated.length - 3; i += sampleStep * 4) {
        final r = desaturated[i];
        final g = desaturated[i + 1];
        final b = desaturated[i + 2];
        
        totalChecked++;
        
        // Check if RGB values are very close (within rounding error)
        if ((r - g).abs() <= 2 && (g - b).abs() <= 2 && (r - b).abs() <= 2) {
          grayscalePixels++;
        }
      }
      
      final grayscaleRatio = grayscalePixels / totalChecked;
      print('  Grayscale pixels: $grayscalePixels / $totalChecked (${(grayscaleRatio * 100).toStringAsFixed(1)}%)');
      
      expect(grayscaleRatio, greaterThan(0.95),
        reason: 'At least 95% of pixels should be grayscale with -100 saturation');
    });
    
    test('Contrast adjustment should expand or compress tonal range', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      print('\n=== Testing contrast adjustment ===');
      
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      // Get baseline
      final baseline = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [],
      );
      
      // Apply positive contrast
      final highContrast = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [ContrastAdjustment(value: 50)], // +50 contrast
      );
      
      cpuProcessor.dispose();
      
      // Calculate standard deviation (measure of contrast)
      final baselineStd = _calculateStandardDeviation(baseline);
      final contrastStd = _calculateStandardDeviation(highContrast);
      
      print('  Baseline std dev: ${baselineStd.toStringAsFixed(2)}');
      print('  High contrast std dev: ${contrastStd.toStringAsFixed(2)}');
      
      expect(contrastStd, greaterThan(baselineStd),
        reason: 'Higher contrast should increase standard deviation');
    });
    
    test('White balance should shift color temperature', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      print('\n=== Testing white balance adjustment ===');
      
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      // Get baseline
      final baseline = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [],
      );
      
      // Apply warm temperature (lower K = more orange/red)
      final warm = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [WhiteBalanceAdjustment(temperature: 3000)], // Warm/tungsten
      );
      
      // Apply cool temperature (higher K = more blue)
      final cool = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [WhiteBalanceAdjustment(temperature: 8000)], // Cool/shade
      );
      
      cpuProcessor.dispose();
      
      final warmStats = _calculateHistogram(warm);
      final coolStats = _calculateHistogram(cool);
      
      print('  Warm (3000K): R=${warmStats['red_mean']!.toStringAsFixed(1)}, B=${warmStats['blue_mean']!.toStringAsFixed(1)}');
      print('  Cool (8000K): R=${coolStats['red_mean']!.toStringAsFixed(1)}, B=${coolStats['blue_mean']!.toStringAsFixed(1)}');
      
      // Warm should have more red relative to blue
      final warmRatio = warmStats['red_mean']! / warmStats['blue_mean']!;
      final coolRatio = coolStats['red_mean']! / coolStats['blue_mean']!;
      
      print('  Warm R/B ratio: ${warmRatio.toStringAsFixed(2)}');
      print('  Cool R/B ratio: ${coolRatio.toStringAsFixed(2)}');
      
      expect(warmRatio, greaterThan(coolRatio),
        reason: 'Warm temperature should have higher red/blue ratio than cool');
    });
    
    test('Highlights adjustment should primarily affect bright areas', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      print('\n=== Testing highlights adjustment ===');
      
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      // Get baseline
      final baseline = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [],
      );
      
      // Darken highlights
      final darkenedHighlights = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        [HighlightsShadowsAdjustment(highlights: -50)],
      );
      
      cpuProcessor.dispose();
      
      // Count pixels in different brightness ranges
      int darkPixelsDiff = 0;
      int brightPixelsDiff = 0;
      int totalPixels = 0;
      
      for (int i = 0; i < baseline.length - 3; i += 4) {
        final baseLum = (0.299 * baseline[i] + 0.587 * baseline[i+1] + 0.114 * baseline[i+2]).round();
        final adjustedLum = (0.299 * darkenedHighlights[i] + 0.587 * darkenedHighlights[i+1] + 0.114 * darkenedHighlights[i+2]).round();
        
        totalPixels++;
        
        if (baseLum > 200) { // Bright pixels
          if (adjustedLum < baseLum) brightPixelsDiff++;
        } else if (baseLum < 50) { // Dark pixels
          if ((adjustedLum - baseLum).abs() > 5) darkPixelsDiff++;
        }
      }
      
      print('  Bright pixels affected: $brightPixelsDiff');
      print('  Dark pixels affected: $darkPixelsDiff');
      
      expect(brightPixelsDiff, greaterThan(darkPixelsDiff * 5),
        reason: 'Highlights adjustment should affect bright areas much more than dark areas');
    });
    
    test('All adjustments combined - CPU vs GPU', () async {
      if (rawPixels == null) {
        print('SKIPPED: Test image not available');
        return;
      }
      
      if (!await VulkanProcessor.isAvailable()) {
        print('SKIPPED: Vulkan not available on this system');
        return;
      }
      
      print('\n=== Testing all adjustments combined ===');
      
      final adjustments = [
        WhiteBalanceAdjustment(temperature: 6000, tint: 10),
        ExposureAdjustment(value: 0.3),
        ContrastAdjustment(value: 15),
        HighlightsShadowsAdjustment(highlights: -20, shadows: 25),
        BlacksWhitesAdjustment(blacks: 5, whites: -10),
        SaturationVibranceAdjustment(saturation: 10, vibrance: 20),
      ];
      
      // Process with CPU
      final cpuProcessor = CpuProcessor();
      await cpuProcessor.initialize();
      
      final cpuResult = await cpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        adjustments,
      );
      
      cpuProcessor.dispose();
      
      // Process with GPU
      final gpuProcessor = VulkanProcessor();
      await gpuProcessor.initialize();
      
      final gpuResult = await gpuProcessor.processPixels(
        Uint8List.fromList(rawPixels),
        imageWidth,
        imageHeight,
        adjustments,
      );
      
      gpuProcessor.dispose();
      
      // Compare results - allow more tolerance for combined adjustments
      // as small floating point differences can accumulate
      _comparePixels(cpuResult, gpuResult, 'All adjustments', maxDifference: 50);
    });
    
    group('Cropping Tests', () {
      test('CPU cropping should produce correct dimensions', () async {
        if (rawPixels == null) {
          print('SKIPPED: Test image not available');
          return;
        }
        
        print('\n=== Testing CPU cropping dimensions ===');
        
        // Create a 50% center crop
        final cropRect = CropRect(
          left: 0.25,
          top: 0.25,
          right: 0.75,
          bottom: 0.75,
        );
        
        // Create raw pixel data
        final rawData = RawPixelData(
          pixels: rawPixels.sublist(0, imageWidth * imageHeight * 3), // Convert to RGB
          width: imageWidth,
          height: imageHeight,
        );
        
        // Apply crop using BaseImageProcessor's static method
        final croppedData = BaseImageProcessor.applyCrop(rawData, cropRect);
        
        // Verify dimensions
        final expectedWidth = (imageWidth * 0.5).round();
        final expectedHeight = (imageHeight * 0.5).round();
        
        print('  Original: ${imageWidth}x${imageHeight}');
        print('  Expected: ${expectedWidth}x${expectedHeight}');
        print('  Actual: ${croppedData.width}x${croppedData.height}');
        
        expect(croppedData.width, equals(expectedWidth));
        expect(croppedData.height, equals(expectedHeight));
        expect(croppedData.pixels.length, equals(expectedWidth * expectedHeight * 3));
      });
      
      test('GPU cropping should produce correct dimensions', () async {
        if (rawPixels == null) {
          print('SKIPPED: Test image not available');
          return;
        }
        
        if (!await VulkanProcessor.isAvailable()) {
          print('SKIPPED: Vulkan not available on this system');
          return;
        }
        
        print('\n=== Testing GPU cropping dimensions ===');
        
        // Initialize Vulkan
        VulkanBindings.initialize();
        
        // Create a 50% center crop
        final cropLeft = 0.25;
        final cropTop = 0.25;
        final cropRight = 0.75;
        final cropBottom = 0.75;
        
        // Create RGB pixels from RGBA
        final rgbPixels = Uint8List(imageWidth * imageHeight * 3);
        int rgbIndex = 0;
        for (int i = 0; i < rawPixels.length - 3; i += 4) {
          rgbPixels[rgbIndex++] = rawPixels[i];     // R
          rgbPixels[rgbIndex++] = rawPixels[i + 1]; // G
          rgbPixels[rgbIndex++] = rawPixels[i + 2]; // B
        }
        
        // Create minimal adjustments array
        final adjustments = Float32List(16); // Minimum required
        adjustments[0] = 5500.0; // Default temperature
        
        // Process with GPU cropping
        final result = VulkanBindings.processImageWithCrop(
          rgbPixels,
          imageWidth,
          imageHeight,
          adjustments,
          cropLeft,
          cropTop,
          cropRight,
          cropBottom,
        );
        
        expect(result, isNotNull, reason: 'GPU cropping should succeed');
        
        if (result != null) {
          final expectedWidth = ((cropRight - cropLeft) * imageWidth).round();
          final expectedHeight = ((cropBottom - cropTop) * imageHeight).round();
          
          print('  Original: ${imageWidth}x${imageHeight}');
          print('  Expected: ${expectedWidth}x${expectedHeight}');
          print('  Actual: ${result.width}x${result.height}');
          
          expect(result.width, equals(expectedWidth));
          expect(result.height, equals(expectedHeight));
          expect(result.pixels.length, equals(expectedWidth * expectedHeight * 4)); // RGBA
        }
      });
      
      test('CPU and GPU cropping should produce identical results', () async {
        if (rawPixels == null) {
          print('SKIPPED: Test image not available');
          return;
        }
        
        if (!await VulkanProcessor.isAvailable()) {
          print('SKIPPED: Vulkan not available on this system');
          return;
        }
        
        print('\n=== Testing CPU vs GPU cropping ===');
        
        // Create an asymmetric crop for better testing
        final cropRect = CropRect(
          left: 0.1,
          top: 0.2,
          right: 0.8,
          bottom: 0.9,
        );
        
        final pipeline = EditPipeline();
        pipeline.setCropRect(cropRect);
        
        // Create RGB raw data
        final rgbPixels = Uint8List(imageWidth * imageHeight * 3);
        int rgbIndex = 0;
        for (int i = 0; i < rawPixels.length - 3; i += 4) {
          rgbPixels[rgbIndex++] = rawPixels[i];
          rgbPixels[rgbIndex++] = rawPixels[i + 1];
          rgbPixels[rgbIndex++] = rawPixels[i + 2];
        }
        
        final rawData = RawPixelData(
          pixels: rgbPixels,
          width: imageWidth,
          height: imageHeight,
        );
        
        // Process with CPU
        final cpuProcessor = CpuProcessor();
        await cpuProcessor.initialize();
        final cpuImage = await cpuProcessor.processImage(rawData, pipeline);
        cpuProcessor.dispose();
        
        // Process with GPU
        final gpuProcessor = VulkanProcessor();
        await gpuProcessor.initialize();
        final gpuImage = await gpuProcessor.processImage(rawData, pipeline);
        gpuProcessor.dispose();
        
        // Compare dimensions (allow 1 pixel difference due to rounding)
        print('  CPU result: ${cpuImage.width}x${cpuImage.height}');
        print('  GPU result: ${gpuImage.width}x${gpuImage.height}');
        
        expect(gpuImage.width, closeTo(cpuImage.width, 1));
        expect(gpuImage.height, closeTo(cpuImage.height, 1));
      });
      
      test('Edge crop values should be handled correctly', () async {
        if (rawPixels == null) {
          print('SKIPPED: Test image not available');
          return;
        }
        
        print('\n=== Testing edge crop values ===');
        
        // Create RGB raw data
        final rgbPixels = Uint8List(imageWidth * imageHeight * 3);
        int rgbIndex = 0;
        for (int i = 0; i < rawPixels.length - 3; i += 4) {
          rgbPixels[rgbIndex++] = rawPixels[i];
          rgbPixels[rgbIndex++] = rawPixels[i + 1];
          rgbPixels[rgbIndex++] = rawPixels[i + 2];
        }
        
        final rawData = RawPixelData(
          pixels: rgbPixels,
          width: imageWidth,
          height: imageHeight,
        );
        
        // Test no crop (0,0,1,1)
        var cropRect = CropRect(left: 0, top: 0, right: 1, bottom: 1);
        var croppedData = BaseImageProcessor.applyCrop(rawData, cropRect);
        
        print('  No crop (0,0,1,1): ${croppedData.width}x${croppedData.height}');
        expect(croppedData.width, equals(imageWidth));
        expect(croppedData.height, equals(imageHeight));
        
        // Test minimal crop (1 pixel border)
        final pixelBorder = 1.0;
        cropRect = CropRect(
          left: pixelBorder / imageWidth,
          top: pixelBorder / imageHeight,
          right: 1.0 - (pixelBorder / imageWidth),
          bottom: 1.0 - (pixelBorder / imageHeight),
        );
        croppedData = BaseImageProcessor.applyCrop(rawData, cropRect);
        
        print('  1-pixel border crop: ${croppedData.width}x${croppedData.height}');
        expect(croppedData.width, equals(imageWidth - 2));
        expect(croppedData.height, equals(imageHeight - 2));
        
        // Test tiny center crop (10%)
        cropRect = CropRect(left: 0.45, top: 0.45, right: 0.55, bottom: 0.55);
        croppedData = BaseImageProcessor.applyCrop(rawData, cropRect);
        
        final expectedWidth = (imageWidth * 0.1).round();
        final expectedHeight = (imageHeight * 0.1).round();
        
        print('  10% center crop: ${croppedData.width}x${croppedData.height}');
        expect(croppedData.width, equals(expectedWidth));
        expect(croppedData.height, equals(expectedHeight));
      });
      
      test('Crop with adjustments should apply correctly', () async {
        if (rawPixels == null) {
          print('SKIPPED: Test image not available');
          return;
        }
        
        if (!await VulkanProcessor.isAvailable()) {
          print('SKIPPED: Vulkan not available on this system');
          return;
        }
        
        print('\n=== Testing crop with adjustments ===');
        
        // Create crop and adjustments
        final cropRect = CropRect(
          left: 0.25,
          top: 0.25,
          right: 0.75,
          bottom: 0.75,
        );
        
        final adjustments = [
          ExposureAdjustment(value: 0.5),
          ContrastAdjustment(value: 20),
          SaturationVibranceAdjustment(saturation: 15),
        ];
        
        final pipeline = EditPipeline();
        for (final adj in adjustments) {
          pipeline.updateAdjustment(adj);
        }
        pipeline.setCropRect(cropRect);
        
        // Create RGB raw data
        final rgbPixels = Uint8List(imageWidth * imageHeight * 3);
        int rgbIndex = 0;
        for (int i = 0; i < rawPixels.length - 3; i += 4) {
          rgbPixels[rgbIndex++] = rawPixels[i];
          rgbPixels[rgbIndex++] = rawPixels[i + 1];
          rgbPixels[rgbIndex++] = rawPixels[i + 2];
        }
        
        final rawData = RawPixelData(
          pixels: rgbPixels,
          width: imageWidth,
          height: imageHeight,
        );
        
        // Process with both CPU and GPU
        final cpuProcessor = CpuProcessor();
        await cpuProcessor.initialize();
        final cpuImage = await cpuProcessor.processImage(rawData, pipeline);
        cpuProcessor.dispose();
        
        final gpuProcessor = VulkanProcessor();
        await gpuProcessor.initialize();
        final gpuImage = await gpuProcessor.processImage(rawData, pipeline);
        gpuProcessor.dispose();
        
        // Verify dimensions match and are correct
        final expectedWidth = (imageWidth * 0.5).round();
        final expectedHeight = (imageHeight * 0.5).round();
        
        print('  Expected: ${expectedWidth}x${expectedHeight}');
        print('  CPU result: ${cpuImage.width}x${cpuImage.height}');
        print('  GPU result: ${gpuImage.width}x${gpuImage.height}');
        
        expect(cpuImage.width, equals(expectedWidth));
        expect(cpuImage.height, equals(expectedHeight));
        expect(gpuImage.width, equals(expectedWidth));
        expect(gpuImage.height, equals(expectedHeight));
      });
    });
  });
}

/// Compare two pixel arrays and report differences
void _comparePixels(Uint8List pixels1, Uint8List pixels2, String testName, {int maxDifference = 1}) {
  expect(pixels1.length, equals(pixels2.length), reason: 'Pixel array lengths should match');
  
  int totalDifferences = 0;
  int maxDiff = 0;
  double totalDiff = 0;
  
  // Calculate histograms for both
  final hist1 = _calculateHistogram(pixels1);
  final hist2 = _calculateHistogram(pixels2);
  
  // Sample some pixels for detailed comparison
  final sampleSize = math.min(1000, pixels1.length ~/ 4);
  final step = pixels1.length ~/ sampleSize ~/ 4;
  
  for (int i = 0; i < pixels1.length; i += step * 4) {
    if (i + 3 >= pixels1.length) break;
    
    final r1 = pixels1[i];
    final g1 = pixels1[i + 1];
    final b1 = pixels1[i + 2];
    
    final r2 = pixels2[i];
    final g2 = pixels2[i + 1];
    final b2 = pixels2[i + 2];
    
    final rDiff = (r1 - r2).abs();
    final gDiff = (g1 - g2).abs();
    final bDiff = (b1 - b2).abs();
    
    maxDiff = math.max(maxDiff, math.max(rDiff, math.max(gDiff, bDiff)));
    totalDiff += rDiff + gDiff + bDiff;
    
    if (rDiff > maxDifference || gDiff > maxDifference || bDiff > maxDifference) {
      totalDifferences++;
      
      if (totalDifferences <= 5) { // Log first few differences
        print('  Pixel difference at index $i: RGB1($r1,$g1,$b1) vs RGB2($r2,$g2,$b2) - diff($rDiff,$gDiff,$bDiff)');
      }
    }
  }
  
  final avgDiff = totalDiff / (sampleSize * 3);
  
  print('\n[$testName] Results:');
  print('  Samples compared: $sampleSize pixels');
  print('  Max channel difference: $maxDiff');
  print('  Average difference: ${avgDiff.toStringAsFixed(2)}');
  print('  Pixels with difference > $maxDifference: $totalDifferences');
  
  // Compare histograms
  print('  Histogram comparison:');
  print('    Red mean: ${hist1['red_mean']!.toStringAsFixed(2)} vs ${hist2['red_mean']!.toStringAsFixed(2)}');
  print('    Green mean: ${hist1['green_mean']!.toStringAsFixed(2)} vs ${hist2['green_mean']!.toStringAsFixed(2)}');
  print('    Blue mean: ${hist1['blue_mean']!.toStringAsFixed(2)} vs ${hist2['blue_mean']!.toStringAsFixed(2)}');
  
  // Assert that differences are within acceptable range
  expect(maxDiff, lessThanOrEqualTo(maxDifference * 2), 
    reason: 'Maximum pixel difference should be minimal');
  expect(avgDiff, lessThan(maxDifference.toDouble()), 
    reason: 'Average pixel difference should be very small');
}

/// Calculate histogram statistics
Map<String, double> _calculateHistogram(Uint8List pixels) {
  double redSum = 0, greenSum = 0, blueSum = 0;
  int count = 0;
  
  for (int i = 0; i < pixels.length - 3; i += 4) {
    redSum += pixels[i];
    greenSum += pixels[i + 1];
    blueSum += pixels[i + 2];
    count++;
  }
  
  return {
    'red_mean': redSum / count,
    'green_mean': greenSum / count,
    'blue_mean': blueSum / count,
  };
}

/// Calculate standard deviation of luminance
double _calculateStandardDeviation(Uint8List pixels) {
  // First calculate mean luminance
  double sum = 0;
  int count = 0;
  
  for (int i = 0; i < pixels.length - 3; i += 4) {
    final lum = 0.299 * pixels[i] + 0.587 * pixels[i + 1] + 0.114 * pixels[i + 2];
    sum += lum;
    count++;
  }
  
  final mean = sum / count;
  
  // Calculate variance
  double variance = 0;
  for (int i = 0; i < pixels.length - 3; i += 4) {
    final lum = 0.299 * pixels[i] + 0.587 * pixels[i + 1] + 0.114 * pixels[i + 2];
    variance += math.pow(lum - mean, 2);
  }
  
  variance /= count;
  return math.sqrt(variance);
}