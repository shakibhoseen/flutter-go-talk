import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/chat_routes.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';

import '../model/chat_user.dart';
import '../model/conversation.dart';
import 'view_model/chat_view_model.dart';
import 'widgets/chat_user_tile.dart';

/// Every user, to start a new chat — `hk`'s `UserPage`.
class UserPage extends StatefulWidget {
  const UserPage({super.key, required this.viewModel});

  final ChatViewModel viewModel;

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final Set<String> _loadingUserIds = <String>{};
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

  Future<void> _startDirectChat(ChatUser user) async {
    final userIdInt = int.tryParse(user.id);
    if (userIdInt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid user ID')),
      );
      return;
    }

    // Duplicate request guard
    if (_loadingUserIds.contains(user.id)) return;

    setState(() {
      _loadingUserIds.add(user.id);
    });

    try {
      final convId = await widget.viewModel.repository.getOrCreateDirectConversation(userIdInt);

      if (!mounted) return;

      final conversation = Conversation(
        id: convId,
        type: 'direct',
        title: user.name,
        avatarUrl: user.avatarUrl.isNotEmpty ? user.avatarUrl : null,
        otherUserId: userIdInt,
        createdAt: DateTime.now(),
      );

      NavigationService.navigateToWithObject(ChatRoutes.inbox, conversation);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start chat: ${e.toString().replaceAll('Exception: ', '')}'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _startDirectChat(user),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingUserIds.remove(user.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Pill Search Bar
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
                hintText: 'Search contacts...',
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
          child: widget.viewModel.allUsersBloc.build(
            builder: (context, state) {
              if (state is ErrorState) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(state.message.isNotEmpty ? state.message : 'Failed to load users'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => widget.viewModel.allUsersBloc.execute(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              if (state is! SuccessState<List<ChatUser>>) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
              var users = state.data;
              if (_filter.isNotEmpty) {
                users = users
                    .where((u) =>
                        u.name.toLowerCase().contains(_filter) ||
                        (u.email ?? '').toLowerCase().contains(_filter))
                    .toList();
              }
              if (users.isEmpty) {
                return Center(
                  child: Text(
                    _filter.isNotEmpty ? 'No contacts found' : 'No users found',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.neutralColor.shade500,
                    ),
                  ),
                );
              }
              return ListView.separated(
                itemCount: users.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  thickness: 0.8,
                  indent: 80,
                  endIndent: 16,
                  color: AppColors.neutralColor.shade100,
                ),
                itemBuilder: (context, index) {
                  final user = users[index];
                  final isLoading = _loadingUserIds.contains(user.id);
                  return Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      ChatUserTile(
                        user: user,
                        onTap: () => _startDirectChat(user),
                      ),
                      if (isLoading)
                        const Positioned(
                          right: 16,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                    ],
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
