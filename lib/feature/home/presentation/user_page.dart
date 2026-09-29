import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';

import '../model/chat_user.dart';
import '../model/conversation.dart';
import 'chat_thread_page.dart';
import 'view_model/chat_view_model.dart';
import 'widgets/chat_user_tile.dart';

/// Every user, to start a new chat — `hk`'s `UserPage`.
class UserPage extends StatelessWidget {
  const UserPage({super.key, required this.viewModel});

  final ChatViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return viewModel.allUsersBloc.build(
      builder: (context, state) {
        if (state is! SuccessState<List<ChatUser>>) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = state.data;
        if (users.isEmpty) {
          return const Center(child: Text('No users found'));
        }
        return ListView.separated(
          itemCount: users.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final user = users[index];
            return ChatUserTile(
              user: user,
              // Starting a new chat with someone who isn't a conversation
              // yet — there's no id for it until the backend creates one, so
              // this is a throwaway `Conversation` just to open the thread.
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatThreadPage(
                    conversation: Conversation(
                      id: user.id,
                      type: 'direct',
                      title: user.name,
                      createdAt: DateTime.now(),
                    ),
                    repository: viewModel.repository,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
