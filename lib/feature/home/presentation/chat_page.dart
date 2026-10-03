import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/chat_routes.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';

import '../model/conversation.dart';
import 'view_model/chat_view_model.dart';
import 'widgets/conversation_tile.dart';

/// Conversation list — `hk`'s `ChatPage`, backed by the real
/// `GET /conversations` call and reordered live from [ChatViewModel]'s
/// socket handling instead of a Firebase `ChangeNotifier`.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.viewModel});

  final ChatViewModel viewModel;

  void onTap(Conversation conversation) {
    NavigationService.navigateToWithObject(ChatRoutes.inbox, conversation);
  }

  @override
  Widget build(BuildContext context) {
    return viewModel.conversationsBloc.build(
      builder: (context, state) {
        if (state is ErrorState) {
          return Center(child: Text(state.message));
        }
        if (state is! SuccessState<List<Conversation>>) {
          return const Center(child: CircularProgressIndicator());
        }
        final conversations = state.data;
        if (conversations.isEmpty) {
          return const Center(child: Text('No conversations yet'));
        }
        return ListView.separated(
          itemCount: conversations.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final conversation = conversations[index];
            return ConversationTile(
              conversation: conversation,
              onTap: () => onTap(conversation),
            );
          },
        );
      },
    );
  }
}
