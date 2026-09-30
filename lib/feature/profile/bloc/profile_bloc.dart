import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';
import 'package:whatsapp_flutter_go/feature/login/model/login_response.dart';
import 'package:whatsapp_flutter_go/feature/profile/data/profile_repo_impl.dart';

import '../model/avatar_request.dart';

class ProfileBloc extends SimpleBlocParent<User> {
  final _repo = ProfileRepoImpl();

  ProfileBloc() {
    setFunction(attach: (event) => _repo.getProfile());
  }

  Future<void> updateName(String newName) async {
    await _repo.updateName(newName);
    if (state is SuccessState<User>) {
      final user = (state as SuccessState<User>).data;
      user.name = newName;
      emitSuccess(user);
    } else {
      execute();
    }
  }

  Future<void> updateBio(String newBio) async {
    await _repo.updateBio(newBio);
    if (state is SuccessState<User>) {
      final user = (state as SuccessState<User>).data;
      user.bio = newBio;
      emitSuccess(user);
    } else {
      execute();
    }
  }

  Future<void> uploadProfileImage(String path) async {
    final response = await _repo.updateProfileAvatar(path);
    if (state is SuccessState<AvatarResponse>) {
      final user = (state as SuccessState<User>).data;
      user.avatarUrl = response.avatarUrl;
      emitSuccess(user);
    } else {
      execute();
    }
  }
}
