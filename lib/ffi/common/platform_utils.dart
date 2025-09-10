import 'dart:io';

/// Platform-specific utilities and constants
class PlatformUtils {
  /// Get the current platform identifier
  static String get platform {
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }
  
  /// Get platform-specific library extension
  static String get libraryExtension {
    if (Platform.isLinux) return 'so';
    if (Platform.isMacOS) return 'dylib';
    if (Platform.isWindows) return 'dll';
    throw UnsupportedError('Platform not supported');
  }
  
  /// Get platform-specific library prefix
  static String get libraryPrefix {
    return (Platform.isLinux || Platform.isMacOS) ? 'lib' : '';
  }
  
  /// Get platform-specific path separator
  static String get pathSeparator {
    return Platform.pathSeparator;
  }
  
  /// Check if running on a Unix-like system
  static bool get isUnix => Platform.isLinux || Platform.isMacOS;
  
  /// Get common library search paths for the current platform
  static List<String> get commonLibraryPaths {
    final paths = <String>[];
    
    if (Platform.isLinux) {
      paths.addAll([
        '/usr/local/lib',
        '/usr/lib',
        '/lib',
        Directory.current.path,
      ]);
    } else if (Platform.isMacOS) {
      paths.addAll([
        '/usr/local/lib',
        '/opt/homebrew/lib',  // Apple Silicon Macs
        '/usr/local/opt/libraw/lib',
        Directory.current.path,
      ]);
    } else if (Platform.isWindows) {
      paths.addAll([
        Directory.current.path,
        Platform.environment['PROGRAMFILES'] ?? r'C:\Program Files',
        Platform.environment['PROGRAMFILES(X86)'] ?? r'C:\Program Files (x86)',
      ]);
    }
    
    return paths;
  }
  
  /// Get platform-specific environment variables
  static Map<String, String> get platformEnvironment {
    final env = Platform.environment;
    
    if (Platform.isLinux) {
      return {
        ...env,
        'LD_LIBRARY_PATH': env['LD_LIBRARY_PATH'] ?? '',
      };
    } else if (Platform.isMacOS) {
      return {
        ...env,
        'DYLD_LIBRARY_PATH': env['DYLD_LIBRARY_PATH'] ?? '',
      };
    }
    
    return env;
  }
}