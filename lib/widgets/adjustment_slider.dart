import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/text_styles.dart';

class AdjustmentSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Function(double) onChanged;
  final VoidCallback? onReset;
  final int decimals;
  final String? suffix;
  final double? neutralValue; // For values where neutral isn't 0 (e.g., temperature)
  
  const AdjustmentSlider({
    Key? key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onReset,
    this.decimals = 0,
    this.suffix,
    this.neutralValue,
  }) : super(key: key);
  
  @override
  State<AdjustmentSlider> createState() => _AdjustmentSliderState();
}

class _AdjustmentSliderState extends State<AdjustmentSlider> {
  late TextEditingController _controller;
  late double _currentValue;
  Timer? _debounceTimer;
  
  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = TextEditingController(text: _formatValue(_currentValue));
  }
  
  @override
  void didUpdateWidget(AdjustmentSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _currentValue) {
      _currentValue = widget.value;
      _controller.text = _formatValue(_currentValue);
    }
  }
  
  String _formatValue(double value) {
    final formatted = value.toStringAsFixed(widget.decimals);
    return widget.suffix != null ? '$formatted${widget.suffix}' : formatted;
  }
  
  void _handleSliderChange(double value) {
    setState(() {
      _currentValue = value;
      _controller.text = _formatValue(value);
    });
    
    // Cancel previous timer if still pending
    _debounceTimer?.cancel();
    
    // Start new timer to debounce the actual processing
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      widget.onChanged(value);
    });
  }
  
  void _handleTextChange(String text) {
    // Remove suffix if present
    if (widget.suffix != null) {
      text = text.replaceAll(widget.suffix!, '');
    }
    
    final value = double.tryParse(text);
    if (value != null) {
      final clampedValue = value.clamp(widget.min, widget.max);
      setState(() {
        _currentValue = clampedValue;
      });
      
      // Cancel previous timer if still pending
      _debounceTimer?.cancel();
      
      // Start new timer to debounce the actual processing
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        widget.onChanged(clampedValue);
      });
    }
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final neutralPoint = widget.neutralValue ?? 0;
    final isNeutral = (_currentValue - neutralPoint).abs() < 0.01;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label and value
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label,
                style: AppTextStyles.inter(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  // Text input for precise value
                  SizedBox(
                    width: 60,
                    height: 24,
                    child: TextField(
                      controller: _controller,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.inter(
                        color: isNeutral ? Colors.white54 : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(
                            color: Colors.white24,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(
                            color: Colors.white24,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(
                            color: Colors.white38,
                            width: 1,
                          ),
                        ),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^-?\d*\.?\d*'),
                        ),
                      ],
                      onSubmitted: _handleTextChange,
                      onChanged: _handleTextChange,
                    ),
                  ),
                  // Reset button
                  if (widget.onReset != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      color: isNeutral ? Colors.white24 : Colors.white54,
                      onPressed: () {
                        widget.onReset!();
                      },
                      tooltip: 'Reset',
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Slider
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white54,
              inactiveTrackColor: Colors.white24,
              thumbColor: isNeutral ? Colors.white54 : Colors.white,
              overlayColor: Colors.white.withOpacity(0.1),
            ),
            child: Slider(
              value: _currentValue,
              min: widget.min,
              max: widget.max,
              onChanged: _handleSliderChange,
            ),
          ),
        ],
      ),
    );
  }
}