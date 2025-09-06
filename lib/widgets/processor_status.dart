import 'package:flutter/material.dart';
import '../services/processors/processor_factory.dart';
import '../theme/text_styles.dart';

/// Widget to display current image processor status
class ProcessorStatus extends StatefulWidget {
  const ProcessorStatus({Key? key}) : super(key: key);
  
  @override
  State<ProcessorStatus> createState() => _ProcessorStatusState();
}

class _ProcessorStatusState extends State<ProcessorStatus> {
  String _processorName = 'Initializing...';
  bool _gpuAvailable = false;
  
  @override
  void initState() {
    super.initState();
    _updateStatus();
  }
  
  Future<void> _updateStatus() async {
    final name = ProcessorFactory.getCurrentProcessorName();
    final gpuAvailable = await ProcessorFactory.isGpuAvailable();
    
    if (mounted) {
      setState(() {
        _processorName = name;
        _gpuAvailable = gpuAvailable;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    
    if (_processorName.contains('Vulkan') || _processorName.contains('Metal')) {
      statusColor = Colors.green;
      statusIcon = Icons.speed; // GPU icon
    } else if (_processorName.contains('CPU')) {
      statusColor = _gpuAvailable ? Colors.orange : Colors.blue;
      statusIcon = Icons.memory; // CPU icon
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.help_outline;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            size: 14,
            color: statusColor,
          ),
          const SizedBox(width: 6),
          Text(
            _processorName,
            style: AppTextStyles.inter(
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
          if (_gpuAvailable && _processorName.contains('CPU')) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'GPU available but using CPU',
              child: Icon(
                Icons.info_outline,
                size: 12,
                color: Colors.orange,
              ),
            ),
          ],
        ],
      ),
    );
  }
}