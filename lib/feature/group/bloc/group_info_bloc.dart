import 'dart:io';

import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';
import 'package:whatsapp_flutter_go/feature/group/data/group_repo_imp.dart';

class GroupInfoBloc extends SimpleBlocParent<Conversation> {
  final _repo = GroupRepoImp();

  GroupInfoBloc(Conversation initialData) {
    emitSuccess(initialData);
  }

  Future<void> uploadGroupAvatar(File imageFile) async {
    if (state is SuccessState<Conversation>) {
      final currentConv = (state as SuccessState<Conversation>).data;
      
      // Call repo
      final avatarUrl = await _repo.updateGroupAvatar(currentConv.id, imageFile);
      
      // Emit new state with updated avatar url
      if (!avatarUrl.contains("failed")) {
        final updatedConv = currentConv.copyWith(avatarUrl: avatarUrl);
        emitSuccess(updatedConv);
      }
    }
  }
}
