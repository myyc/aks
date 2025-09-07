import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/text_styles.dart';
import '../models/crop_state.dart';

class CropOverlay extends StatefulWidget {
  final Size imageSize;
  final Function(PointerScrollEvent)? onScroll;
  
  const CropOverlay({
    Key? key,
    required this.imageSize,
    this.onScroll,
  }) : super(key: key);
  
  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  Offset? _dragStart;
  CropRect? _initialCropRect;
  String? _dragHandle;
  String? _hoveredHandle;  // Track which handle is being hovered
  
  @override
  Widget build(BuildContext context) {
    return Consumer<CropState>(
      builder: (context, cropState, child) {
        if (!cropState.isActive) {
          return const SizedBox.shrink();
        }
        
        return Stack(
          children: [
            // Listener for scroll events only - doesn't block anything
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent && widget.onScroll != null) {
                  widget.onScroll!(event);
                }
              },
              child: Container(),  // Empty container just for capturing scroll
            ),
            
            // Dark overlay outside crop area - ignore pointer events
            IgnorePointer(
              child: CustomPaint(
                size: widget.imageSize,
                painter: CropOverlayPainter(
                  cropRect: cropState.cropRect,
                  showRuleOfThirds: cropState.showRuleOfThirds,
                ),
              ),
            ),
            
            // Interactive crop area
            _buildInteractiveCropArea(cropState),
            
            // Aspect ratio selector
            _buildAspectRatioSelector(cropState),
          ],
        );
      },
    );
  }
  
  Widget _buildInteractiveCropArea(CropState cropState) {
    final rect = cropState.cropRect.toPixelRect(
      widget.imageSize.width,
      widget.imageSize.height,
    );
    
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Stack(
        children: [
          // Visual border
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
            ),
          ),
          
          // Draggable interior - blocks mouse drag but allows trackpad gestures
          GestureDetector(
            onPanStart: (details) {
              // Check if this is a mouse drag (not trackpad gesture)
              // Mouse drags typically have smaller initial velocities
              _onPanStart(details, cropState, 'center');
            },
            onPanUpdate: (details) => _onPanUpdate(details, cropState),
            onPanEnd: (_) => _onPanEnd(),
            behavior: HitTestBehavior.opaque,
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.open_with,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Corner handles
          _buildHandle('top-left', cropState),
          _buildHandle('top-right', cropState),
          _buildHandle('bottom-left', cropState),
          _buildHandle('bottom-right', cropState),
          
          // Edge handles
          _buildHandle('top', cropState),
          _buildHandle('bottom', cropState),
          _buildHandle('left', cropState),
          _buildHandle('right', cropState),
        ],
      ),
    );
  }
  
  Widget _buildHandle(String position, CropState cropState) {
    final handleSize = 20.0;
    final halfSize = handleSize / 2;
    final isHovered = _hoveredHandle == position;
    
    Widget handle = MouseRegion(
      onEnter: (_) => setState(() => _hoveredHandle = position),
      onExit: (_) => setState(() => _hoveredHandle = null),
      cursor: _getCursorForPosition(position),
      child: GestureDetector(
        onPanStart: (details) => _onPanStart(details, cropState, position),
        onPanUpdate: (details) => _onPanUpdate(details, cropState),
        onPanEnd: (_) => _onPanEnd(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: handleSize * (isHovered ? 1.3 : 1.0),
          height: handleSize * (isHovered ? 1.3 : 1.0),
          decoration: BoxDecoration(
            color: isHovered ? Colors.white : Colors.white.withOpacity(0.9),
            border: Border.all(
              color: isHovered ? Colors.white : Colors.black,
              width: isHovered ? 2 : 1,
            ),
            shape: position.contains('-') ? BoxShape.circle : BoxShape.rectangle,
            boxShadow: isHovered ? [
              BoxShadow(
                color: Colors.white.withOpacity(0.6),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ] : null,
          ),
        ),
      ),
    );
    
    switch (position) {
      case 'top-left':
        return Positioned(
          left: -halfSize,
          top: -halfSize,
          child: handle,
        );
      case 'top-right':
        return Positioned(
          right: -halfSize,
          top: -halfSize,
          child: handle,
        );
      case 'bottom-left':
        return Positioned(
          left: -halfSize,
          bottom: -halfSize,
          child: handle,
        );
      case 'bottom-right':
        return Positioned(
          right: -halfSize,
          bottom: -halfSize,
          child: handle,
        );
      case 'top':
        return Positioned(
          left: 0,
          right: 0,
          top: -halfSize,
          height: handleSize,
          child: Center(child: handle),
        );
      case 'bottom':
        return Positioned(
          left: 0,
          right: 0,
          bottom: -halfSize,
          height: handleSize,
          child: Center(child: handle),
        );
      case 'left':
        return Positioned(
          left: -halfSize,
          top: 0,
          bottom: 0,
          width: handleSize,
          child: Center(child: handle),
        );
      case 'right':
        return Positioned(
          right: -halfSize,
          top: 0,
          bottom: 0,
          width: handleSize,
          child: Center(child: handle),
        );
      default:
        return const SizedBox.shrink();
    }
  }
  
  Widget _buildAspectRatioSelector(CropState cropState) {
    return Positioned(
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
                  cropState.setAspectRatioPreset(preset, widget.imageSize.width, widget.imageSize.height);
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
                  onTap: () => cropState.toggleOrientation(widget.imageSize.width, widget.imageSize.height),
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
    );
  }
  
  SystemMouseCursor _getCursorForPosition(String position) {
    switch (position) {
      case 'top-left':
        return SystemMouseCursors.resizeUpLeft;
      case 'top-right':
        return SystemMouseCursors.resizeUpRight;
      case 'bottom-left':
        return SystemMouseCursors.resizeDownLeft;
      case 'bottom-right':
        return SystemMouseCursors.resizeDownRight;
      case 'top':
      case 'bottom':
        return SystemMouseCursors.resizeUpDown;
      case 'left':
      case 'right':
        return SystemMouseCursors.resizeLeftRight;
      case 'center':
        return SystemMouseCursors.move;
      default:
        return SystemMouseCursors.basic;
    }
  }
  
  void _onPanStart(DragStartDetails details, CropState cropState, String handle) {
    _dragStart = details.localPosition;
    _initialCropRect = cropState.cropRect;
    _dragHandle = handle;
  }
  
  void _onPanUpdate(DragUpdateDetails details, CropState cropState) {
    if (_dragStart == null || _initialCropRect == null || _dragHandle == null) return;
    
    final delta = details.localPosition - _dragStart!;
    final dx = delta.dx / widget.imageSize.width;
    final dy = delta.dy / widget.imageSize.height;
    
    CropRect newRect = _initialCropRect!;
    
    // Check if we have an aspect ratio to maintain
    final hasAspectRatio = cropState.aspectRatioPreset != AspectRatioPreset.free && _dragHandle != 'center';
    final targetRatio = hasAspectRatio 
        ? cropState.aspectRatioPreset.getRatioWithOrientation(cropState.isPortraitOrientation)
        : null;
    
    if (hasAspectRatio && targetRatio != null) {
      // FOR ASPECT RATIO PRESETS - CALCULATE IN PIXEL SPACE FOR ACTUAL ASPECT RATIO
      switch (_dragHandle) {
        case 'top-left':
          // Move left edge, calculate everything IN PIXELS for true aspect ratio
          final newLeft = (_initialCropRect!.left + dx).clamp(0.0, _initialCropRect!.right - 0.05);
          
          // Convert to PIXELS
          final pixelLeft = newLeft * widget.imageSize.width;
          final pixelRight = _initialCropRect!.right * widget.imageSize.width;
          final pixelWidth = pixelRight - pixelLeft;
          
          // Calculate height IN PIXELS to maintain aspect ratio
          final pixelHeight = pixelWidth / targetRatio;
          
          // Convert back to normalized
          final normalizedHeight = pixelHeight / widget.imageSize.height;
          
          newRect = CropRect(
            left: newLeft,
            top: _initialCropRect!.bottom - normalizedHeight,
            right: _initialCropRect!.right,
            bottom: _initialCropRect!.bottom,
          );
          break;
        case 'top-right':
          // Move right edge, calculate everything IN PIXELS for true aspect ratio
          final newRight = (_initialCropRect!.right + dx).clamp(_initialCropRect!.left + 0.05, 1.0);
          
          // Convert to PIXELS
          final pixelLeft = _initialCropRect!.left * widget.imageSize.width;
          final pixelRight = newRight * widget.imageSize.width;
          final pixelWidth = pixelRight - pixelLeft;
          
          // Calculate height IN PIXELS to maintain aspect ratio
          final pixelHeight = pixelWidth / targetRatio;
          
          // Convert back to normalized
          final normalizedHeight = pixelHeight / widget.imageSize.height;
          
          newRect = CropRect(
            left: _initialCropRect!.left,
            top: _initialCropRect!.bottom - normalizedHeight,
            right: newRight,
            bottom: _initialCropRect!.bottom,
          );
          break;
        case 'bottom-left':
          // Move left edge, calculate everything IN PIXELS for true aspect ratio
          final newLeft = (_initialCropRect!.left + dx).clamp(0.0, _initialCropRect!.right - 0.05);
          
          // Convert to PIXELS
          final pixelLeft = newLeft * widget.imageSize.width;
          final pixelRight = _initialCropRect!.right * widget.imageSize.width;
          final pixelWidth = pixelRight - pixelLeft;
          
          // Calculate height IN PIXELS to maintain aspect ratio
          final pixelHeight = pixelWidth / targetRatio;
          
          // Convert back to normalized
          final normalizedHeight = pixelHeight / widget.imageSize.height;
          
          newRect = CropRect(
            left: newLeft,
            top: _initialCropRect!.top,
            right: _initialCropRect!.right,
            bottom: _initialCropRect!.top + normalizedHeight,
          );
          break;
        case 'bottom-right':
          // Move right edge, calculate everything IN PIXELS for true aspect ratio
          final newRight = (_initialCropRect!.right + dx).clamp(_initialCropRect!.left + 0.05, 1.0);
          
          // Convert to PIXELS
          final pixelLeft = _initialCropRect!.left * widget.imageSize.width;
          final pixelRight = newRight * widget.imageSize.width;
          final pixelWidth = pixelRight - pixelLeft;
          
          // Calculate height IN PIXELS to maintain aspect ratio
          final pixelHeight = pixelWidth / targetRatio;
          
          // Convert back to normalized
          final normalizedHeight = pixelHeight / widget.imageSize.height;
          
          newRect = CropRect(
            left: _initialCropRect!.left,
            top: _initialCropRect!.top,
            right: newRight,
            bottom: _initialCropRect!.top + normalizedHeight,
          );
          break;
        case 'top':
          // Move top edge, calculate width IN PIXELS to maintain ratio
          final newTop = (_initialCropRect!.top + dy).clamp(0.0, _initialCropRect!.bottom - 0.05);
          
          // Convert to PIXELS
          final pixelHeight = (_initialCropRect!.bottom - newTop) * widget.imageSize.height;
          final pixelWidth = pixelHeight * targetRatio;
          
          // Convert back to normalized
          final normalizedWidth = pixelWidth / widget.imageSize.width;
          final widthDiff = normalizedWidth - _initialCropRect!.width;
          
          newRect = CropRect(
            left: _initialCropRect!.left - widthDiff / 2,
            top: newTop,
            right: _initialCropRect!.right + widthDiff / 2,
            bottom: _initialCropRect!.bottom,
          );
          break;
        case 'bottom':
          // Move bottom edge, calculate width IN PIXELS to maintain ratio
          final newBottom = (_initialCropRect!.bottom + dy).clamp(_initialCropRect!.top + 0.05, 1.0);
          
          // Convert to PIXELS
          final pixelHeight = (newBottom - _initialCropRect!.top) * widget.imageSize.height;
          final pixelWidth = pixelHeight * targetRatio;
          
          // Convert back to normalized
          final normalizedWidth = pixelWidth / widget.imageSize.width;
          final widthDiff = normalizedWidth - _initialCropRect!.width;
          
          newRect = CropRect(
            left: _initialCropRect!.left - widthDiff / 2,
            top: _initialCropRect!.top,
            right: _initialCropRect!.right + widthDiff / 2,
            bottom: newBottom,
          );
          break;
        case 'left':
          // Move left edge, calculate height IN PIXELS to maintain ratio
          final newLeft = (_initialCropRect!.left + dx).clamp(0.0, _initialCropRect!.right - 0.05);
          
          // Convert to PIXELS
          final pixelWidth = (_initialCropRect!.right - newLeft) * widget.imageSize.width;
          final pixelHeight = pixelWidth / targetRatio;
          
          // Convert back to normalized
          final normalizedHeight = pixelHeight / widget.imageSize.height;
          final heightDiff = normalizedHeight - _initialCropRect!.height;
          
          newRect = CropRect(
            left: newLeft,
            top: _initialCropRect!.top - heightDiff / 2,
            right: _initialCropRect!.right,
            bottom: _initialCropRect!.bottom + heightDiff / 2,
          );
          break;
        case 'right':
          // Move right edge, calculate height IN PIXELS to maintain ratio
          final newRight = (_initialCropRect!.right + dx).clamp(_initialCropRect!.left + 0.05, 1.0);
          
          // Convert to PIXELS
          final pixelWidth = (newRight - _initialCropRect!.left) * widget.imageSize.width;
          final pixelHeight = pixelWidth / targetRatio;
          
          // Convert back to normalized
          final normalizedHeight = pixelHeight / widget.imageSize.height;
          final heightDiff = normalizedHeight - _initialCropRect!.height;
          
          newRect = CropRect(
            left: _initialCropRect!.left,
            top: _initialCropRect!.top - heightDiff / 2,
            right: newRight,
            bottom: _initialCropRect!.bottom + heightDiff / 2,
          );
          break;
        default:
          break;
      }
    } else {
      // FREE MODE - Allow independent movement
      switch (_dragHandle) {
        case 'center':
          // Move entire crop area
          newRect = CropRect(
            left: (_initialCropRect!.left + dx).clamp(0.0, 1.0 - _initialCropRect!.width),
            top: (_initialCropRect!.top + dy).clamp(0.0, 1.0 - _initialCropRect!.height),
            right: (_initialCropRect!.right + dx).clamp(_initialCropRect!.width, 1.0),
            bottom: (_initialCropRect!.bottom + dy).clamp(_initialCropRect!.height, 1.0),
          );
          break;
        case 'top-left':
          newRect = _initialCropRect!.copyWith(
            left: (_initialCropRect!.left + dx).clamp(0.0, _initialCropRect!.right - 0.05),
            top: (_initialCropRect!.top + dy).clamp(0.0, _initialCropRect!.bottom - 0.05),
          );
          break;
        case 'top-right':
          newRect = _initialCropRect!.copyWith(
            right: (_initialCropRect!.right + dx).clamp(_initialCropRect!.left + 0.05, 1.0),
            top: (_initialCropRect!.top + dy).clamp(0.0, _initialCropRect!.bottom - 0.05),
          );
          break;
        case 'bottom-left':
          newRect = _initialCropRect!.copyWith(
            left: (_initialCropRect!.left + dx).clamp(0.0, _initialCropRect!.right - 0.05),
            bottom: (_initialCropRect!.bottom + dy).clamp(_initialCropRect!.top + 0.05, 1.0),
          );
          break;
        case 'bottom-right':
          newRect = _initialCropRect!.copyWith(
            right: (_initialCropRect!.right + dx).clamp(_initialCropRect!.left + 0.05, 1.0),
            bottom: (_initialCropRect!.bottom + dy).clamp(_initialCropRect!.top + 0.05, 1.0),
          );
          break;
        case 'top':
          newRect = _initialCropRect!.copyWith(
            top: (_initialCropRect!.top + dy).clamp(0.0, _initialCropRect!.bottom - 0.05),
          );
          break;
        case 'bottom':
          newRect = _initialCropRect!.copyWith(
            bottom: (_initialCropRect!.bottom + dy).clamp(_initialCropRect!.top + 0.05, 1.0),
          );
          break;
        case 'left':
          newRect = _initialCropRect!.copyWith(
            left: (_initialCropRect!.left + dx).clamp(0.0, _initialCropRect!.right - 0.05),
          );
          break;
        case 'right':
          newRect = _initialCropRect!.copyWith(
            right: (_initialCropRect!.right + dx).clamp(_initialCropRect!.left + 0.05, 1.0),
          );
          break;
      }
    }
    
    // Ensure the crop rectangle stays within image bounds
    // BUT DON'T BREAK ASPECT RATIO FOR PRESETS!
    if (hasAspectRatio && targetRatio != null) {
      // For aspect ratio presets, clamp but maintain ratio
      newRect = _clampToImageBoundsWithRatio(newRect, targetRatio);
    } else {
      // For free mode, clamp normally
      newRect = _clampToImageBounds(newRect);
    }
    
    cropState.updateCropRectWithDimensions(newRect, widget.imageSize.width, widget.imageSize.height);
  }
  
  void _onPanEnd() {
    _dragStart = null;
    _initialCropRect = null;
    _dragHandle = null;
  }
  
  CropRect _constrainToAspectRatio(CropRect rect, double targetRatio, String handle) {
    // FORCE THE EXACT ASPECT RATIO - NO EXCEPTIONS
    final width = rect.width;
    final height = rect.height;
    
    // For ALL handles, we ALWAYS maintain the EXACT aspect ratio
    // We keep the dimension that was changed and adjust the other
    
    if (handle == 'top-left') {
      // Anchor is bottom-right
      // Always maintain exact aspect ratio
      final newHeight = width / targetRatio;
      return CropRect(
        left: rect.left,
        top: rect.bottom - newHeight,
        right: rect.right,
        bottom: rect.bottom,
      );
    } else if (handle == 'top-right') {
      // Anchor is bottom-left
      final newHeight = width / targetRatio;
      return CropRect(
        left: rect.left,
        top: rect.bottom - newHeight,
        right: rect.right,
        bottom: rect.bottom,
      );
    } else if (handle == 'bottom-left') {
      // Anchor is top-right
      final newHeight = width / targetRatio;
      return CropRect(
        left: rect.left,
        top: rect.top,
        right: rect.right,
        bottom: rect.top + newHeight,
      );
    } else if (handle == 'bottom-right') {
      // Anchor is top-left
      final newHeight = width / targetRatio;
      return CropRect(
        left: rect.left,
        top: rect.top,
        right: rect.right,
        bottom: rect.top + newHeight,
      );
    } else if (handle == 'left' || handle == 'right') {
      // Side handles - adjust height to maintain ratio
      final newHeight = width / targetRatio;
      final heightDiff = newHeight - height;
      return rect.copyWith(
        top: rect.top - heightDiff / 2,
        bottom: rect.bottom + heightDiff / 2,
      );
    } else if (handle == 'top' || handle == 'bottom') {
      // Top/bottom handles - adjust width to maintain ratio
      final newWidth = height * targetRatio;
      final widthDiff = newWidth - width;
      return rect.copyWith(
        left: rect.left - widthDiff / 2,
        right: rect.right + widthDiff / 2,
      );
    }
    
    return rect;
  }
  
  // Helper method to ensure crop stays within image bounds
  CropRect _clampToImageBounds(CropRect rect) {
    // Ensure all values are within [0, 1]
    double left = rect.left.clamp(0.0, 1.0);
    double top = rect.top.clamp(0.0, 1.0);
    double right = rect.right.clamp(0.0, 1.0);
    double bottom = rect.bottom.clamp(0.0, 1.0);
    
    // Ensure minimum size
    const minSize = 0.05;
    if (right - left < minSize) {
      if (left < 0.5) {
        right = left + minSize;
      } else {
        left = right - minSize;
      }
    }
    if (bottom - top < minSize) {
      if (top < 0.5) {
        bottom = top + minSize;
      } else {
        top = bottom - minSize;
      }
    }
    
    return CropRect(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }
  
  // Helper method to clamp within bounds WHILE MAINTAINING ASPECT RATIO IN PIXELS
  CropRect _clampToImageBoundsWithRatio(CropRect rect, double targetRatio) {
    double left = rect.left;
    double top = rect.top;
    double right = rect.right;
    double bottom = rect.bottom;
    
    // Clamp to bounds first
    left = left.clamp(0.0, 1.0);
    right = right.clamp(0.0, 1.0);
    top = top.clamp(0.0, 1.0);
    bottom = bottom.clamp(0.0, 1.0);
    
    // Convert to pixels to maintain actual aspect ratio
    final pixelLeft = left * widget.imageSize.width;
    final pixelRight = right * widget.imageSize.width;
    final pixelTop = top * widget.imageSize.height;
    final pixelBottom = bottom * widget.imageSize.height;
    
    double pixelWidth = pixelRight - pixelLeft;
    double pixelHeight = pixelBottom - pixelTop;
    
    // If it got too small, enforce minimum size
    const minPixelSize = 30.0;
    if (pixelWidth < minPixelSize || pixelHeight < minPixelSize) {
      pixelWidth = minPixelSize;
      pixelHeight = minPixelSize;  // For square
    }
    
    // FORCE the exact pixel aspect ratio
    pixelHeight = pixelWidth / targetRatio;
    
    // Check if it fits, if not scale down
    if (pixelHeight > widget.imageSize.height) {
      pixelHeight = widget.imageSize.height;
      pixelWidth = pixelHeight * targetRatio;
    }
    if (pixelWidth > widget.imageSize.width) {
      pixelWidth = widget.imageSize.width;
      pixelHeight = pixelWidth / targetRatio;
    }
    
    // Center if needed
    final pixelCenterX = (pixelLeft + pixelRight) / 2;
    final pixelCenterY = (pixelTop + pixelBottom) / 2;
    
    // Adjust center if it would go out of bounds
    double finalCenterX = pixelCenterX;
    double finalCenterY = pixelCenterY;
    
    if (pixelCenterX - pixelWidth/2 < 0) {
      finalCenterX = pixelWidth/2;
    } else if (pixelCenterX + pixelWidth/2 > widget.imageSize.width) {
      finalCenterX = widget.imageSize.width - pixelWidth/2;
    }
    
    if (pixelCenterY - pixelHeight/2 < 0) {
      finalCenterY = pixelHeight/2;
    } else if (pixelCenterY + pixelHeight/2 > widget.imageSize.height) {
      finalCenterY = widget.imageSize.height - pixelHeight/2;
    }
    
    // Convert back to normalized
    return CropRect(
      left: ((finalCenterX - pixelWidth/2) / widget.imageSize.width).clamp(0.0, 1.0),
      top: ((finalCenterY - pixelHeight/2) / widget.imageSize.height).clamp(0.0, 1.0),
      right: ((finalCenterX + pixelWidth/2) / widget.imageSize.width).clamp(0.0, 1.0),
      bottom: ((finalCenterY + pixelHeight/2) / widget.imageSize.height).clamp(0.0, 1.0),
    );
  }
}

class CropOverlayPainter extends CustomPainter {
  final CropRect cropRect;
  final bool showRuleOfThirds;
  
  CropOverlayPainter({
    required this.cropRect,
    required this.showRuleOfThirds,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final rect = cropRect.toPixelRect(size.width, size.height);
    
    // Draw dark overlay outside crop area
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    
    // Create path with hole for crop area
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, overlayPaint);
    
    // Draw rule of thirds grid if enabled
    if (showRuleOfThirds) {
      final gridPaint = Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      
      // Vertical lines
      final thirdWidth = rect.width / 3;
      for (int i = 1; i < 3; i++) {
        final x = rect.left + thirdWidth * i;
        canvas.drawLine(
          Offset(x, rect.top),
          Offset(x, rect.bottom),
          gridPaint,
        );
      }
      
      // Horizontal lines
      final thirdHeight = rect.height / 3;
      for (int i = 1; i < 3; i++) {
        final y = rect.top + thirdHeight * i;
        canvas.drawLine(
          Offset(rect.left, y),
          Offset(rect.right, y),
          gridPaint,
        );
      }
    }
  }
  
  @override
  bool shouldRepaint(CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect || 
           oldDelegate.showRuleOfThirds != showRuleOfThirds;
  }
}