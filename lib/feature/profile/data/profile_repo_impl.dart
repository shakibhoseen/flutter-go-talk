import 'package:dio/dio.dart';
import 'package:whatsapp_flutter_go/feature/profile/data/profile_repository.dart';
import 'package:whatsapp_flutter_go/feature/profile/model/avatar_request.dart';

import '../../../core/db/network/exception_handler/data_source.dart';
import '../../../core/state/global_data_api.dart';
import '../../login/model/login_response.dart';

class ProfileRepoImpl extends ProfileRepository {
  @override
  Future<User> getProfile({String? id}) async {
    final dataAPi = GlobalDataApi.instance;
    final response = await dataAPi.getResponse(url: 'users/me');

    final login = LoginResponse.fromJson(response);
    if (login.user != null) {
      return login.user!;
    }

    throw Failure.missingData(debugMessage: 'data not found');
  }

  @override
  Future<void> updateName(String name) async {
    final dataApi = GlobalDataApi.instance;
    await dataApi.putResponse(url: 'users/me/name', data: {'name': name});
  }

  @override
  Future<void> updateBio(String bio) async {
    final dataApi = GlobalDataApi.instance;
    await dataApi.putResponse(url: 'users/me/bio', data: {'bio': bio});
  }

  @override
  Future<AvatarResponse> updateProfileAvatar(String path) async {
    final dataApi = GlobalDataApi.instance;
    final response = await dataApi.postResponse(
      url: 'users/me/avatar',
      data: FormData.fromMap({'avatar': await MultipartFile.fromFile(path)}),
    );
    return AvatarResponse.fromJson(response);
  }
}
