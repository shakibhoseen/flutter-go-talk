import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';
import 'package:whatsapp_flutter_go/core/widgets/cute_avatar.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/view_model/chat_view_model.dart';

class CallsPage extends StatelessWidget {
  const CallsPage({super.key, required this.viewModel});

  final ChatViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Cute Active / Recent Call Card with Waveform banner (inspired by reference)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.neutralColor.shade200, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CuteAvatar(
                    name: 'Maria Fernanda',
                    size: 42,
                    isOnline: true,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Maria Fernanda',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '02:03 • HD Audio',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.onlineGreen,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.call_end_rounded,
                      color: Colors.red.shade400,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Cute audio waveform visualizer representation
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.cyanLight.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(24, (index) {
                    final heights = [
                      8.0, 14.0, 22.0, 12.0, 26.0, 18.0, 10.0, 24.0,
                      28.0, 16.0, 12.0, 20.0, 26.0, 14.0, 8.0, 18.0,
                      22.0, 10.0, 15.0, 24.0, 18.0, 12.0, 9.0, 16.0,
                    ];
                    final h = heights[index % heights.length];
                    return Container(
                      width: 3.5,
                      height: h,
                      decoration: BoxDecoration(
                        color: index < 14
                            ? AppColors.cyanAccent
                            : AppColors.cyanAccent.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text(
          'Recent Calls',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),

        // Recent call items
        _buildCallTile(
          name: 'Amazon Support',
          time: 'Today, 11:32 AM',
          isMissed: false,
          isVideo: false,
        ),
        _buildCallTile(
          name: 'Mike James',
          time: 'Yesterday, 04:15 PM',
          isMissed: true,
          isVideo: true,
        ),
        _buildCallTile(
          name: 'David Romano',
          time: 'Oct 05, 08:30 PM',
          isMissed: false,
          isVideo: false,
        ),
      ],
    );
  }

  Widget _buildCallTile({
    required String name,
    required String time,
    required bool isMissed,
    required bool isVideo,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CuteAvatar(name: name, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      isMissed
                          ? Icons.call_missed_rounded
                          : Icons.call_received_rounded,
                      size: 14,
                      color: isMissed ? Colors.red : AppColors.onlineGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.neutralColor.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              color: AppColors.cyanAccent,
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
