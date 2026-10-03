import 'package:flutter/material.dart';
import '../data/model/call_status.dart';
import 'view_model/call_view_model.dart';
import 'widgets/call_action_buttons.dart';
import 'widgets/call_user_info_widget.dart';
import 'widgets/call_video_renderers.dart';

class CallScreen extends StatefulWidget {
  final int targetUserId;
  final String userName;
  final String avatarUrl;
  final bool isVideo;
  final bool isIncoming;
  final Map<String, dynamic>? offerSdp;

  const CallScreen({
    super.key,
    required this.targetUserId,
    required this.userName,
    this.avatarUrl = '',
    this.isVideo = false,
    this.isIncoming = false,
    this.offerSdp,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = CallViewModel();
    _viewModel.addListener(_handleCallStateChange);
    _viewModel.initCall(
      targetUserId: widget.targetUserId,
      isVideo: widget.isVideo,
      isIncoming: widget.isIncoming,
      offerSdp: widget.offerSdp,
    );
  }

  void _handleCallStateChange() {
    if (_viewModel.status == CallStatus.ended && mounted) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  void _onEndCall() {
    _viewModel.endCall();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_handleCallStateChange);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.blueGrey.shade900,
          body: Stack(
            children: [
              // Video streams background (if video call)
              CallVideoRenderers(viewModel: _viewModel),

              // Overlay content
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    // User info & call duration
                    CallUserInfoWidget(
                      userName: widget.userName,
                      avatarUrl: widget.avatarUrl,
                      status: _viewModel.status,
                      durationSeconds: _viewModel.durationSeconds,
                      isVideo: _viewModel.isVideo,
                    ),

                    const Spacer(),

                    // Action buttons
                    CallActionButtons(
                      viewModel: _viewModel,
                      onEndCall: _onEndCall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
