import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';
import 'package:whatsapp_flutter_go/feature/login/data/auth_login_repository.dart';

import '../../../login/model/login_response.dart';

class ViewModel {
  final profileBloc = SimpleBlocParent<User>();

  ViewModel() {
    setUp();
    profileBloc.execute();
  }

  void setUp() {
    profileBloc.setFunction(
      attach: (event) => AuthLoginRepository().getProfile(),
    );
  }
}
