import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/text_styles.dart';
import '../models/image_state.dart';
import '../models/adjustments.dart';
import '../services/export_service.dart';
import 'adjustment_slider.dart';
import 'tone_curve_widget.dart';
import 'exif_widget.dart';

class TabbedSidebar extends StatefulWidget {
  const TabbedSidebar({Key? key}) : super(key: key);

  @override
  State<TabbedSidebar> createState() => _TabbedSidebarState();
}

class _TabbedSidebarState extends State<TabbedSidebar> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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

        return Container(
          width: 300,
          color: const Color(0xFF1A1A1A),
          child: Column(
            children: [
              // Tab Bar
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: AppTextStyles.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: 'ADJUSTMENTS'),
                    Tab(text: 'INFO'),
                  ],
                ),
              ),

              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Adjustments Tab
                    _buildAdjustmentsTab(
                      context,
                      imageState,
                      pipeline,
                      whiteBalance,
                      exposure,
                      contrast,
                      highlightsShadows,
                      blacksWhites,
                      satVibrance,
                      toneCurve,
                    ),
                    
                    // Info Tab
                    _buildInfoTab(imageState),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdjustmentsTab(
    BuildContext context,
    ImageState imageState,
    dynamic pipeline,
    WhiteBalanceAdjustment? whiteBalance,
    ExposureAdjustment? exposure,
    ContrastAdjustment? contrast,
    HighlightsShadowsAdjustment? highlightsShadows,
    BlacksWhitesAdjustment? blacksWhites,
    SaturationVibranceAdjustment? satVibrance,
    ToneCurveAdjustment? toneCurve,
  ) {
    return Column(
      children: [
        // Reset button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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

              // Tone Section
              _buildSection(
                'Tone',
                [
                  if (exposure != null)
                    AdjustmentSlider(
                      label: 'Exposure',
                      value: exposure.value,
                      min: -4.0,
                      max: 4.0,
                      decimals: 2,
                      onChanged: (value) {
                        pipeline.updateAdjustment(
                          exposure.copyWith(value: value),
                        );
                      },
                      onReset: () {
                        pipeline.updateAdjustment(
                          exposure.copyWith(value: 0.0),
                        );
                      },
                    ),
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

              // Presence Section
              _buildSection(
                'Presence',
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

              // Tone Curve Section
              if (toneCurve != null)
                _buildSection(
                  'Tone Curve',
                  [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ToneCurveWidget(
                        adjustment: toneCurve,
                        size: 268,
                        onChanged: (adjustment) {
                          pipeline.updateAdjustment(adjustment);
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Export buttons
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFF2A2A2A), width: 1),
            ),
          ),
          child: Column(
            children: [
              // Export button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (imageState.currentImage != null) {
                      await imageState.exportImage(
                        format: ExportFormat.jpeg,
                        jpegQuality: 90,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Export Image',
                    style: AppTextStyles.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Save sidecar button
              if (pipeline.hasAdjustments)
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
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTab(ImageState imageState) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // EXIF Information
        if (imageState.exifData != null && imageState.exifData!.hasData)
          _buildInfoSection(
            'Camera Information',
            ExifWidget(
              exif: imageState.exifData,
              showDetails: true,
              onToggleDetails: () {},
            ),
          ),

        // Image Information
        _buildInfoSection(
          'Image Details',
          _buildImageDetails(imageState),
        ),

        // File Information
        _buildInfoSection(
          'File Information',
          _buildFileDetails(imageState),
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: AppTextStyles.inter(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildInfoSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: AppTextStyles.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        content,
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildImageDetails(ImageState imageState) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Dimensions', '${imageState.originalWidth} × ${imageState.originalHeight}'),
          if (imageState.currentImage != null)
            _buildInfoRow('Display Size', '${imageState.currentImage!.width} × ${imageState.currentImage!.height}'),
          if (imageState.originalWidth != null && imageState.originalHeight != null)
            _buildInfoRow('Aspect Ratio', _getAspectRatioString(imageState.originalWidth!, imageState.originalHeight!)),
          _buildInfoRow('Color Depth', '16-bit RAW'),
        ],
      ),
    );
  }

  Widget _buildFileDetails(ImageState imageState) {
    if (imageState.currentFilePath == null) {
      return const Text('No file loaded', style: TextStyle(color: Colors.white54));
    }

    final file = File(imageState.currentFilePath!);
    return FutureBuilder<FileStat>(
      future: file.stat(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final stat = snapshot.data!;
        final fileSize = _formatFileSize(stat.size);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('File Name', imageState.currentFilePath!.split(Platform.pathSeparator).last),
              _buildInfoRow('File Size', fileSize),
              _buildInfoRow('Modified', _formatDateTime(stat.modified)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.inter(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.inter(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getAspectRatioString(int width, int height) {
    if (width == 0 || height == 0) return '';
    
    final ratio = width / height;
    if (ratio.abs() - (3 / 2) < 0.01) return '3:2';
    if (ratio.abs() - (4 / 3) < 0.01) return '4:3';
    if (ratio.abs() - (16 / 9) < 0.01) return '16:9';
    if (ratio.abs() - 1.0 < 0.01) return '1:1';
    return '${ratio.toStringAsFixed(2)}:1';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}