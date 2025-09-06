import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/text_styles.dart';
import '../models/image_state.dart';
import '../models/adjustments.dart';
import '../services/export_service.dart';
import 'adjustment_slider.dart';
import 'tone_curve_widget.dart';

class EditingPanel extends StatelessWidget {
  const EditingPanel({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Consumer<ImageState>(
      builder: (context, imageState, child) {
        if (!imageState.hasImage) {
          return const SizedBox.shrink();
        }
        
        final pipeline = imageState.pipeline;
        final whiteBalance = pipeline.getAdjustment<WhiteBalanceAdjustment>('white_balance');
        final exposure = pipeline.getAdjustment<ExposureAdjustment>('exposure');
        final contrast = pipeline.getAdjustment<ContrastAdjustment>('contrast');
        final highlightsShadows = pipeline.getAdjustment<HighlightsShadowsAdjustment>('highlights_shadows');
        final blacksWhites = pipeline.getAdjustment<BlacksWhitesAdjustment>('blacks_whites');
        final satVibrance = pipeline.getAdjustment<SaturationVibranceAdjustment>('saturation_vibrance');
        final toneCurve = pipeline.getAdjustment<ToneCurveAdjustment>('tone_curve');
        
        // Debug: Check if tone curve is loaded
        print('ToneCurve adjustment: ${toneCurve != null ? "loaded" : "null"}');
        
        return Container(
          width: 300,
          color: const Color(0xFF1A1A1A), // Slightly lighter than main background
          child: Column(
            children: [
              // Header
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Adjustments',
                          style: AppTextStyles.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (imageState.isProcessing) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                            ),
                          ),
                        ],
                      ],
                    ),
                    TextButton(
                      onPressed: pipeline.hasAdjustments
                          ? () async => await imageState.resetAllAdjustments()
                          : null,
                      child: Text(
                        'Reset All',
                        style: AppTextStyles.inter(
                          color: pipeline.hasAdjustments
                              ? Colors.white54
                              : Colors.white24,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Adjustments list
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // White Balance Section
                    _buildSection(
                      'White Balance',
                      [
                        if (whiteBalance != null) ...[
                          AdjustmentSlider(
                            label: 'Temperature',
                            value: whiteBalance.temperature,
                            min: 2000,
                            max: 10000,
                            decimals: 0,
                            suffix: 'K',
                            neutralValue: 5500, // Daylight
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                whiteBalance.copyWith(temperature: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                whiteBalance.copyWith(temperature: 5500),
                              );
                            },
                          ),
                          AdjustmentSlider(
                            label: 'Tint',
                            value: whiteBalance.tint,
                            min: -150,
                            max: 150,
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                whiteBalance.copyWith(tint: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                whiteBalance.copyWith(tint: 0),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                    
                    // Exposure Section
                    _buildSection(
                      'Exposure',
                      [
                        if (exposure != null)
                          AdjustmentSlider(
                            label: 'Exposure',
                            value: exposure.value,
                            min: -5,
                            max: 5,
                            decimals: 2,
                            suffix: ' EV',
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                exposure.copyWith(value: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                exposure.copyWith(value: 0),
                              );
                            },
                          ),
                      ],
                    ),
                    
                    // Tone Section
                    _buildSection(
                      'Tone',
                      [
                        if (contrast != null)
                          AdjustmentSlider(
                            label: 'Contrast',
                            value: contrast.value,
                            min: -100,
                            max: 100,
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                contrast.copyWith(value: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                contrast.copyWith(value: 0),
                              );
                            },
                          ),
                        if (highlightsShadows != null) ...[
                          AdjustmentSlider(
                            label: 'Highlights',
                            value: highlightsShadows.highlights,
                            min: -100,
                            max: 100,
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                highlightsShadows.copyWith(highlights: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                highlightsShadows.copyWith(highlights: 0),
                              );
                            },
                          ),
                          AdjustmentSlider(
                            label: 'Shadows',
                            value: highlightsShadows.shadows,
                            min: -100,
                            max: 100,
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                highlightsShadows.copyWith(shadows: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                highlightsShadows.copyWith(shadows: 0),
                              );
                            },
                          ),
                        ],
                        if (blacksWhites != null) ...[
                          AdjustmentSlider(
                            label: 'Blacks',
                            value: blacksWhites.blacks,
                            min: -100,
                            max: 100,
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                blacksWhites.copyWith(blacks: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                blacksWhites.copyWith(blacks: 0),
                              );
                            },
                          ),
                          AdjustmentSlider(
                            label: 'Whites',
                            value: blacksWhites.whites,
                            min: -100,
                            max: 100,
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                blacksWhites.copyWith(whites: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                blacksWhites.copyWith(whites: 0),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                    
                    // Tone Curve Section
                    _buildSection(
                      'Tone Curve',
                      [
                        if (toneCurve != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ToneCurveWidget(
                              adjustment: toneCurve,
                              size: 268, // Full width minus padding
                              onChanged: (value) {
                                pipeline.updateAdjustment(value);
                              },
                            ),
                          ),
                      ],
                    ),
                    
                    // Color Section
                    _buildSection(
                      'Color',
                      [
                        if (satVibrance != null) ...[
                          AdjustmentSlider(
                            label: 'Saturation',
                            value: satVibrance.saturation,
                            min: -100,
                            max: 100,
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                satVibrance.copyWith(saturation: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                satVibrance.copyWith(saturation: 0),
                              );
                            },
                          ),
                          AdjustmentSlider(
                            label: 'Vibrance',
                            value: satVibrance.vibrance,
                            min: -100,
                            max: 100,
                            onChanged: (value) {
                              pipeline.updateAdjustment(
                                satVibrance.copyWith(vibrance: value),
                              );
                            },
                            onReset: () {
                              pipeline.updateAdjustment(
                                satVibrance.copyWith(vibrance: 0),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              
              // Bottom actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF2A2A2A), width: 1),
                  ),
                ),
                child: Column(
                  children: [
                    // Save sidecar button - only if there are adjustments
                    if (pipeline.hasAdjustments) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            await imageState.savePipelineToSidecar();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Adjustments saved to sidecar file'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Save Sidecar',
                            style: AppTextStyles.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            title.toUpperCase(),
            style: AppTextStyles.inter(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...children,
        const SizedBox(height: 8),
      ],
    );
  }
}