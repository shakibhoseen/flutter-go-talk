import 'dart:io';

import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_sync_coordinator.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/feature/group/data/group_repo_imp.dart';
import 'package:whatsapp_flutter_go/feature/group/data/group_repository.dart';
import '../model/group_member.dart';

class GroupInfoData {
  final Conversation conversation;
  final List<GroupMember> members;
  final bool isActionLoading;
  final int? activeMemberId;

  const GroupInfoData({
    required this.conversation,
    this.members = const [],
    this.isActionLoading = false,
    this.activeMemberId,
  });

  GroupInfoData copyWith({
    Conversation? conversation,
    List<GroupMember>? members,
    bool? isActionLoading,
    int? activeMemberId,
    bool clearActiveMemberId = false,
  }) {
    return GroupInfoData(
      conversation: conversation ?? this.conversation,
      members: members ?? this.members,
      isActionLoading: isActionLoading ?? this.isActionLoading,
      activeMemberId:
          clearActiveMemberId ? null : (activeMemberId ?? this.activeMemberId),
    );
  }
}

class GroupInfoBloc extends SimpleBlocParent<GroupInfoData> {
  final GroupRepository _repo;
  Conversation _conversation;
  final int? Function()? currentUserIdProvider;
  bool _isActionInProgress = false;

  GroupInfoBloc(
    Conversation initialData, {
    GroupRepository? repo,
    bool autoLoad = true,
    this.currentUserIdProvider,
  })  : _conversation = initialData,
        _repo = repo ?? GroupRepoImp() {
    setFunction(
      attach: (_) async {
        final members = await _repo.getGroupMembers(_conversation.id);
        return GroupInfoData(
          conversation: _conversation,
          members: members,
        );
      },
    );

    if (autoLoad) {
      execute();
    }
  }

  Conversation get conversation => _conversation;

  int? get currentUserId =>
      (currentUserIdProvider ?? () => AuthSession.tokens?.user?.id)();

  List<GroupMember> get members {
    final s = state;
    if (s is SuccessState<GroupInfoData>) {
      return s.data.members;
    }
    return const [];
  }

  GroupMember? get currentMember {
    final uid = currentUserId;
    if (uid == null) return null;
    return members.cast<GroupMember?>().firstWhere(
      (m) => m?.id == uid,
      orElse: () => null,
    );
  }

  bool get isCurrentMemberAdmin => currentMember?.isAdmin ?? false;

  int get adminCount => members.where((m) => m.isAdmin).length;

  bool get isOnlyAdmin => isCurrentMemberAdmin && adminCount <= 1;

  bool get canLeaveGroup => !isOnlyAdmin;

  bool canRemoveMember(GroupMember member) {
    if (!isCurrentMemberAdmin) return false;
    if (member.id == currentUserId) return false;
    return true;
  }

  bool get isActionInProgress => _isActionInProgress;

  void _updateActionState({
    required bool isLoading,
    int? activeMemberId,
    List<GroupMember>? members,
  }) {
    final s = state;
    if (s is SuccessState<GroupInfoData>) {
      emitSuccess(
        s.data.copyWith(
          isActionLoading: isLoading,
          activeMemberId: activeMemberId,
          clearActiveMemberId: activeMemberId == null,
          members: members,
        ),
      );
    }
  }

  Future<void> loadMembers() async {
    final settled = stream.firstWhere(
      (s) => s is SuccessState<GroupInfoData> || s is ErrorState,
    );
    execute();
    await settled;
  }

  Future<void> addMember(int userId) async {
    if (_isActionInProgress) return;
    _isActionInProgress = true;
    _updateActionState(isLoading: true, activeMemberId: userId);
    try {
      await _repo.addGroupMember(
        conversationId: _conversation.id,
        userId: userId,
      );
      final fresh = await _repo.getGroupMembers(_conversation.id);
      _updateActionState(isLoading: false, members: fresh);
    } catch (e) {
      _updateActionState(isLoading: false);
      rethrow;
    } finally {
      _isActionInProgress = false;
    }
  }

  Future<void> removeMember(int userId) async {
    if (_isActionInProgress) return;
    _isActionInProgress = true;
    _updateActionState(isLoading: true, activeMemberId: userId);
    try {
      await _repo.removeGroupMember(
        conversationId: _conversation.id,
        userId: userId,
      );
      final fresh = await _repo.getGroupMembers(_conversation.id);
      _updateActionState(isLoading: false, members: fresh);
    } catch (e) {
      _updateActionState(isLoading: false);
      rethrow;
    } finally {
      _isActionInProgress = false;
    }
  }

  Future<void> leaveGroup() async {
    final uid = currentUserId;
    if (uid == null || uid <= 0) {
      throw Exception('Current user not found');
    }
    if (isOnlyAdmin) {
      throw Exception('Cannot leave group as the only admin');
    }
    if (_isActionInProgress) return;
    _isActionInProgress = true;
    _updateActionState(isLoading: true, activeMemberId: uid);
    try {
      await _repo.removeGroupMember(
        conversationId: _conversation.id,
        userId: uid,
      );
      ChatSyncCoordinator.instance.triggerConversationRemoved(_conversation.id);
      ChatSyncCoordinator.instance.triggerConversationsSync();
    } catch (e) {
      _updateActionState(isLoading: false);
      rethrow;
    } finally {
      _isActionInProgress = false;
    }
  }

  Future<void> uploadGroupAvatar(File imageFile) async {
    final avatarUrl = await _repo.updateGroupAvatar(_conversation.id, imageFile);
    if (!avatarUrl.contains('failed')) {
      _conversation = _conversation.copyWith(avatarUrl: avatarUrl);
      final currentMembers = members;
      emitSuccess(
        GroupInfoData(
          conversation: _conversation,
          members: currentMembers,
        ),
      );
    }
  }
}
