import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:provider/provider.dart';
import '../theme/text_styles.dart';
import '../models/image_state.dart';
import '../services/file_service.dart';

class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return WindowTitleBarBox(
      child: Container(
        height: 48,
        color: const Color(0xFF0F0F0F), // Very dark like nhac
        child: Row(
          children: [
            // Hamburger menu (keeping for now, will remove in modernization)
            _buildHamburgerMenu(context),
            // Title - properly centered
            Expanded(
              child: MoveWindow(
                child: Center(
                  child: Text(
                    'AKS',
                    style: AppTextStyles.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ),
            // Window controls
            _buildWindowControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildHamburgerMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu, color: Colors.white54, size: 20),
      color: const Color(0xFF1A1A1A),
      onSelected: (value) {
        if (value == 'open') {
          _openImage(context);
        }
      },
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.folder_open, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text('Open RAW Image', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWindowControls() {
    return Row(
      children: [
        MinimizeWindowButton(
          colors: WindowButtonColors(
            iconNormal: Colors.white70,
            mouseOver: const Color(0xFF404040),
            mouseDown: const Color(0xFF202020),
            iconMouseOver: Colors.white,
            iconMouseDown: Colors.white54,
          ),
        ),
        MaximizeWindowButton(
          colors: WindowButtonColors(
            iconNormal: Colors.white70,
            mouseOver: const Color(0xFF404040),
            mouseDown: const Color(0xFF202020),
            iconMouseOver: Colors.white,
            iconMouseDown: Colors.white54,
          ),
        ),
        CloseWindowButton(
          colors: WindowButtonColors(
            iconNormal: Colors.white70,
            mouseOver: const Color(0xFFD32F2F),
            mouseDown: const Color(0xFFB71C1C),
            iconMouseOver: Colors.white,
            iconMouseDown: Colors.white54,
          ),
        ),
      ],
    );
  }

  Future<void> _openImage(BuildContext context) async {
    final imageState = Provider.of<ImageState>(context, listen: false);
    
    try {
      // Use the new file service with XDG portal support
      final filePath = await FileService.pickRawImage();
      
      if (filePath != null) {
        try {
          await imageState.loadImage(filePath);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to open RAW file: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error in _openImage: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}