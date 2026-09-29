import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/di/di.dart';
import '../core/session/session_cubit.dart';
import '../core/session/session_reset_scope.dart';
import 'app_view.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: locator<SessionCubit>(),
      child: const SessionResetScope(child: AppView()),
    );
  }
}
