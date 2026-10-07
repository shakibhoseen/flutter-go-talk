import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/chat_routes.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';

import '../model/conversation.dart';
import 'view_model/chat_view_model.dart';
import 'widgets/conversation_tile.dart';

/// Conversation list — backed by `GET /conversations` with live socket updates,
/// styled with the cute modern cyan & pill search design.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.viewModel});

  final ChatViewModel viewModel;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _filter = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void onTap(Conversation conversation) {
    NavigationService.navigateToWithObject(ChatRoutes.inbox, conversation);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Pill Search Bar matching Image 1 & Image 3
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.neutralColor.shade100,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.neutralColor.shade900,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                hintText: 'Find or start a new chat',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: AppColors.neutralColor.shade400,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.neutralColor.shade400,
                ),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: widget.viewModel.conversationsBloc.build(
            builder: (context, state) {
              if (state is ErrorState) {
                return Center(child: Text(state.message));
              }
              if (state is! SuccessState<List<Conversation>>) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.cyanAccent,
                  ),
                );
              }
              var conversations = state.data;
              if (_filter.isNotEmpty) {
                conversations = conversations
                    .where((c) =>
                        c.displayTitle.toLowerCase().contains(_filter) ||
                        (c.lastMessageContent ?? '')
                            .toLowerCase()
                            .contains(_filter))
                    .toList();
              }
              if (conversations.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 56,
                        color: AppColors.neutralColor.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _filter.isNotEmpty
                            ? 'No conversations found'
                            : 'No conversations yet',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.neutralColor.shade500,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                itemCount: conversations.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  thickness: 0.8,
                  indent: 80,
                  endIndent: 16,
                  color: AppColors.neutralColor.shade100,
                ),
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  return ConversationTile(
                    conversation: conversation,
                    onTap: () => onTap(conversation),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
