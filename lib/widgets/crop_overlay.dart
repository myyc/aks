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
    
    Widget handle = GestureDetector(
      onPanStart: (details) => _onPanStart(details, cropState, position),
      onPanUpdate: (details) => _onPanUpdate(details, cropState),
      onPanEnd: (_) => _onPanEnd(),
      child: Container(
        width: handleSize,
        height: handleSize,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 1),
          shape: position.contains('-') ? BoxShape.circle : BoxShape.rectangle,
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
        child: DropdownButton<AspectRatioPreset>(
          value: cropState.aspectRatioPreset,
          dropdownColor: Colors.black.withOpacity(0.9),
          style: AppTextStyles.inter(color: Colors.white),
          underline: const SizedBox.shrink(),
          onChanged: (preset) {
            if (preset != null) {
              cropState.setAspectRatioPreset(preset);
            }
          },
          items: AspectRatioPreset.values.map((preset) {
            return DropdownMenuItem(
              value: preset,
              child: Text(preset.label),
            );
          }).toList(),
        ),
      ),
    );
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
    
    // Apply aspect ratio constraint if needed
    if (cropState.aspectRatioPreset != AspectRatioPreset.free && 
        cropState.aspectRatioPreset.ratio != null &&
        _dragHandle != 'center') {
      newRect = _constrainToAspectRatio(newRect, cropState.aspectRatioPreset.ratio!, _dragHandle!);
    }
    
    cropState.updateCropRect(newRect);
  }
  
  void _onPanEnd() {
    _dragStart = null;
    _initialCropRect = null;
    _dragHandle = null;
  }
  
  CropRect _constrainToAspectRatio(CropRect rect, double targetRatio, String handle) {
    final width = rect.width;
    final height = rect.height;
    
    if (handle.contains('left') || handle.contains('right')) {
      // Width changed, adjust height
      final newHeight = width / targetRatio;
      if (handle.contains('top')) {
        return rect.copyWith(top: rect.bottom - newHeight);
      } else if (handle.contains('bottom')) {
        return rect.copyWith(bottom: rect.top + newHeight);
      } else {
        // Just left or right edge
        final heightDiff = newHeight - height;
        return rect.copyWith(
          top: rect.top - heightDiff / 2,
          bottom: rect.bottom + heightDiff / 2,
        );
      }
    } else {
      // Height changed, adjust width
      final newWidth = height * targetRatio;
      if (handle.contains('left')) {
        return rect.copyWith(left: rect.right - newWidth);
      } else if (handle.contains('right')) {
        return rect.copyWith(right: rect.left + newWidth);
      } else {
        // Just top or bottom edge
        final widthDiff = newWidth - width;
        return rect.copyWith(
          left: rect.left - widthDiff / 2,
          right: rect.right + widthDiff / 2,
        );
      }
    }
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