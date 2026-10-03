import 'dart:io';
import 'package:dio/dio.dart';
import 'package:whatsapp_flutter_go/core/state/global_data_api.dart';

import 'group_repository.dart';

class GroupRepoImp implements GroupRepository {
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
}
