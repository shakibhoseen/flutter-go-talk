import 'dart:io';

import '../model/group_member.dart';

abstract class GroupRepository {
   Future<String> updateGroupAvatar(String conversationId, File imageFile);

   Future<String> createGroup({
     required String title,
     required List<int> memberIds,
   });

   Future<List<GroupMember>> getGroupMembers(String conversationId);

   Future<void> addGroupMember({
     required String conversationId,
     required int userId,
   });

   Future<void> removeGroupMember({
     required String conversationId,
     required int userId,
   });
}
