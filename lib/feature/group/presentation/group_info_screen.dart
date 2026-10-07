import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whatsapp_flutter_go/core/config/app_flavor_config.dart';
import 'package:whatsapp_flutter_go/core/db/network/network_service_type.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/feature/group/data/group_repository.dart';
import 'package:whatsapp_flutter_go/feature/group/model/group_member.dart';
import 'package:whatsapp_flutter_go/feature/home/data/chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/data/http_chat_repository.dart';
import 'package:whatsapp_flutter_go/feature/home/model/chat_user.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/feature/home/presentation/view_model/chat_view_model.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';
import 'package:whatsapp_flutter_go/core/widgets/cute_avatar.dart';
import 'package:whatsapp_flutter_go/feature/group/bloc/group_info_bloc.dart';

class GroupInfoScreen extends StatefulWidget {
  final Conversation conversation;
  final GroupRepository? repository;
  final ChatRepository? chatRepository;
  final ChatViewModel? chatViewModel;
  final VoidCallback? onGroupLeft;
  final int? Function()? currentUserIdProvider;

  const GroupInfoScreen({
    super.key,
    required this.conversation,
    this.repository,
    this.chatRepository,
    this.chatViewModel,
    this.onGroupLeft,
    this.currentUserIdProvider,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late final GroupInfoBloc _bloc;
  late final ChatRepository _chatRepository;
  File? _selectedImage;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _chatRepository = widget.chatRepository ?? const HttpChatRepository();
    _bloc = GroupInfoBloc(
      widget.conversation,
      repo: widget.repository,
      currentUserIdProvider: widget.currentUserIdProvider,
    );
  }

  String _getFullUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final baseUrl = AppFlavorConfig.baseUrlFor(NetworkServiceType.chat);
    return '$baseUrl/$path';
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 50,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      setState(() {
        _selectedImage = file;
      });
      try {
        await _bloc.uploadGroupAvatar(file);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update avatar: $e')),
          );
        }
      }
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddMemberSheet() async {
    final allUsers = await _chatRepository.getAllUsers();
    if (!mounted) return;

    final currentMembers = _bloc.members;
    final eligibleUsers = allUsers.where((user) {
      final uid = int.tryParse(user.id);
      return uid != null && !currentMembers.any((m) => m.id == uid);
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add Member',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                if (eligibleUsers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                      child: Text(
                        'No additional users available to add',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: eligibleUsers.length,
                      itemBuilder: (context, index) {
                        final user = eligibleUsers[index];
                        final hasAvatar = user.avatarUrl.isNotEmpty;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey.shade300,
                            backgroundImage: hasAvatar
                                ? NetworkImage(_getFullUrl(user.avatarUrl))
                                : null,
                            child: !hasAvatar
                                ? Text(
                                    user.name.isNotEmpty
                                        ? user.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(user.name),
                          subtitle: (user.bio != null && user.bio!.isNotEmpty)
                              ? Text(user.bio!)
                              : (user.email != null ? Text(user.email!) : null),
                          trailing: const Icon(Icons.add_circle_outline, color: Colors.green),
                          onTap: () => _confirmAddMember(sheetContext, user),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAddMember(BuildContext sheetContext, ChatUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Member?'),
        content: Text('Add "${user.name}" to this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (_isActionInProgress) return;
      _isActionInProgress = true;
      try {
        final userId = int.parse(user.id);
        await _bloc.addMember(userId);
        if (sheetContext.mounted) {
          Navigator.pop(sheetContext);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${user.name} added to group')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add member: $e')),
          );
        }
      } finally {
        _isActionInProgress = false;
      }
    }
  }

  Future<void> _confirmRemoveMember(GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Member?'),
        content: Text('Remove "${member.name}" from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (_isActionInProgress) return;
      _isActionInProgress = true;
      try {
        await _bloc.removeMember(member.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${member.name} removed from group')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove member: $e')),
          );
        }
      } finally {
        _isActionInProgress = false;
      }
    }
  }

  Future<void> _confirmLeaveGroup() async {
    if (_bloc.isOnlyAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot leave group as the only admin'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave Group?'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (_isActionInProgress) return;
      _isActionInProgress = true;
      try {
        await _bloc.leaveGroup();
        widget.chatViewModel?.removeConversation(widget.conversation.id);
        widget.onGroupLeft?.call();
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to leave group: $e')),
          );
        }
      } finally {
        _isActionInProgress = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
      ),
      body: _bloc.build(
        builder: (context, state) {
          if (state is LoadingState || state is InitialState) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ErrorState) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(
                      state.message.isNotEmpty
                          ? state.message
                          : 'Failed to load group info',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _bloc.loadMembers(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is! SuccessState<GroupInfoData>) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = state.data;
          final conv = data.conversation;
          final members = data.members;
          final isAdmin = _bloc.isCurrentMemberAdmin;

                  return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24),
                // Group Avatar with cute styling
                Center(
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.cyanAccent.withValues(alpha: 0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 54,
                          backgroundColor: AppColors.cyanLight,
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : (conv.avatarUrl != null
                                  ? NetworkImage(_getFullUrl(conv.avatarUrl))
                                  : null) as ImageProvider?,
                          child: _selectedImage == null && conv.avatarUrl == null
                              ? const Icon(Icons.groups_rounded, size: 54, color: AppColors.cyanDark)
                              : null,
                        ),
                      ),
                      // Camera edit button: only shown for admin
                      if (isAdmin)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _showImageSourceActionSheet,
                            child: Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: AppColors.cyanAccent,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Group Title
                Text(
                  conv.displayTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Group • ${members.length} members',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.neutralColor.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                // Members Section Header
                Container(
                  color: AppColors.neutralColor.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${members.length} members',
                        key: const Key('group_member_count'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neutralColor.shade800,
                        ),
                      ),
                      // Add Member button: only shown for admin
                      if (isAdmin)
                        TextButton.icon(
                          key: const Key('add_member_button'),
                          onPressed: data.isActionLoading ? null : _showAddMemberSheet,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.cyanDark,
                          ),
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text(
                            'Add Member',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
                // Real Members List
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final isMemberBeingRemoved =
                        data.isActionLoading && data.activeMemberId == member.id;
                    final canRemove = _bloc.canRemoveMember(member);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                      leading: CuteAvatar(
                        name: member.name,
                        imageUrl: member.avatarUrl,
                        size: 44,
                        showOnlineDot: false,
                      ),
                      title: Text(
                        member.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      subtitle: (member.bio != null && member.bio!.isNotEmpty)
                          ? Text(
                              member.bio!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.neutralColor.shade500,
                              ),
                            )
                          : (member.email.isNotEmpty
                              ? Text(
                                  member.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.neutralColor.shade500,
                                  ),
                                )
                              : null),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (member.isAdmin) ...[
                            Container(
                              key: Key('admin_badge_${member.id}'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3.5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cyanLight,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.cyanDark,
                                  width: 0.8,
                                ),
                              ),
                              child: const Text(
                                'Admin',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.cyanDark,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (canRemove)
                            isMemberBeingRemoved
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.cyanAccent,
                                    ),
                                  )
                                : IconButton(
                                    key: Key('remove_member_${member.id}'),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      color: Colors.redAccent,
                                    ),
                                    tooltip: 'Remove',
                                    onPressed: data.isActionLoading
                                        ? null
                                        : () => _confirmRemoveMember(member),
                                  ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(color: AppColors.neutralColor.shade100, height: 1),
                ),
                const SizedBox(height: 12),
                // Leave Group Option: Available to all group members
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Material(
                    color: Colors.red.shade50.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      key: const Key('leave_group_button'),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: Icon(Icons.exit_to_app_rounded, color: Colors.red.shade600),
                      title: Text(
                        'Leave Group',
                        style: TextStyle(
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: data.isActionLoading ? null : _confirmLeaveGroup,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}
