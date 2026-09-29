import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/di/di.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/chat_routes.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/session/session_cubit.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';

import '../../../login/model/login_response.dart';
import '../../data/auth_login_repository.dart';

class ViewModel {
  final simpleLogin = SimpleBlocParent<LoginResponse>();
  final repository = AuthLoginRepository();

  ViewModel() {
    setUp();
    simpleLogin.stream.listen(_handleState);
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
          return repository.login(email: email, password: password);
        }

        throw "input not valid";
      },
    );
  }

  /// Login itself only gets the tokens back — this is the one place that
  /// turns "the request succeeded" into "the app is signed in": persisting
  /// the session, syncing [SessionCubit] (so `SessionResetScope` and the
  /// splash-time routing decision see it), and moving off the login screen.
  void _handleState(CommonState state) {
    if (state is! SuccessState<LoginResponse>) return;
    final response = state.data;
    AuthSession.start(response);
    locator<SessionCubit>().sync(
      isLoggedIn: true,
      accessToken: response.token,
    );
    ChatSocketService.instance.connect();
    NavigationService.removeALlAndReplace(ChatRoutes.home);
  }

  void login({String? email, String? password}) {
    if (email == null || password == null) {
      return;
    }

    simpleLogin.add(
      FetchDataWithQueryEvent(query: {'email': email, 'password': password}),
    );
  }
}
