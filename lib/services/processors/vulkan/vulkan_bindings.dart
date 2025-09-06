import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// Vulkan FFI bindings for image processing
class VulkanBindings {
  static const String _libName = 'vulkan_processor';
  static late final DynamicLibrary _lib;
  static late final VulkanNative _native;
  static bool _initialized = false;
  
  /// Initialize Vulkan bindings
  static bool initialize() {
    if (_initialized) return true;
    
    try {
      // macOS doesn't have Vulkan support yet (will use Metal in future)
      if (Platform.isMacOS) {
        print('Vulkan not available on macOS - using CPU processor');
        return false;
      }
      
      // Try different possible paths for the library
      try {
        _lib = DynamicLibrary.open('linux/lib$_libName.so');
      } catch (_) {
        try {
          _lib = DynamicLibrary.open('lib$_libName.so');
        } catch (_) {
          try {
            _lib = DynamicLibrary.open('./lib$_libName.so');
          } catch (_) {
            try {
              _lib = DynamicLibrary.open('bundle/lib/lib$_libName.so');
            } catch (_) {
              _lib = DynamicLibrary.open('lib/lib$_libName.so');
            }
          }
        }
      }
      _native = VulkanNative(_lib);
      _initialized = _native.vk_init() == 1;
      return _initialized;
    } catch (e) {
      print('Failed to initialize Vulkan bindings: $e');
      return false;
    }
  }
  
  /// Check if Vulkan is available on this system
  static bool isAvailable() {
    if (!_initialized) {
      if (!initialize()) return false;
    }
    return _native.vk_is_available() == 1;
  }
  
  /// Process image with Vulkan (with tone curve support)
  static Uint8List? processImage(
    Uint8List pixels,
    int width,
    int height,
    Float32List adjustments, // Packed adjustment values
    {Uint8List? rgbLut,
     Uint8List? redLut,
     Uint8List? greenLut,
     Uint8List? blueLut}
  ) {
    if (!_initialized) return null;
    
    // Create identity LUTs if not provided
    final identityLut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      identityLut[i] = i;
    }
    
    rgbLut ??= identityLut;
    redLut ??= identityLut;
    greenLut ??= identityLut;
    blueLut ??= identityLut;
    
    final pixelsPtr = calloc<Uint8>(pixels.length);
    final adjustmentsPtr = calloc<Float>(adjustments.length);
    final rgbLutPtr = calloc<Uint8>(256);
    final redLutPtr = calloc<Uint8>(256);
    final greenLutPtr = calloc<Uint8>(256);
    final blueLutPtr = calloc<Uint8>(256);
    final outputPtr = calloc<Pointer<Uint8>>();
    
    try {
      // Copy input data
      pixelsPtr.asTypedList(pixels.length).setAll(0, pixels);
      adjustmentsPtr.asTypedList(adjustments.length).setAll(0, adjustments);
      rgbLutPtr.asTypedList(256).setAll(0, rgbLut);
      redLutPtr.asTypedList(256).setAll(0, redLut);
      greenLutPtr.asTypedList(256).setAll(0, greenLut);
      blueLutPtr.asTypedList(256).setAll(0, blueLut);
      
      // Process with Vulkan (using tone curves version)
      final result = _native.vk_process_image_with_curves(
        pixelsPtr,
        width,
        height,
        adjustmentsPtr,
        adjustments.length,
        rgbLutPtr,
        redLutPtr,
        greenLutPtr,
        blueLutPtr,
        outputPtr,
      );
      
      if (result != 1) return null;
      
      // Copy output data
      final outputSize = width * height * 4; // RGBA
      final output = outputPtr.value.asTypedList(outputSize);
      return Uint8List.fromList(output);
    } finally {
      calloc.free(pixelsPtr);
      calloc.free(adjustmentsPtr);
      calloc.free(rgbLutPtr);
      calloc.free(redLutPtr);
      calloc.free(greenLutPtr);
      calloc.free(blueLutPtr);
      if (outputPtr.value != nullptr) {
        _native.vk_free_buffer(outputPtr.value);
      }
      calloc.free(outputPtr);
    }
  }
  
  /// Cleanup Vulkan resources
  static void dispose() {
    if (_initialized) {
      _native.vk_cleanup();
      _initialized = false;
    }
  }
}

/// Native function signatures
class VulkanNative {
  final DynamicLibrary _lib;
  
  VulkanNative(this._lib);
  
  /// Initialize Vulkan
  late final vk_init = _lib
      .lookup<NativeFunction<Int32 Function()>>('vk_init')
      .asFunction<int Function()>();
  
  /// Check if Vulkan is available
  late final vk_is_available = _lib
      .lookup<NativeFunction<Int32 Function()>>('vk_is_available')
      .asFunction<int Function()>();
  
  /// Process image (basic)
  late final vk_process_image = _lib
      .lookup<NativeFunction<Int32 Function(
        Pointer<Uint8>,  // input pixels
        Int32,           // width
        Int32,           // height
        Pointer<Float>,  // adjustments
        Int32,           // adjustment count
        Pointer<Pointer<Uint8>>, // output pixels
      )>>('vk_process_image')
      .asFunction<int Function(
        Pointer<Uint8>,
        int,
        int,
        Pointer<Float>,
        int,
        Pointer<Pointer<Uint8>>,
      )>();
  
  /// Process image with tone curves
  late final vk_process_image_with_curves = _lib
      .lookup<NativeFunction<Int32 Function(
        Pointer<Uint8>,  // input pixels
        Int32,           // width
        Int32,           // height
        Pointer<Float>,  // adjustments
        Int32,           // adjustment count
        Pointer<Uint8>,  // rgb_lut
        Pointer<Uint8>,  // red_lut
        Pointer<Uint8>,  // green_lut
        Pointer<Uint8>,  // blue_lut
        Pointer<Pointer<Uint8>>, // output pixels
      )>>('vk_process_image_with_curves')
      .asFunction<int Function(
        Pointer<Uint8>,
        int,
        int,
        Pointer<Float>,
        int,
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Pointer<Uint8>>,
      )>();
  
  /// Free allocated buffer
  late final vk_free_buffer = _lib
      .lookup<NativeFunction<Void Function(Pointer<Uint8>)>>('vk_free_buffer')
      .asFunction<void Function(Pointer<Uint8>)>();
  
  /// Cleanup Vulkan
  late final vk_cleanup = _lib
      .lookup<NativeFunction<Void Function()>>('vk_cleanup')
      .asFunction<void Function()>();
}