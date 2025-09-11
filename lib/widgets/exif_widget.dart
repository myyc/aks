import 'package:flutter/material.dart';
import '../models/exif_metadata.dart';
import '../theme/text_styles.dart';

class ExifWidget extends StatelessWidget {
  final ExifMetadata? exif;
  final bool showDetails;
  final VoidCallback? onToggleDetails;

  const ExifWidget({
    Key? key,
    required this.exif,
    this.showDetails = false,
    this.onToggleDetails,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (exif == null || !exif!.hasData) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Camera Info',
                style: AppTextStyles.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onToggleDetails != null)
                GestureDetector(
                  onTap: onToggleDetails,
                  child: Icon(
                    showDetails ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Always visible info
          _buildInfoRow('Camera', exif!.cameraName),
          if (exif!.lensName != 'Unknown')
            _buildInfoRow('Lens', exif!.lensName),
          _buildInfoRow('ISO', exif!.isoSpeed?.toString() ?? ''),
          
          // Detailed info (collapsible)
          if (showDetails) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            const SizedBox(height: 12),
            
            // Exposure settings
            if (exif!.aperture != null || exif!.shutterSpeed != null) ...[
              _buildSectionHeader('Exposure'),
              if (exif!.aperture != null)
                _buildInfoRow('Aperture', exif!.formattedAperture),
              if (exif!.shutterSpeed != null)
                _buildInfoRow('Shutter Speed', exif!.formattedShutterSpeed),
              if (exif!.exposureCompensation != null)
                _buildInfoRow('Exposure Comp', '${exif!.exposureCompensation!.toStringAsFixed(1)} EV'),
              const SizedBox(height: 12),
            ],
            
            // Focal length
            if (exif!.focalLength != null) ...[
              _buildSectionHeader('Lens'),
              _buildInfoRow('Focal Length', exif!.formattedFocalLength),
              const SizedBox(height: 12),
            ],
            
            // Date/time
            if (exif!.dateTime != null) ...[
              _buildSectionHeader('Capture Date'),
              _buildInfoRow('Date/Time', exif!.formattedDate),
              const SizedBox(height: 12),
            ],
            
            // Advanced settings
            if (exif!.exposureProgram != null || 
                exif!.exposureMode != null || 
                exif!.meteringMode != null) ...[
              _buildSectionHeader('Camera Settings'),
              if (exif!.exposureProgram != null)
                _buildInfoRow('Exposure Program', exif!.exposureProgramName),
              if (exif!.exposureMode != null)
                _buildInfoRow('Exposure Mode', exif!.exposureModeName),
              if (exif!.meteringMode != null)
                _buildInfoRow('Metering Mode', exif!.meteringModeName),
              const SizedBox(height: 12),
            ],
            
            // Other info
            if (exif!.software != null || exif!.whiteBalance != null) ...[
              _buildSectionHeader('Other'),
              if (exif!.software != null)
                _buildInfoRow('Software', exif!.software!),
              if (exif!.whiteBalance != null)
                _buildInfoRow('White Balance', exif!.whiteBalance.toString()),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: AppTextStyles.inter(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.inter(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}