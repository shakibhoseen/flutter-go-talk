import 'dart:io';
import 'package:dio/dio.dart';
import 'package:whatsapp_flutter_go/core/db/network/chat_endpoints.dart';
import 'package:whatsapp_flutter_go/core/state/global_data_api.dart';

import '../model/group_member.dart';
import 'group_repository.dart';

class GroupRepoImp implements GroupRepository {
  @override
  Future<List<GroupMember>> getGroupMembers(String conversationId) async {
    final response = await GlobalDataApi.instance.getResponse(
      url: ChatEndpoints.conversationMembers(conversationId),
    );

    final List<dynamic> list;
    if (response is List) {
      list = response;
    } else if (response is Map) {
      final members = response['members'] ?? response['data'];
      list = members is List ? members : const [];
    } else {
      list = const [];
    }

    return list
        .whereType<Map>()
        .map((m) => GroupMember.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  @override
  Future<String> createGroup({
    required String title,
    required List<int> memberIds,
  }) async {
    final response = await GlobalDataApi.instance.postResponse(
      url: ChatEndpoints.groupConversation(),
      data: {
        'title': title,
        'member_ids': memberIds,
      },
    );
    final map = switch (response) {
      final Map<String, dynamic> m => m,
      final Map m => Map<String, dynamic>.from(m),
      _ => null,
    };
    final convId = map?['conversation_id']?.toString();
    if (convId == null || convId.isEmpty) {
      throw Exception('Failed to get group conversation ID from server');
    }
    return convId;
  }

  @override
  Future<String> updateGroupAvatar(String conversationId, File imageFile) async {
    final dataAPi = GlobalDataApi.instance;
    
    final formData = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(imageFile.path, filename: imageFile.path.split('/').last),
    });

    final response = await dataAPi.putResponse(
      url: 'conversations/$conversationId/avatar',
      data: formData,
    );
    try {
      return await Future.value(
        response?['avatar_url'] ?? 'Avatar updated successfully',
      );
    } catch (e) {
      return await Future.value('Data parsed failed , but updated');
    }
  }

  @override
  Future<void> addGroupMember({
    required String conversationId,
    required int userId,
  }) async {
    await GlobalDataApi.instance.postResponse(
      url: ChatEndpoints.conversationMembers(conversationId),
      data: {
        'user_id': userId,
        'target_user_id': userId,
      },
    );
  }

  @override
  Future<void> removeGroupMember({
    required String conversationId,
    required int userId,
  }) async {
    await GlobalDataApi.instance.deleteResponse(
      url: ChatEndpoints.conversationMember(conversationId, userId),
    );
  }
}
