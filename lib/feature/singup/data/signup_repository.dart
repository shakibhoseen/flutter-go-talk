
import '../../login/model/login_response.dart';

abstract class SignUpRepository {
  /// Signs in with an email **or** a phone number — the accounts service takes
  /// either in the same `identifier` field and decides which it is.
  ///
  /// Answers with the token pair and the account behind it, or throws a
  /// `Failure` carrying the server's message.
  Future<User> signUp({
    required String email,
    required String name,
    required String password,
  });
}
