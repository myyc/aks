import 'dart:io';
import 'image_processor_interface.dart';
import 'cpu_processor.dart';
import 'vulkan_processor.dart';

/// Factory for creating appropriate image processor based on platform and availability
class ProcessorFactory {
  static ImageProcessorInterface? _instance;
  static bool _useGpu = true; // User preference for GPU acceleration
  
  /// Get or create the singleton processor instance
  static Future<ImageProcessorInterface> getProcessor() async {
    if (_instance != null) {
      return _instance!;
    }
    
    _instance = await _createProcessor();
    await _instance!.initialize();
    return _instance!;
  }
  
  /// Create appropriate processor based on platform and availability
  static Future<ImageProcessorInterface> _createProcessor() async {
    print('ProcessorFactory: Detecting best processor for platform...');
    
    // Check environment variable to enable GPU processing
    // Default is false (use CPU) unless explicitly enabled
    final enableGpu = Platform.environment['AKS_ENABLE_GPU']?.toLowerCase();
    final gpuEnabled = enableGpu == 'true' || enableGpu == '1';
    
    if (!gpuEnabled) {
      print('ProcessorFactory: GPU not enabled (set AKS_ENABLE_GPU=true to enable), using CPU processor');
      return CpuProcessor();
    }
    
    // Check if GPU acceleration is enabled by user preference
    if (!_useGpu) {
      print('ProcessorFactory: GPU disabled by user preference, using CPU processor');
      return CpuProcessor();
    }
    
    // Platform-specific processor selection
    if (Platform.isLinux || Platform.isWindows) {
      // Check for Vulkan availability
      if (await VulkanProcessor.isAvailable()) {
        print('ProcessorFactory: Vulkan available and enabled, using GPU processor');
        return VulkanProcessor();
      }
      print('ProcessorFactory: Vulkan not available, falling back to CPU');
    } else if (Platform.isMacOS || Platform.isIOS) {
      // TODO: Future Metal implementation
      // if (await MetalProcessor.isAvailable()) {
      //   print('ProcessorFactory: Metal available, using GPU processor');
      //   return MetalProcessor();
      // }
      print('ProcessorFactory: Running on macOS/iOS, using CPU processor');
    }
    
    // Default fallback to CPU processor
    print('ProcessorFactory: Using CPU processor (default)');
    return CpuProcessor();
  }
  
  /// Set whether to use GPU acceleration (user preference)
  static void setUseGpu(bool useGpu) {
    if (_useGpu != useGpu) {
      _useGpu = useGpu;
      // Dispose current processor if settings changed
      if (_instance != null) {
        _instance!.dispose();
        _instance = null;
      }
    }
  }
  
  /// Get current processor name for UI/debugging
  static String getCurrentProcessorName() {
    return _instance?.name ?? 'Not initialized';
  }
  
  /// Check if GPU acceleration is available on this system
  static Future<bool> isGpuAvailable() async {
    if (Platform.isLinux || Platform.isWindows) {
      return await VulkanProcessor.isAvailable();
    } else if (Platform.isMacOS || Platform.isIOS) {
      // TODO: Return Metal availability
      return false; // Metal not yet implemented
    }
    return false;
  }
  
  /// Dispose of the current processor instance
  static void dispose() {
    _instance?.dispose();
    _instance = null;
  }
}