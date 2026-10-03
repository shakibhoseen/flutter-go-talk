import 'dart:io';

abstract class GroupRepository {
   Future<String> updateGroupAvatar(String conversationId, File imageFile);
}
