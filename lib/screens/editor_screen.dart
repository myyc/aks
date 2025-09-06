import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import '../models/image_state.dart';
import '../models/crop_state.dart';
import '../services/file_service.dart';
import '../services/export_service.dart';
import '../widgets/toolbar.dart';
import '../widgets/image_viewer.dart';
import '../widgets/editing_panel.dart';
import '../widgets/export_dialog.dart';
import '../widgets/histogram_widget.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({Key? key}) : super(key: key);

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final FocusNode _focusNode = FocusNode();
  bool _isPickingFile = false;
  
  @override
  void initState() {
    super.initState();
    // Load the last image when the screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ImageState>().loadLastImage();
    });
  }
  
  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageState = Provider.of<ImageState>(context);
    final cropState = Provider.of<CropState>(context);
    
    return CallbackShortcuts(
      bindings: {
        // Ctrl/Cmd + O or just O - Open file
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.keyO,
        ): () => _openFile(context),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyO,
        ): () => _openFile(context),
        LogicalKeySet(
          LogicalKeyboardKey.keyO,
        ): () => _openFile(context),
        
        // Ctrl/Cmd + E - Export
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.keyE,
        ): () => _exportImage(context),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyE,
        ): () => _exportImage(context),
        
        // Ctrl/Cmd + S - Save sidecar
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.keyS,
        ): () => _saveSidecar(context),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyS,
        ): () => _saveSidecar(context),
        
        // R - Reset all adjustments
        LogicalKeySet(
          LogicalKeyboardKey.keyR,
        ): () async {
          if (imageState.pipeline.hasAdjustments) {
            await imageState.resetAllAdjustments();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('All adjustments reset'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        },
        
        // C - Toggle crop tool
        LogicalKeySet(
          LogicalKeyboardKey.keyC,
        ): () {
          if (imageState.hasImage) {
            if (cropState.isActive) {
              cropState.cancelCropping();
            } else {
              cropState.startCropping(imageState.pipeline.cropRect);
            }
          }
        },
        
        // Ctrl/Cmd + Z - Undo
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.keyZ,
        ): () {
          if (imageState.historyManager.canUndo) {
            imageState.undo();
          }
        },
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyZ,
        ): () {
          if (imageState.historyManager.canUndo) {
            imageState.undo();
          }
        },
        
        // Ctrl/Cmd + Shift + Z - Redo
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyZ,
        ): () {
          if (imageState.historyManager.canRedo) {
            imageState.redo();
          }
        },
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyZ,
        ): () {
          if (imageState.historyManager.canRedo) {
            imageState.redo();
          }
        },
      },
      child: RawKeyboardListener(
        focusNode: _focusNode,
        autofocus: false,  // Don't grab focus automatically - let widgets handle their own events
        onKey: (RawKeyEvent event) {
          // Handle Space key for before/after toggle
          if (event.logicalKey == LogicalKeyboardKey.space) {
            if (imageState.hasImage) {
              if (event is RawKeyDownEvent) {
                imageState.setShowOriginal(true);
              } else if (event is RawKeyUpEvent) {
                imageState.setShowOriginal(false);
              }
            }
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0F0F0F), // Very dark background
          body: WindowBorder(
            color: const Color(0xFF2A2A2A),
            width: 1,
            child: Column(
            children: [
              Toolbar(
                onOpenImage: _isPickingFile ? null : () => _openFile(context),
                onExportImage: imageState.hasImage ? () => _exportImage(context) : null,
              ),
              Expanded(
                child: Row(
                  children: [
                    // Main image viewer
                    Expanded(
                      child: Container(
                        color: const Color(0xFF0F0F0F), // Match main background
                        child: Stack(
                          children: [
                            const ImageViewer(),
                            // Histogram overlay in top-right corner
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Consumer<ImageState>(
                                builder: (context, imageState, child) {
                                  return HistogramWidget(
                                    image: imageState.currentImage,
                                    width: 200,
                                    height: 80,
                                    cropRect: imageState.pipeline.cropRect,
                                  );
                                },
                              ),
                            ),
                            // Original indicator overlay
                            if (imageState.showOriginal && imageState.hasImage)
                              Positioned(
                                top: 20,
                                left: 20,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                                  ),
                                  child: const Text(
                                    'ORIGINAL',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Editing panel
                    const EditingPanel(),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _openFile(BuildContext context) async {
    // Prevent multiple file pickers
    if (_isPickingFile) return;
    
    final imageState = Provider.of<ImageState>(context, listen: false);
    final cropState = Provider.of<CropState>(context, listen: false);
    
    setState(() {
      _isPickingFile = true;
    });
    
    try {
      final filePath = await FileService.pickRawImage();
      
      if (filePath != null) {
        // Reset crop editing state when loading a new image
        cropState.resetEditingState();
        await imageState.loadImage(filePath);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingFile = false;
        });
      }
    }
  }
  
  Future<void> _exportImage(BuildContext context) async {
    final imageState = Provider.of<ImageState>(context, listen: false);
    
    if (!imageState.hasImage) return;
    
    // Show export dialog
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ExportDialog(
        imageWidth: imageState.exportImageWidth,
        imageHeight: imageState.exportImageHeight,
      ),
    );
    
    if (result != null && context.mounted) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF6366F1),
          ),
        ),
      );
      
      // Export the image with all settings
      final success = await imageState.exportImage(
        format: result['format'],
        jpegQuality: result['quality'],
        resizePercentage: result['resizePercentage'],
        frameType: result['frameType'] ?? 'none',
        frameColor: result['frameColor'] ?? 'black',
        borderWidth: result['borderWidth'] ?? 20,
      );
      
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success 
                ? 'Image exported successfully'
                : 'Failed to export image',
            ),
            backgroundColor: success 
              ? const Color(0xFF10B981)
              : const Color(0xFFEF4444),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  Future<void> _saveSidecar(BuildContext context) async {
    final imageState = Provider.of<ImageState>(context, listen: false);
    
    if (!imageState.pipeline.hasAdjustments) return;
    
    await imageState.savePipelineToSidecar();
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adjustments saved to sidecar file'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}