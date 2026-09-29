import 'dart:developer';

import '../../../../../core/db/network/auth_endpoints.dart';
import '../../../../../core/db/network/dio/auth_dio.dart';
import '../../../../../core/db/network/exception_handler/data_source.dart';
import '../../../../../core/helper/device_identity.dart';
import '../../login/model/login_response.dart';
import 'signup_repository.dart';

/// [LoginRepository] against the accounts service.
class AuthSignUpRepository implements SignUpRepository {
  const AuthSignUpRepository();

  @override
  Future<User> signUp({
    required String email,
    required String name,
    required String password,
  }) async {
    try {
      final device = await DeviceIdentity.resolve();
      final response = await authPostHttp(
        AuthEndpoints.register(),
        data: {
          'email': email,
          'password': password,
        },
        // Wrong credentials belong under the password field, not in a toast
        // that covers the form the user is about to correct.
        requestMetadata: const RequestFailureMetadata(
          isAuthRequest: true,
          preferredDisplayType: ErrorDisplayType.inline,
        ),
      );

      final body = _asMap(response.data);
      if (body == null) {
        throw DataSource.defaults.getFailure();
      }

      // A 200 with `success:false` is still a failure — carry the server's
      // message instead of showing an empty form.
      final businessFailure = ErrorHandler.tryResolveBusinessFailure(
        body,
        displayType: ErrorDisplayType.inline,
        requestOptions: response.requestOptions,
      );
      if (businessFailure != null) {
        throw businessFailure;
      }

      // The accounts service returns `{token, user}` at the top level — no
      // `data` envelope. Prefer one if a future response does add it.
      final data = _asMap(body['data']) ?? body;

      final login = LoginResponse.fromJson(data); // just parse user

      if(login.user==null){
        throw Failure.missingData(debugMessage:'login response carried no user');
      }
      return login.user!;
    } catch (error) {
      final failure = ErrorHandler.resolve(error);
      log('login failed: ${failure.responseCode} ${failure.responseMessage}');
      throw failure;
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) => switch (value) {
    final Map<String, dynamic> value => value,
    final Map value => Map<String, dynamic>.from(value),
    _ => null,
  };
}
