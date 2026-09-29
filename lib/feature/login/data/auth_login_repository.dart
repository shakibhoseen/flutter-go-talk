import 'dart:developer';

import 'package:whatsapp_flutter_go/core/state/global_data_api.dart';

import '../../../../../core/db/network/auth_endpoints.dart';
import '../../../../../core/db/network/dio/auth_dio.dart';
import '../../../../../core/db/network/exception_handler/data_source.dart';
import '../../../../../core/helper/device_identity.dart';
import '../model/login_response.dart';
import 'login_repository.dart';

/// [LoginRepository] against the accounts service.
class AuthLoginRepository implements LoginRepository {
  const AuthLoginRepository();

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      await DeviceIdentity.resolve();
      final response = await authPostHttp(
        AuthEndpoints.login(),
        data: {'email': email, 'password': password},
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

      // The accounts service returns `{token, user}` at the top level —
      // no `data` envelope. Prefer one if a future response does add it.
      final data = _asMap(body['data']) ?? body;

      final login = LoginResponse.fromJson(data);
      if (!(login.token?.isNotEmpty ?? false)) {
        throw Failure.missingData(
          debugMessage: 'login response carried no token pair',
        );
      }
      return login;
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

  @override
  Future<User> getProfile({String? id}) async {
    final dataAPi = GlobalDataApi.instance;
    final response = await dataAPi.getResponse(url: 'users/me');

    final login = LoginResponse.fromJson(response);
    if (login.user != null) {
      return login.user!;
    }
    // TODO: implement getProfile
    throw UnimplementedError();
  }
}
