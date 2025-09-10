import 'dart:io';
import 'package:flutter/foundation.dart' show TargetPlatform;

/// Test helper to ensure native libraries are built before running tests
class TestHelper {
  static bool _initialized = false;
  
  /// Ensure test environment is set up for the current platform
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    
    print('Checking test environment for ${currentPlatform}...');
    
    // Only build Linux libraries on Linux
    if (currentPlatform == 'linux') {
      await _ensureLinuxLibraries();
    } else {
      print('Skipping native library build on $currentPlatform');
    }
    
    _initialized = true;
  }
  
  /// Get current platform string
  static String get currentPlatform {
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }
  
  /// Ensure Linux native libraries are built and available
  static Future<void> _ensureLinuxLibraries() async {
    // Check if libraries exist
    final librawPath = 'linux/libraw_processor.so';
    final vulkanPath = 'linux/libvulkan_processor.so';
    final shaderPath = 'linux/vulkan_processor/shaders/image_process.spv';
    
    bool needsBuild = false;
    
    if (!File(librawPath).existsSync()) {
      print('  libraw_processor.so not found');
      needsBuild = true;
    }
    
    if (!File(vulkanPath).existsSync()) {
      print('  libvulkan_processor.so not found');
      needsBuild = true;
    }
    
    if (!File(shaderPath).existsSync()) {
      print('  Vulkan shaders not compiled');
      needsBuild = true;
    }
    
    if (needsBuild) {
      print('Building Linux native libraries...');
      
      // Check if build script exists
      final buildScript = File('scripts/build_test_libs.sh');
      if (!buildScript.existsSync()) {
        throw Exception(
          'Build script not found. Please run from project root directory.'
        );
      }
      
      // Run build script
      final result = await Process.run('bash', ['scripts/build_test_libs.sh']);
      
      if (result.exitCode != 0) {
        print('Build output:');
        print(result.stdout);
        print('Build errors:');
        print(result.stderr);
        throw Exception('Failed to build native libraries');
      }
      
      print('Linux native libraries built successfully');
    } else {
      print('All Linux native libraries found');
    }
  }
  
  /// Check if a specific library is available
  static bool isLibraryAvailable(String libraryName) {
    switch (libraryName) {
      case 'vulkan':
        return currentPlatform == 'linux' && 
               File('linux/libvulkan_processor.so').existsSync();
      case 'raw':
        return currentPlatform == 'linux' && 
               File('linux/libraw_processor.so').existsSync();
      default:
        return false;
    }
  }
  
  /// Clean up test artifacts if needed
  static Future<void> cleanup() async {
    // Currently no cleanup needed
  }
}