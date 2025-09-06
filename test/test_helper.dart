import 'dart:io';

/// Test helper to ensure native libraries are built before running tests
class TestHelper {
  static bool _initialized = false;
  
  /// Ensure test environment is set up
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    
    print('Checking test environment...');
    
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
      print('Building native libraries...');
      
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
      
      print('Native libraries built successfully');
    } else {
      print('All native libraries found');
    }
    
    _initialized = true;
  }
  
  /// Clean up test artifacts if needed
  static Future<void> cleanup() async {
    // Currently no cleanup needed
  }
}