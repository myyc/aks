import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class PreferencesService {
  static const String _lastImagePathKey = 'last_image_path';
  static const String _lastExportDirectoryKey = 'last_export_directory';
  static SharedPreferences? _prefs;

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> saveLastImagePath(String path) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_lastImagePathKey, path);
    print('Saved last image path: $path');
  }

  static Future<String?> getLastImagePath() async {
    _prefs ??= await SharedPreferences.getInstance();
    final path = _prefs!.getString(_lastImagePathKey);
    
    // Verify the file still exists before returning
    if (path != null && await File(path).exists()) {
      print('Retrieved last image path: $path');
      return path;
    }
    
    // Clear the preference if file no longer exists
    if (path != null) {
      await _prefs!.remove(_lastImagePathKey);
      print('Cleared non-existent last image path: $path');
    }
    
    return null;
  }

  static Future<void> clearLastImagePath() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_lastImagePathKey);
    print('Cleared last image path');
  }

  static Future<void> saveLastExportDirectory(String directory) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_lastExportDirectoryKey, directory);
    print('Saved last export directory: $directory');
  }

  static Future<String?> getLastExportDirectory() async {
    _prefs ??= await SharedPreferences.getInstance();
    final dir = _prefs!.getString(_lastExportDirectoryKey);
    
    // Verify the directory still exists before returning
    if (dir != null && await Directory(dir).exists()) {
      print('Retrieved last export directory: $dir');
      return dir;
    }
    
    // Clear the preference if directory no longer exists
    if (dir != null) {
      await _prefs!.remove(_lastExportDirectoryKey);
      print('Cleared non-existent last export directory: $dir');
    }
    
    return null;
  }
}