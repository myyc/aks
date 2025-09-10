import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

/// Base class for FFI operations with common utilities
abstract class FfiBase {
  /// Load dynamic library with platform-specific naming and paths
  static DynamicLibrary loadLibrary(String baseName, {
    List<String> linuxPaths = const [],
    List<String> macosPaths = const [],
    List<String> windowsPaths = const [],
  }) {
    late String libraryName;
    late List<String> searchPaths;
    
    if (Platform.isLinux) {
      libraryName = 'lib$baseName.so';
      searchPaths = linuxPaths;
    } else if (Platform.isMacOS) {
      libraryName = 'lib$baseName.dylib';
      searchPaths = macosPaths;
    } else if (Platform.isWindows) {
      libraryName = '$baseName.dll';
      searchPaths = windowsPaths;
    } else {
      throw UnsupportedError('Platform not supported');
    }
    
    // Try loading from standard library paths first
    try {
      return DynamicLibrary.open(libraryName);
    } catch (_) {
      // If not found, try additional search paths
      for (final searchPath in searchPaths) {
        try {
          final fullPath = path.join(searchPath, libraryName);
          return DynamicLibrary.open(fullPath);
        } catch (_) {
          continue;
        }
      }
      
      throw Exception('Could not load library: $libraryName');
    }
  }
  
  /// Safe memory allocation with automatic cleanup
  static Pointer<Uint8> mallocAndCopy(
    List<int> data,
  ) {
    final pointer = malloc<Uint8>(data.length);
    for (int i = 0; i < data.length; i++) {
      pointer[i] = data[i];
    }
    return pointer;
  }
  
  /// Convert FFI string to Dart string with null safety
  static String? fromCString(Pointer<Utf8>? charPtr) {
    return charPtr?.toDartString();
  }
  
  /// Convert Dart string to FFI string
  static Pointer<Utf8> toCString(String string) {
    return string.toNativeUtf8();
  }
  
  /// Check if a pointer is null
  static bool isNull(Pointer? pointer) => pointer == nullptr;
  
  /// Get platform-specific error message
  static String getPlatformErrorMessage(String operation) {
    return 'Failed to $operation on ${Platform.operatingSystem}';
  }
}