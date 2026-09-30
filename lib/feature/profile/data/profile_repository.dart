import '../../login/model/login_response.dart';
import '../model/avatar_request.dart';

abstract class ProfileRepository {
  Future<User> getProfile({String? id});
  Future<void> updateName(String name);
  Future<void> updateBio(String bio);
  Future<AvatarResponse> updateProfileAvatar(String path);
}
