import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:xdg_desktop_portal/xdg_desktop_portal.dart';

class FileService {
  static const List<String> rawExtensions = [
    'cr2', 'cr3', 'nef', 'arw', 'orf', 'dng', 'raf', 'rw2',
    'pef', 'srw', 'x3f', 'erf', 'mef', 'mrw', 'nrw', 'rwl',
    'iiq', '3fr', 'dcr', 'kdc', 'sr2', 'srf', 'mdc', 'raw',
    'CR2', 'CR3', 'NEF', 'ARW', 'ORF', 'DNG', 'RAF', 'RW2',
  ];
  
  static XdgDesktopPortalClient? _portalClient;

  static Future<String?> pickRawImage() async {
    if (Platform.isLinux) {
      try {
        print('Trying XDG Desktop Portal for file picking...');
        
        // Create or reuse XDG portal client
        _portalClient ??= XdgDesktopPortalClient();
        
        // Create filters for RAW image formats
        final filters = [
          XdgFileChooserFilter(
            'RAW Images',
            [
              for (final ext in rawExtensions)
                XdgFileChooserGlobPattern('*.$ext'),
            ],
          ),
          XdgFileChooserFilter(
            'All Files',
            [
              XdgFileChooserGlobPattern('*'),
            ],
          ),
        ];
        
        // Open file dialog - returns a Stream
        final resultStream = _portalClient!.fileChooser.openFile(
          title: 'Open RAW Image',
          acceptLabel: 'Open',
          filters: filters,
          multiple: false,
        );
        
        // Get first result from stream
        final result = await resultStream.first;
        
        // Handle result
        if (result.uris.isNotEmpty) {
          final uri = Uri.parse(result.uris.first);
          final path = uri.toFilePath();
          print('Selected file via XDG Portal: $path');
          return path;
        } else {
          // User cancelled - this is normal, not an error
          print('File selection cancelled');
          return null;
        }
      } catch (e) {
        // Check if this is just a cancellation (user pressed Escape)
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('cancelled') || 
            errorStr.contains('cancel') || 
            errorStr.contains('closed') ||
            errorStr.contains('no such method')) {
          print('File selection cancelled');
          return null;
        }
        // Only print error and fall back for real errors
        print('XDG Portal failed, falling back to file_picker: $e');
        // Fall through to file_picker below
      }
    }
    
    // Use file_picker for non-Linux or as fallback
    // Skip file_picker if we're on Linux and portal was just cancelled
    if (Platform.isLinux) {
      // Portal was tried but failed/cancelled, don't fall back to file_picker
      // to avoid zenity errors
      return null;
    }
    
    try {
      print('Using file_picker for file selection...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: rawExtensions,
        dialogTitle: 'Open RAW Image',
        withData: false,
        withReadStream: false,
      );
      
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        print('Selected file via file_picker: $path');
        return path;
      } else {
        print('No file selected via file_picker');
        return null;
      }
    } catch (e) {
      print('Error picking file: $e');
      return null;
    }
  }
  
  static void dispose() {
    _portalClient?.close();
    _portalClient = null;
  }
}