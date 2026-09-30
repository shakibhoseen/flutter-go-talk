
import '../model/login_response.dart';

abstract class LoginRepository {
  /// Signs in with an email **or** a phone number — the accounts service takes
  /// either in the same `identifier` field and decides which it is.
  ///
  /// Answers with the token pair and the account behind it, or throws a
  /// `Failure` carrying the server's message.
  Future<LoginResponse> login({
    required String email,
    required String password,
  });


}
