import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/text_styles.dart';
import 'dart:ui' as ui;
import '../models/image_state.dart';
import '../models/crop_state.dart';
import 'crop_overlay.dart';
import 'applied_crop_overlay.dart';

class ImageViewer extends StatefulWidget {
  const ImageViewer({Key? key}) : super(key: key);

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  final TransformationController _controller = TransformationController();
  static const double _minScale = 0.1;
  static const double _maxScale = 10.0;
  static const double _zoomSpeed = 0.1;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  
  Future<void> _applyCropToImage(ImageState imageState, CropState cropState) async {
    // Store the crop rect in the image state pipeline
    final cropRect = cropState.cropRect;
    
    print('_applyCropToImage called');
    print('Current crop rect: left=${cropRect.left}, top=${cropRect.top}, right=${cropRect.right}, bottom=${cropRect.bottom}');
    print('Pipeline before setCropRect: ${imageState.pipeline.cropRect}');
    
    // Update the pipeline with the new crop
    imageState.pipeline.setCropRect(cropRect);
    
    print('Pipeline after setCropRect: ${imageState.pipeline.cropRect}');
    print('Pipeline hasAdjustments: ${imageState.pipeline.hasAdjustments}');
    
    // Save to sidecar for persistence
    await imageState.savePipelineToSidecar();
    print('Crop saved to sidecar');
    
    // The image will be reprocessed automatically via the pipeline listener
    print('Crop should now be applied and image reprocessing triggered');
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final delta = event.scrollDelta.dy;
      final scaleFactor = delta > 0 ? (1 - _zoomSpeed) : (1 + _zoomSpeed);
      
      final currentScale = _controller.value.getMaxScaleOnAxis();
      final newScale = (currentScale * scaleFactor).clamp(_minScale, _maxScale);
      final scale = newScale / currentScale;
      
      // Get the position of the mouse pointer
      final pointerPosition = event.localPosition;
      
      // Calculate the focal point for scaling
      final matrix = Matrix4.identity()
        ..translate(pointerPosition.dx, pointerPosition.dy)
        ..scale(scale)
        ..translate(-pointerPosition.dx, -pointerPosition.dy);
      
      _controller.value = matrix * _controller.value;
      
      // Trigger a rebuild to update boundary margin based on new scale
      setState(() {});
    }
  }

  EdgeInsets _calculateBoundaryMargin(Size viewportSize) {
    // Get current scale from the transformation controller
    final currentScale = _controller.value.getMaxScaleOnAxis();
    
    // Calculate the larger dimension of the viewport
    final maxDimension = viewportSize.width > viewportSize.height 
        ? viewportSize.width 
        : viewportSize.height;
    
    // Dynamic boundary based on zoom level:
    // - At minimum zoom (0.1-1.0): Allow 50% of viewport for panning
    // - When zoomed in (>1.0): Increase proportionally for easier navigation
    // - Cap at 2x viewport size to prevent excessive panning
    final boundarySize = maxDimension * (currentScale > 1.0 
        ? (0.5 + (currentScale - 1.0) * 0.5).clamp(0.5, 2.0)
        : 0.5);
    
    return EdgeInsets.all(boundarySize);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ImageState>(
      builder: (context, imageState, child) {
        // Request focus when we have an image and are not loading
        if (imageState.hasImage && !imageState.isLoading) {
          // Use a post-frame callback to request focus after the widget is built
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_focusNode.hasFocus) {
              _focusNode.requestFocus();
            }
          });
        }
        
        if (imageState.isLoading) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white30),
                SizedBox(height: 16),
                Text(
                  'Processing RAW image...',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          );
        }

        if (imageState.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Error loading image',
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    imageState.error!,
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        if (!imageState.hasImage) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image, color: Colors.white30, size: 64),
                SizedBox(height: 16),
                Text(
                  'No image loaded',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Use the menu to open a RAW file',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ],
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
            final cropState = context.watch<CropState>();
            
            // Request focus when crop mode is active
            if (cropState.isActive && !_focusNode.hasFocus) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _focusNode.requestFocus();
              });
            }
            
            // Calculate the actual displayed size of the image
            // Use the image that's actually being displayed
            final imageToMeasure = imageState.getDisplayImage(cropState.isActive);
            final imageAspectRatio = imageToMeasure!.width / imageToMeasure.height;
            final viewportAspectRatio = constraints.maxWidth / constraints.maxHeight;
            
            double displayWidth, displayHeight;
            if (imageAspectRatio > viewportAspectRatio) {
              // Image is wider than viewport
              displayWidth = constraints.maxWidth;
              displayHeight = constraints.maxWidth / imageAspectRatio;
            } else {
              // Image is taller than viewport
              displayHeight = constraints.maxHeight;
              displayWidth = constraints.maxHeight * imageAspectRatio;
            }
            
            // Wrap with Listener first to catch scroll events based on position
            return Listener(
              onPointerSignal: _handlePointerSignal,
              behavior: HitTestBehavior.opaque,  // Receive events when cursor is over this area
              child: Focus(
                focusNode: _focusNode,
                autofocus: true,  // Auto-grab focus for keyboard shortcuts
                canRequestFocus: true,
                onKeyEvent: (FocusNode node, KeyEvent event) {
                if (event is KeyDownEvent && cropState.isActive) {
                  // Enter key to apply crop
                  if (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                    print('Enter key pressed - applying crop');
                    cropState.applyCrop();
                    _applyCropToImage(imageState, cropState);
                    return KeyEventResult.handled;
                  }
                  // Escape key to cancel crop
                  else if (event.logicalKey == LogicalKeyboardKey.escape) {
                    print('Escape key pressed - cancelling crop');
                    cropState.cancelCropping();
                    return KeyEventResult.handled;
                  }
                }
                
                // Zoom controls with Ctrl
                if (HardwareKeyboard.instance.isControlPressed) {
                  // Ctrl+Plus (both regular and numpad) to zoom in
                  if (event.logicalKey == LogicalKeyboardKey.equal || 
                      event.logicalKey == LogicalKeyboardKey.add ||
                      event.logicalKey == LogicalKeyboardKey.numpadAdd) {
                    final currentScale = _controller.value.getMaxScaleOnAxis();
                    final newScale = (currentScale * 1.2).clamp(_minScale, _maxScale);
                    
                    // Get the center of the viewport
                    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
                    
                    // Apply zoom transformation
                    final matrix = Matrix4.identity()
                      ..translate(center.dx, center.dy)
                      ..scale(newScale / currentScale)
                      ..translate(-center.dx, -center.dy);
                    
                    _controller.value = matrix * _controller.value;
                    setState(() {});
                    return KeyEventResult.handled;
                  }
                  // Ctrl+Minus (both regular and numpad) to zoom out
                  else if (event.logicalKey == LogicalKeyboardKey.minus ||
                           event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
                    final currentScale = _controller.value.getMaxScaleOnAxis();
                    final newScale = (currentScale / 1.2).clamp(_minScale, _maxScale);
                    
                    // Get the center of the viewport
                    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
                    
                    // Apply zoom transformation
                    final matrix = Matrix4.identity()
                      ..translate(center.dx, center.dy)
                      ..scale(newScale / currentScale)
                      ..translate(-center.dx, -center.dy);
                    
                    _controller.value = matrix * _controller.value;
                    setState(() {});
                    return KeyEventResult.handled;
                  }
                  // Ctrl+0 to reset zoom to fit
                  else if (event.logicalKey == LogicalKeyboardKey.digit0 ||
                           event.logicalKey == LogicalKeyboardKey.numpad0) {
                    _controller.value = Matrix4.identity();
                    setState(() {});
                    return KeyEventResult.handled;
                  }
                }
                
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onTap: () {
                  // Request focus when tapped
                  _focusNode.requestFocus();
                },
                child: Stack(
                  children: [
                    // Main image viewer
                    InteractiveViewer(
                      transformationController: _controller,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      boundaryMargin: _calculateBoundaryMargin(viewportSize),
                      // Enable both pan and scale
                      panEnabled: true,
                      scaleEnabled: true,
                      child: Center(
                        child: SizedBox(
                          width: displayWidth,
                          height: displayHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Show original during crop mode if image has been cropped, otherwise current
                              RawImage(
                                image: imageState.getDisplayImage(cropState.isActive),
                                fit: BoxFit.fill,
                              ),
                              // Crop overlay for active editing
                              if (cropState.isActive)
                                CropOverlay(
                                  imageSize: Size(displayWidth, displayHeight),
                                  originalImageSize: Size(
                                    (imageState.originalWidth ?? displayWidth).toDouble(),
                                    (imageState.originalHeight ?? displayHeight).toDouble(),
                                  ),
                                  onScroll: (event) {
                                    // Manually handle scroll events for zooming
                                    _handlePointerSignal(event);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Fixed aspect ratio selector at the top
                    if (cropState.isActive)
                      Positioned(
                        top: 20,
                        left: 20,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DropdownButton<AspectRatioPreset>(
                                value: cropState.aspectRatioPreset,
                                dropdownColor: Colors.black.withOpacity(0.9),
                                style: AppTextStyles.inter(color: Colors.white),
                                underline: const SizedBox.shrink(),
                                onChanged: (preset) {
                                  if (preset != null) {
                                    // Use original dimensions for precise aspect ratio
                                    final origWidth = imageState.originalWidth?.toDouble() ?? displayWidth;
                                    final origHeight = imageState.originalHeight?.toDouble() ?? displayHeight;
                                    cropState.setAspectRatioPreset(preset, origWidth, origHeight);
                                  }
                                },
                                items: AspectRatioPreset.values.map((preset) {
                                  return DropdownMenuItem(
                                    value: preset,
                                    child: Text(preset.getLabel(cropState.isPortraitOrientation)),
                                  );
                                }).toList(),
                              ),
                              // Orientation toggle button (hidden only for Square format)
                              if (cropState.aspectRatioPreset != AspectRatioPreset.square) ...[
                                const SizedBox(width: 8),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      // Use original dimensions for precise orientation toggle
                                      final origWidth = imageState.originalWidth?.toDouble() ?? displayWidth;
                                      final origHeight = imageState.originalHeight?.toDouble() ?? displayHeight;
                                      cropState.toggleOrientation(origWidth, origHeight);
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 1,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(
                                        cropState.isPortraitOrientation 
                                          ? Icons.crop_portrait 
                                          : Icons.crop_landscape,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    // Fixed crop control buttons at the bottom
                    if (cropState.isActive)
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            print('Cancel crop button pressed');
                            cropState.cancelCropping();
                          },
                          icon: const Icon(Icons.close),
                          label: Text(
                            'Cancel (Esc)',
                            style: AppTextStyles.inter(),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () async {
                            print('Apply crop button pressed');
                            cropState.applyCrop();
                            await _applyCropToImage(imageState, cropState);
                            print('Crop applied: ${cropState.cropRect.left}, ${cropState.cropRect.top}, ${cropState.cropRect.right}, ${cropState.cropRect.bottom}');
                          },
                          icon: const Icon(Icons.check),
                          label: Text(
                            'Apply Crop (Enter)',
                            style: AppTextStyles.inter(),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    ),
                  ],
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }
}