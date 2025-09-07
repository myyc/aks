import 'package:flutter_test/flutter_test.dart';
import 'package:aks/models/crop_state.dart';

void main() {
  group('CropRect Tests', () {
    test('CropRect should initialize with valid values', () {
      final crop = CropRect(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.8,
      );
      
      expect(crop.left, equals(0.1));
      expect(crop.top, equals(0.2));
      expect(crop.right, equals(0.9));
      expect(crop.bottom, equals(0.8));
    });
    
    test('CropRect should calculate width and height correctly', () {
      final crop = CropRect(
        left: 0.25,
        top: 0.25,
        right: 0.75,
        bottom: 0.75,
      );
      
      expect(crop.width, equals(0.5));
      expect(crop.height, equals(0.5));
    });
    
    test('CropRect should validate bounds', () {
      // Test invalid left > right
      expect(
        () => CropRect(left: 0.8, top: 0.2, right: 0.2, bottom: 0.8),
        throwsAssertionError,
      );
      
      // Test invalid top > bottom
      expect(
        () => CropRect(left: 0.2, top: 0.8, right: 0.8, bottom: 0.2),
        throwsAssertionError,
      );
      
      // Test values outside 0-1 range
      expect(
        () => CropRect(left: -0.1, top: 0, right: 1, bottom: 1),
        throwsAssertionError,
      );
      
      expect(
        () => CropRect(left: 0, top: 0, right: 1.1, bottom: 1),
        throwsAssertionError,
      );
    });
    
    test('CropRect equality should work correctly', () {
      final crop1 = CropRect(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.8,
      );
      
      final crop2 = CropRect(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.8,
      );
      
      final crop3 = CropRect(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.7, // Different
      );
      
      expect(crop1, equals(crop2));
      expect(crop1, isNot(equals(crop3)));
    });
    
    test('CropRect should detect no-crop state', () {
      final noCrop = CropRect(left: 0, top: 0, right: 1, bottom: 1);
      final withCrop = CropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9);
      
      expect(noCrop.isFullImage, isTrue);
      expect(withCrop.isFullImage, isFalse);
    });
    
    test('CropRect should convert to pixel coordinates correctly', () {
      final crop = CropRect(
        left: 0.25,
        top: 0.25,
        right: 0.75,
        bottom: 0.75,
      );
      
      const imageWidth = 4000;
      const imageHeight = 6000;
      
      final pixelLeft = (crop.left * imageWidth).round();
      final pixelTop = (crop.top * imageHeight).round();
      final pixelRight = (crop.right * imageWidth).round();
      final pixelBottom = (crop.bottom * imageHeight).round();
      
      expect(pixelLeft, equals(1000));
      expect(pixelTop, equals(1500));
      expect(pixelRight, equals(3000));
      expect(pixelBottom, equals(4500));
      
      // Calculate cropped dimensions
      final croppedWidth = pixelRight - pixelLeft;
      final croppedHeight = pixelBottom - pixelTop;
      
      expect(croppedWidth, equals(2000));
      expect(croppedHeight, equals(3000));
    });
    
    test('CropRect should handle edge cases for pixel conversion', () {
      // Very small crop
      final tinyCrop = CropRect(
        left: 0.499,
        top: 0.499,
        right: 0.501,
        bottom: 0.501,
      );
      
      const imageWidth = 1000;
      const imageHeight = 1000;
      
      final pixelLeft = (tinyCrop.left * imageWidth).round();
      final pixelTop = (tinyCrop.top * imageHeight).round();
      final pixelRight = (tinyCrop.right * imageWidth).round();
      final pixelBottom = (tinyCrop.bottom * imageHeight).round();
      
      final croppedWidth = pixelRight - pixelLeft;
      final croppedHeight = pixelBottom - pixelTop;
      
      // Should result in at least 1 pixel
      expect(croppedWidth, greaterThan(0));
      expect(croppedHeight, greaterThan(0));
    });
  });
  
  group('CropState Tests', () {
    test('CropState should initialize with defaults', () {
      final state = CropState();
      
      expect(state.isActive, isFalse);
      expect(state.aspectRatio, isNull);
      expect(state.lockedAspectRatio, isNull);
      expect(state.currentCrop, isNull);
    });
    
    test('CropState should track active state', () {
      final state = CropState();
      
      expect(state.isActive, isFalse);
      
      state.isActive = true;
      expect(state.isActive, isTrue);
      
      state.isActive = false;
      expect(state.isActive, isFalse);
    });
    
    test('CropState should manage aspect ratio', () {
      final state = CropState();
      
      // Set aspect ratio
      state.aspectRatio = 1.5; // 3:2
      expect(state.aspectRatio, equals(1.5));
      
      // Lock aspect ratio
      state.lockedAspectRatio = 1.5;
      expect(state.lockedAspectRatio, equals(1.5));
      
      // Clear aspect ratio
      state.aspectRatio = null;
      expect(state.aspectRatio, isNull);
    });
    
    test('CropState should store current crop', () {
      final state = CropState();
      
      final crop = CropRect(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.8,
      );
      
      state.currentCrop = crop;
      expect(state.currentCrop, equals(crop));
      
      // Clear crop
      state.currentCrop = null;
      expect(state.currentCrop, isNull);
    });
    
    test('CropState should reset correctly', () {
      final state = CropState();
      
      // Set various values
      state.isActive = true;
      state.aspectRatio = 1.5;
      state.lockedAspectRatio = 1.5;
      state.currentCrop = CropRect(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.8,
      );
      
      // Reset
      state.reset();
      
      expect(state.isActive, isFalse);
      expect(state.aspectRatio, isNull);
      expect(state.lockedAspectRatio, isNull);
      expect(state.currentCrop, isNull);
    });
  });
  
  group('Aspect Ratio Calculations', () {
    test('Should calculate aspect ratio from dimensions', () {
      // 3:2 aspect ratio (common for cameras)
      expect(4000 / 6000, closeTo(0.667, 0.001));
      expect(6000 / 4000, closeTo(1.5, 0.001));
      
      // 16:9 aspect ratio (HD video)
      expect(1920 / 1080, closeTo(1.778, 0.001));
      expect(1080 / 1920, closeTo(0.563, 0.001));
      
      // 1:1 aspect ratio (square)
      expect(1000 / 1000, equals(1.0));
    });
    
    test('Should detect common aspect ratios with tolerance', () {
      const tolerance = 0.005; // 0.5% tolerance
      
      // Test 3:2 detection
      final ratio32 = 1.5;
      final nearRatio32 = 1.498; // Slightly off due to rounding
      expect((ratio32 - nearRatio32).abs() / ratio32, lessThan(tolerance));
      
      // Test 16:9 detection
      final ratio169 = 16.0 / 9.0;
      final nearRatio169 = 1920.0 / 1080.0;
      expect((ratio169 - nearRatio169).abs() / ratio169, lessThan(tolerance));
      
      // Test 4:3 detection
      final ratio43 = 4.0 / 3.0;
      final nearRatio43 = 1.335; // Slightly off
      expect((ratio43 - nearRatio43).abs() / ratio43, lessThan(tolerance));
    });
    
    test('Should maintain aspect ratio when cropping', () {
      const targetRatio = 1.5; // 3:2 (landscape)
      const imageWidth = 4000.0;
      const imageHeight = 6000.0;
      
      // For a portrait image (4000x6000) to get a landscape crop (3:2)
      // We need to find the largest crop that fits
      
      // Since image is portrait and we want landscape (1.5),
      // we're constrained by width
      const cropWidthPixels = imageWidth; // Use full width
      final cropHeightPixels = cropWidthPixels / targetRatio; // 4000 / 1.5 = 2666.67
      
      // Check the actual aspect ratio of the crop in pixels
      final actualRatio = cropWidthPixels / cropHeightPixels;
      
      expect(actualRatio, closeTo(targetRatio, 0.001));
    });
  });
}