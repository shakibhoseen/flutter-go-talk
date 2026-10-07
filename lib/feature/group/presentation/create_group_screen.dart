import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/chat_routes.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/feature/group/data/group_repo_imp.dart';
import 'package:whatsapp_flutter_go/feature/group/data/group_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_user.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';
import 'package:whatsapp_flutter_go/core/widgets/cute_avatar.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/view_model/chat_view_model.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({
    super.key,
    required this.chatViewModel,
    this.groupRepository,
  });

  final ChatViewModel chatViewModel;
  final GroupRepository? groupRepository;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  late final TextEditingController _titleController;
  final Set<int> _selectedUserIds = <int>{};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    final state = widget.chatViewModel.allUsersBloc.state;
    if (state is InitialState) {
      widget.chatViewModel.allUsersBloc.execute();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (_isLoading) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 member')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final repo = widget.groupRepository ?? GroupRepoImp();
      final convId = await repo.createGroup(
        title: title,
        memberIds: _selectedUserIds.toList(),
      );

      if (!mounted) return;

      final conversation = Conversation(
        id: convId,
        type: 'group',
        title: title,
        createdAt: DateTime.now(),
      );

      widget.chatViewModel.addOrUpdateConversation(conversation);
      widget.chatViewModel.refreshConversations();

      NavigationService.navigateToWithObject(ChatRoutes.inbox, conversation);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create group: ${e.toString().replaceAll('Exception: ', '')}'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _createGroup,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _createGroup,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: 'Create Group',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.neutralColor.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.neutralColor.shade200,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'Enter group name...',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: AppColors.neutralColor.shade400,
                  ),
                  prefixIcon: const Icon(
                    Icons.groups_rounded,
                    color: AppColors.cyanDark,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                enabled: !_isLoading,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Members',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _selectedUserIds.isNotEmpty
                        ? AppColors.cyanLight
                        : AppColors.neutralColor.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_selectedUserIds.length} selected',
                    style: TextStyle(
                      color: _selectedUserIds.isNotEmpty
                          ? AppColors.cyanDark
                          : AppColors.neutralColor.shade500,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(color: AppColors.neutralColor.shade100, height: 1),
          ),
          Expanded(
            child: widget.chatViewModel.allUsersBloc.build(
              builder: (context, state) {
                if (state is ErrorState) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(state.message.isNotEmpty
                            ? state.message
                            : 'Failed to load users'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              widget.chatViewModel.allUsersBloc.execute(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                if (state is! SuccessState<List<ChatUser>>) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.cyanAccent),
                  );
                }
                final users = state.data;
                if (users.isEmpty) {
                  return const Center(child: Text('No users found'));
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
                    final userIdInt = int.tryParse(user.id);
                    final isSelected =
                        userIdInt != null && _selectedUserIds.contains(userIdInt);
                    return CheckboxListTile(
                      activeColor: AppColors.cyanAccent,
                      checkColor: Colors.white,
                      checkboxShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      value: isSelected,
                      onChanged: _isLoading || userIdInt == null
                          ? null
                          : (bool? checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedUserIds.add(userIdInt);
                                } else {
                                  _selectedUserIds.remove(userIdInt);
                                }
                              });
                            },
                      title: Text(
                        user.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      subtitle: Text(
                        user.bio ?? user.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.neutralColor.shade500,
                        ),
                      ),
                      secondary: CuteAvatar(
                        name: user.name,
                        imageUrl: user.avatarUrl,
                        size: 46,
                        showOnlineDot: false,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyanAccent,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: _isLoading ? null : _createGroup,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check_rounded),
        label: Text(_isLoading ? 'Creating...' : 'Create Group'),
      ),
    );
  }
}
