import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum SessionStatus {
  unknown,
  guest,
  authenticated,
}

final class SessionState extends Equatable {
  const SessionState._({
    required this.status,
    this.accessToken,
  });

  const SessionState.unknown() : this._(status: SessionStatus.unknown);

  const SessionState.guest()
      : this._(
          status: SessionStatus.guest,
        );

  const SessionState.authenticated(String accessToken)
      : this._(
          status: SessionStatus.authenticated,
          accessToken: accessToken,
        );

  final SessionStatus status;
  final String? accessToken;

  bool get isUnknown => status == SessionStatus.unknown;

  bool get isGuest => status == SessionStatus.guest;

  bool get isAuthenticated => status == SessionStatus.authenticated;

  @override
  List<Object?> get props => [status, accessToken];
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit() : super(const SessionState.unknown());

  void sync({
    required bool isLoggedIn,
    String? accessToken,
  }) {
    final normalizedToken = accessToken?.trim();
    final hasToken = normalizedToken != null && normalizedToken.isNotEmpty;

    if (isLoggedIn && hasToken) {
      emit(SessionState.authenticated(normalizedToken));
      return;
    }

    emit(const SessionState.guest());
  }

  void markUnknown() {
    emit(const SessionState.unknown());
  }
}
