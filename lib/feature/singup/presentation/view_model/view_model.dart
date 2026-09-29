import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';

import '../../../login/model/login_response.dart';
import '../../data/auth_sign_up_repository.dart';

class ViewModel {
  final simpleLogin = SimpleBlocParent<User>();
  final repository = AuthSignUpRepository();

  ViewModel() {
    setUp();
  }

  void setUp() {
    simpleLogin.setFunction(
      attach: (event) {
        if (event is FetchDataWithQueryEvent &&
            event.query != null &&
            (event.query ?? {}).isNotEmpty) {
          final query = event.query!;
          final email = query['email'];
          final password = query['password'];
          final name = query['name'];
          return repository.signUp(
            name: name,
            email: email,
            password: password,
          );
        }

        throw "input not valid";
      },
    );
  }

  void signUp({String? name, String? email, String? password}) {
    if (email == null ||
        password == null ||
        name == null ||
        email.isEmpty ||
        password.isEmpty ||
        name.isEmpty) {
      return;
    }

    simpleLogin.add(
      FetchDataWithQueryEvent(
        query: {'email': email, 'password': password, "name": name},
      ),
    );
  }
}
