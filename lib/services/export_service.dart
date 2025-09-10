import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:xdg_desktop_portal/xdg_desktop_portal.dart';
import 'image_manipulation_service.dart';
import 'image_processor.dart';
import 'preferences_service.dart';
import '../models/crop_state.dart';
import '../ffi/jpeg/jpeg_processor.dart';

/// Export formats supported
enum ExportFormat {
  jpeg,
  png,
}

/// Service for exporting edited images to various formats
class ExportService {
  static XdgDesktopPortalClient? _portalClient;
  
  /// Generate a smart filename with _aks suffix and counter if needed
  static String generateExportFilename(String? originalPath, String extension) {
    if (originalPath == null) {
      return 'edited_image_aks.$extension';
    }
    
    final dir = path.dirname(originalPath);
    final basename = path.basenameWithoutExtension(originalPath);
    
    // Start with _aks (no number)
    String filename = '${basename}_aks.$extension';
    String fullPath = path.join(dir, filename);
    
    // Check if file exists
    if (!File(fullPath).existsSync()) {
      return filename;
    }
    
    // Try _aks01, _aks02, etc.
    int counter = 1;
    do {
      filename = '${basename}_aks${counter.toString().padLeft(2, '0')}.$extension';
      fullPath = path.join(dir, filename);
      counter++;
    } while (File(fullPath).existsSync() && counter < 100);
    
    return filename;
  }
  
  /// Export the image to JPEG format
  static Future<bool> exportJpeg({
    required ui.Image image,
    required String outputPath,
    int quality = 90,
  }) async {
    try {
      
      // Compress image to JPEG
      final jpegData = await JpegProcessor.compressImage(
        image: image,
        quality: quality,
      );
      
      // Write to file
      final file = File(outputPath);
      await file.writeAsBytes(jpegData);
      
      return true;
    } catch (e) {
      print('Error exporting JPEG: $e');
      return false;
    }
  }
  
  /// Export the image to PNG format
  static Future<bool> exportPng({
    required ui.Image image,
    required String outputPath,
  }) async {
    try {
      // Convert image to PNG byte data
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      
      if (byteData == null) {
        throw Exception('Failed to convert image to byte data');
      }
      
      final buffer = byteData.buffer.asUint8List();
      
      // Write to file
      final file = File(outputPath);
      await file.writeAsBytes(buffer);
      
      return true;
    } catch (e) {
      print('Error exporting PNG: $e');
      return false;
    }
  }
  
  /// Show export dialog and export the image with transformations
  static Future<bool> showExportDialog({
    required ui.Image image,
    required String? originalPath,
    ExportFormat format = ExportFormat.jpeg,
    int jpegQuality = 90,
    double? resizePercentage,
    String frameType = 'none',
    String frameColor = 'black',
    int borderWidth = 20,
  }) async {
    try {
      // Determine file extension and type
      final String extension = format == ExportFormat.jpeg ? 'jpg' : 'png';
      final String typeName = format == ExportFormat.jpeg ? 'JPEG' : 'PNG';
      
      // Generate smart filename (just the filename, not the full path)
      String smartFilename = generateExportFilename(originalPath, extension);
      
      String? outputFile;
      
      // Get last export directory if available
      final lastExportDir = await PreferencesService.getLastExportDirectory();
      String? initialDirectory;
      
      // Determine the directory to use
      if (lastExportDir != null) {
        initialDirectory = lastExportDir;
        print('Using last export directory: $initialDirectory');
      } else {
        // Try to get the Downloads directory from environment
        final home = Platform.environment['HOME'];
        final xdgDownload = Platform.environment['XDG_DOWNLOAD_DIR'];
        
        if (xdgDownload != null && await Directory(xdgDownload).exists()) {
          initialDirectory = xdgDownload;
          print('Using XDG Downloads directory: $initialDirectory');
        } else if (home != null) {
          // Fall back to ~/Downloads if XDG_DOWNLOAD_DIR is not set
          final downloadsPath = path.join(home, 'Downloads');
          if (await Directory(downloadsPath).exists()) {
            initialDirectory = downloadsPath;
            print('Using ~/Downloads directory: $initialDirectory');
          } else {
            // Fall back to home directory
            initialDirectory = home;
            print('Using home directory: $initialDirectory');
          }
        } else if (originalPath != null) {
          // Last resort: use the directory of the original image
          initialDirectory = path.dirname(originalPath);
          print('Using original image directory: $initialDirectory');
        } else {
          print('No initial directory available');
        }
      }
      
      // Try to use XDG Desktop Portal on Linux
      if (Platform.isLinux) {
        try {
          print('Trying XDG Desktop Portal for file save...');
          
          // Create or reuse XDG portal client
          _portalClient ??= XdgDesktopPortalClient();
          
          // Create filter for the chosen format
          final filters = [
            XdgFileChooserFilter(
              '$typeName Images',
              [XdgFileChooserGlobPattern('*.$extension')],
            ),
            XdgFileChooserFilter(
              'All Files',
              [XdgFileChooserGlobPattern('*')],
            ),
          ];
          
          // Show native save dialog - returns a Stream
          // Note: XDG Portal doesn't support setting initial directory with a string path
          // We can try to suggest a full path as the filename
          String suggestedName = smartFilename;
          if (initialDirectory != null && lastExportDir == null) {
            // Only suggest full path if we're using a default directory (not last export)
            suggestedName = path.join(initialDirectory, smartFilename);
            print('Suggesting full path to XDG Portal: $suggestedName');
          }
          
          final resultStream = _portalClient!.fileChooser.saveFile(
            title: 'Export as $typeName',
            acceptLabel: 'Export',
            currentName: suggestedName,
            filters: filters,
          );
          
          // Get first result from stream
          final result = await resultStream.first;
          
          // Handle result
          if (result.uris.isNotEmpty) {
            final uri = Uri.parse(result.uris.first);
            outputFile = uri.toFilePath();
            print('Save location via XDG Portal: $outputFile');
          } else {
            print('No save location selected via XDG Portal');
            return false;
          }
        } catch (e) {
          print('XDG Portal failed, falling back to file_picker: $e');
          // Fall back to file_picker if XDG portal fails
          outputFile = await FilePicker.platform.saveFile(
            dialogTitle: 'Export as $typeName',
            fileName: smartFilename,  // Just use filename, not full path
            initialDirectory: initialDirectory,  // Try with initialDirectory
            type: FileType.custom,
            allowedExtensions: [extension],
          );
        }
      } else {
        // Use file_picker on other platforms
        outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Export as $typeName',
          fileName: smartFilename,  // Just use filename, not full path
          initialDirectory: initialDirectory,  // Try with initialDirectory
          type: FileType.custom,
          allowedExtensions: [extension],
        );
      }
      
      if (outputFile == null) {
        return false; // User cancelled
      }
      
      // Ensure proper extension
      if (!outputFile.toLowerCase().endsWith('.$extension')) {
        outputFile = '$outputFile.$extension';
      }
      
      // Apply transformations if needed
      ui.Image imageToExport = image;
      if (resizePercentage != null || frameType != 'none') {
        // Determine frame color
        final uiFrameColor = frameColor == 'white' 
            ? const ui.Color(0xFFFFFFFF) 
            : const ui.Color(0xFF000000);
        
        imageToExport = await ImageManipulationService.applyTransformations(
          image,
          resizePercentage: resizePercentage,
          padToSquare: frameType == 'square',
          padColor: uiFrameColor,
          borderWidth: frameType == 'border' ? borderWidth : 0,
          borderColor: uiFrameColor,
        );
      }
      
      // Export based on format
      bool success = false;
      if (format == ExportFormat.jpeg) {
        success = await exportJpeg(
          image: imageToExport,
          outputPath: outputFile,
          quality: jpegQuality,
        );
      } else {
        success = await exportPng(
          image: imageToExport,
          outputPath: outputFile,
        );
      }
      
      // Dispose of transformed image if we created one
      if (imageToExport != image) {
        imageToExport.dispose();
      }
      
      // Save the export directory for next time if export was successful
      if (success) {
        final exportDir = path.dirname(outputFile);
        print('Export successful. Saving directory: $exportDir from file: $outputFile');
        await PreferencesService.saveLastExportDirectory(exportDir);
      } else {
        print('Export failed, not saving directory');
      }
      
      return success;
    } catch (e) {
      print('Error in export dialog: $e');
      return false;
    }
  }
  
  /// Export with full resolution processing
  static Future<bool> exportWithFullResolution({
    required ui.Image? previewImage,
    required ui.Image? fullImage,
    required String? originalPath,
    CropRect? cropRect,
    ExportFormat format = ExportFormat.jpeg,
    int jpegQuality = 90,
    double? resizePercentage,
    String frameType = 'none',
    String frameColor = 'black',
    int borderWidth = 20,
  }) async {
    // Use full resolution if available, otherwise use preview
    var imageToExport = fullImage ?? previewImage;
    
    if (imageToExport == null) {
      print('No image available for export');
      return false;
    }
    
    // Apply crop if specified
    if (cropRect != null) {
      print('Applying crop for export: $cropRect');
      print('Image size before crop: ${imageToExport.width}x${imageToExport.height}');
      imageToExport = await ImageProcessor.applyCropToImage(imageToExport, cropRect);
      print('Image size after crop: ${imageToExport.width}x${imageToExport.height}');
    }
    
    return await showExportDialog(
      image: imageToExport,
      originalPath: originalPath,
      format: format,
      jpegQuality: jpegQuality,
      resizePercentage: resizePercentage,
      frameType: frameType,
      frameColor: frameColor,
      borderWidth: borderWidth,
    );
  }
  
  /// Clean up the portal client
  static void dispose() {
    _portalClient?.close();
    _portalClient = null;
  }
}