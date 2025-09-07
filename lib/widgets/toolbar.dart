import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/text_styles.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import '../models/image_state.dart';
import '../models/crop_state.dart';

class Toolbar extends StatelessWidget {
  final VoidCallback? onOpenImage;
  final VoidCallback? onExportImage;
  
  const Toolbar({
    Key? key,
    this.onOpenImage,
    this.onExportImage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final imageState = context.watch<ImageState>();
    final cropState = context.watch<CropState>();
    
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF2A2A2A),
            width: 1,
          ),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) {
          appWindow.startDragging();
        },
        onDoubleTap: () {
          appWindow.maximizeOrRestore();
        },
        child: Row(
          children: [
            const SizedBox(width: 6),
            // Open button
            _ToolButton(
              icon: Icons.folder_open,
              tooltip: 'Open Image (Ctrl+O)',
              isActive: false,
              onPressed: onOpenImage,
            ),
            const SizedBox(width: 8),
            // Export button
            _ToolButton(
              icon: Icons.download,
              tooltip: 'Export Image (Ctrl+E)',
              isActive: false,
              onPressed: onExportImage,
            ),
            const SizedBox(width: 8),
            // Crop tool
            _ToolButton(
              icon: Icons.crop,
              tooltip: 'Crop (C)',
              isActive: cropState.isActive,
              onPressed: imageState.hasImage ? () {
                if (cropState.isActive) {
                  cropState.cancelCropping();
                } else {
                  cropState.startCropping(imageState.pipeline.cropRect);
                }
              } : null,
            ),
            const SizedBox(width: 8),
            // Undo button
            _ToolButton(
              icon: Icons.undo,
              tooltip: 'Undo (Ctrl+Z)',
              isActive: false,
              onPressed: imageState.historyManager.canUndo ? () {
                imageState.undo();
              } : null,
            ),
            const SizedBox(width: 8),
            // Redo button
            _ToolButton(
              icon: Icons.redo,
              tooltip: 'Redo (Ctrl+Shift+Z)',
              isActive: false,
              onPressed: imageState.historyManager.canRedo ? () {
                imageState.redo();
              } : null,
            ),
            const SizedBox(width: 8),
            const Spacer(),
            // Crop indicator
            if (imageState.hasCrop && !cropState.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.crop,
                      size: 16,
                      color: const Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cropped',
                      style: TextStyle(
                        color: const Color(0xFF6366F1),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            // Window close button (not shown on macOS)
            if (!Platform.isMacOS) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    appWindow.close();
                  },
                  borderRadius: BorderRadius.circular(4),
                  hoverColor: Colors.red.withOpacity(0.2),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback? onPressed;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          hoverColor: Colors.white.withOpacity(0.1),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF6366F1).withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive ? const Color(0xFF6366F1) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 20,
                color: isActive 
                    ? const Color(0xFF6366F1) 
                    : (onPressed != null ? Colors.white70 : Colors.white30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}