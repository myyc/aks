import 'package:flutter/material.dart';
import '../theme/text_styles.dart';
import '../services/export_service.dart';

class ExportDialog extends StatefulWidget {
  final int? imageWidth;
  final int? imageHeight;
  
  const ExportDialog({
    Key? key,
    this.imageWidth,
    this.imageHeight,
  }) : super(key: key);

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  ExportFormat _selectedFormat = ExportFormat.jpeg;
  double _jpegQuality = 90;
  
  // Size options
  String _sizeOption = 'original'; // original, half, quarter, custom
  int _customMaxDimension = 2048; // Max dimension in pixels for custom size
  
  // Framing options
  bool _showFramingOptions = false;
  String _frameType = 'none'; // none, square, border
  String _frameColor = 'black'; // black, white
  double _borderWidthPercentage = 5; // Border as percentage of max dimension (max 20%)

  // Helper to calculate dimensions
  String _getDimensionText(double scale) {
    if (widget.imageWidth == null || widget.imageHeight == null) {
      return '';
    }
    final newWidth = (widget.imageWidth! * scale).round();
    final newHeight = (widget.imageHeight! * scale).round();
    return '${newWidth}×${newHeight} px';
  }
  
  // Helper to calculate custom scale based on max dimension
  double _getCustomScale() {
    if (widget.imageWidth == null || widget.imageHeight == null) {
      return 1.0;
    }
    final maxDim = widget.imageWidth! > widget.imageHeight! ? widget.imageWidth! : widget.imageHeight!;
    return _customMaxDimension / maxDim;
  }
  
  // Helper to get actual border width in pixels
  int _getBorderWidthPixels() {
    if (widget.imageWidth == null || widget.imageHeight == null) {
      return 20;
    }
    
    // Get the max dimension after any scaling
    double scale = 1.0;
    if (_sizeOption == 'half') scale = 0.5;
    else if (_sizeOption == 'quarter') scale = 0.25;
    else if (_sizeOption == 'custom') scale = _getCustomScale();
    
    final scaledWidth = (widget.imageWidth! * scale).round();
    final scaledHeight = (widget.imageHeight! * scale).round();
    final maxDim = scaledWidth > scaledHeight ? scaledWidth : scaledHeight;
    
    return (maxDim * _borderWidthPercentage / 100).round();
  }
  
  @override
  void initState() {
    super.initState();
    // Initialize custom max dimension to half of the largest dimension
    if (widget.imageWidth != null && widget.imageHeight != null) {
      final maxDim = widget.imageWidth! > widget.imageHeight! ? widget.imageWidth! : widget.imageHeight!;
      _customMaxDimension = (maxDim / 2).round();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: 450,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              'Export Image',
              style: AppTextStyles.inter(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            
            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Format selection
                    Text(
              'FORMAT',
              style: AppTextStyles.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            
            // Format radio buttons
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  RadioListTile<ExportFormat>(
                    title: Text(
                      'JPEG',
                      style: AppTextStyles.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Smaller file size, adjustable quality',
                      style: AppTextStyles.inter(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    value: ExportFormat.jpeg,
                    groupValue: _selectedFormat,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (value) {
                      setState(() {
                        _selectedFormat = value!;
                      });
                    },
                  ),
                  const Divider(
                    color: Color(0xFF2A2A2A),
                    height: 1,
                  ),
                  RadioListTile<ExportFormat>(
                    title: Text(
                      'PNG',
                      style: AppTextStyles.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Lossless compression, larger file size',
                      style: AppTextStyles.inter(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    value: ExportFormat.png,
                    groupValue: _selectedFormat,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (value) {
                      setState(() {
                        _selectedFormat = value!;
                      });
                    },
                  ),
                ],
              ),
            ),
            
            // Quality slider (only for JPEG)
            if (_selectedFormat == ExportFormat.jpeg) ...[
              const SizedBox(height: 24),
              Text(
                'QUALITY',
                style: AppTextStyles.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white38,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'JPEG Quality',
                          style: AppTextStyles.inter(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${_jpegQuality.round()}%',
                          style: AppTextStyles.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        activeTrackColor: const Color(0xFF6366F1),
                        inactiveTrackColor: Colors.white24,
                        thumbColor: const Color(0xFF6366F1),
                        overlayColor: const Color(0xFF6366F1).withOpacity(0.2),
                      ),
                      child: Slider(
                        value: _jpegQuality,
                        min: 10,
                        max: 100,
                        divisions: 9,
                        onChanged: (value) {
                          setState(() {
                            _jpegQuality = value;
                          });
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Smaller file',
                          style: AppTextStyles.inter(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'Better quality',
                          style: AppTextStyles.inter(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Size options
            Text(
              'SIZE',
              style: AppTextStyles.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: Row(
                      children: [
                        Text(
                          'Original size',
                          style: AppTextStyles.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_getDimensionText(1.0).isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            _getDimensionText(1.0),
                            style: AppTextStyles.inter(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    value: 'original',
                    groupValue: _sizeOption,
                    activeColor: const Color(0xFF6366F1),
                    dense: true,
                    onChanged: (value) {
                      setState(() {
                        _sizeOption = value!;
                      });
                    },
                  ),
                  const Divider(color: Color(0xFF2A2A2A), height: 1),
                  RadioListTile<String>(
                    title: Row(
                      children: [
                        Text(
                          'Half size',
                          style: AppTextStyles.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_getDimensionText(0.5).isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            _getDimensionText(0.5),
                            style: AppTextStyles.inter(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    value: 'half',
                    groupValue: _sizeOption,
                    activeColor: const Color(0xFF6366F1),
                    dense: true,
                    onChanged: (value) {
                      setState(() {
                        _sizeOption = value!;
                      });
                    },
                  ),
                  const Divider(color: Color(0xFF2A2A2A), height: 1),
                  RadioListTile<String>(
                    title: Row(
                      children: [
                        Text(
                          'Quarter size',
                          style: AppTextStyles.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_getDimensionText(0.25).isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            _getDimensionText(0.25),
                            style: AppTextStyles.inter(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    value: 'quarter',
                    groupValue: _sizeOption,
                    activeColor: const Color(0xFF6366F1),
                    dense: true,
                    onChanged: (value) {
                      setState(() {
                        _sizeOption = value!;
                      });
                    },
                  ),
                  const Divider(color: Color(0xFF2A2A2A), height: 1),
                  RadioListTile<String>(
                    title: Text(
                      'Custom size',
                      style: AppTextStyles.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    value: 'custom',
                    groupValue: _sizeOption,
                    activeColor: const Color(0xFF6366F1),
                    dense: true,
                    onChanged: (value) {
                      setState(() {
                        _sizeOption = value!;
                      });
                    },
                  ),
                  if (_sizeOption == 'custom')
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Max dimension',
                                style: AppTextStyles.inter(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${_customMaxDimension}px',
                                    style: AppTextStyles.inter(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_getDimensionText(_getCustomScale()).isNotEmpty)
                                    Text(
                                      _getDimensionText(_getCustomScale()),
                                      style: AppTextStyles.inter(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor: const Color(0xFF6366F1),
                              inactiveTrackColor: Colors.white24,
                              thumbColor: const Color(0xFF6366F1),
                              overlayColor: const Color(0xFF6366F1).withOpacity(0.2),
                            ),
                            child: Slider(
                              value: _customMaxDimension.toDouble(),
                              min: 256,
                              max: widget.imageWidth != null && widget.imageHeight != null 
                                  ? (widget.imageWidth! > widget.imageHeight! 
                                      ? widget.imageWidth! : widget.imageHeight!).toDouble()
                                  : 4096,
                              divisions: 50,
                              onChanged: (value) {
                                setState(() {
                                  _customMaxDimension = value.round();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Framing options (collapsible)
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                title: Text(
                  'FRAMING (OPTIONAL)',
                  style: AppTextStyles.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white38,
                    letterSpacing: 0.8,
                  ),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: _showFramingOptions,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _showFramingOptions = expanded;
                  });
                },
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Frame type
                        RadioListTile<String>(
                          title: Text(
                            'No frame',
                            style: AppTextStyles.inter(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          value: 'none',
                          groupValue: _frameType,
                          activeColor: const Color(0xFF6366F1),
                          dense: true,
                          onChanged: (value) {
                            setState(() {
                              _frameType = value!;
                            });
                          },
                        ),
                        const Divider(color: Color(0xFF2A2A2A), height: 1),
                        RadioListTile<String>(
                          title: Text(
                            'Pad to square',
                            style: AppTextStyles.inter(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            'Add bands to make square',
                            style: AppTextStyles.inter(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          value: 'square',
                          groupValue: _frameType,
                          activeColor: const Color(0xFF6366F1),
                          onChanged: (value) {
                            setState(() {
                              _frameType = value!;
                            });
                          },
                        ),
                        const Divider(color: Color(0xFF2A2A2A), height: 1),
                        RadioListTile<String>(
                          title: Text(
                            'Uniform border',
                            style: AppTextStyles.inter(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            'Add border on all sides',
                            style: AppTextStyles.inter(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          value: 'border',
                          groupValue: _frameType,
                          activeColor: const Color(0xFF6366F1),
                          onChanged: (value) {
                            setState(() {
                              _frameType = value!;
                            });
                          },
                        ),
                        
                        // Frame color and border width
                        if (_frameType != 'none') ...[
                          const Divider(color: Color(0xFF2A2A2A), height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Color selection
                                Row(
                                  children: [
                                    Text(
                                      'Color:',
                                      style: AppTextStyles.inter(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    ChoiceChip(
                                      label: Text(
                                        'Black',
                                        style: AppTextStyles.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      selected: _frameColor == 'black',
                                      selectedColor: const Color(0xFF6366F1),
                                      backgroundColor: const Color(0xFF2A2A2A),
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(() {
                                            _frameColor = 'black';
                                          });
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    ChoiceChip(
                                      label: Text(
                                        'White',
                                        style: AppTextStyles.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      selected: _frameColor == 'white',
                                      selectedColor: const Color(0xFF6366F1),
                                      backgroundColor: const Color(0xFF2A2A2A),
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(() {
                                            _frameColor = 'white';
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                
                                // Border width (only for border type)
                                if (_frameType == 'border') ...[
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Border width',
                                        style: AppTextStyles.inter(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        '${_getBorderWidthPixels()}px (${_borderWidthPercentage.toStringAsFixed(1)}%)',
                                        style: AppTextStyles.inter(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                      ),
                                      overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 12,
                                      ),
                                      activeTrackColor: const Color(0xFF6366F1),
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: const Color(0xFF6366F1),
                                      overlayColor: const Color(0xFF6366F1).withOpacity(0.2),
                                    ),
                                    child: Slider(
                                      value: _borderWidthPercentage,
                                      min: 1,
                                      max: 20,
                                      divisions: 38,
                                      onChanged: (value) {
                                        setState(() {
                                          _borderWidthPercentage = value;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(null);
                  },
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.inter(
                      color: Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    // Calculate resize percentage
                    double? resizePercentage;
                    if (_sizeOption == 'half') {
                      resizePercentage = 0.5;
                    } else if (_sizeOption == 'quarter') {
                      resizePercentage = 0.25;
                    } else if (_sizeOption == 'custom') {
                      resizePercentage = _getCustomScale();
                    }
                    
                    Navigator.of(context).pop({
                      'format': _selectedFormat,
                      'quality': _jpegQuality.round(),
                      'resizePercentage': resizePercentage,
                      'frameType': _frameType,
                      'frameColor': _frameColor,
                      'borderWidth': _getBorderWidthPixels(),
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Export',
                    style: AppTextStyles.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}