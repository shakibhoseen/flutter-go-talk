import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'session_cubit.dart';

class SessionResetScope extends StatelessWidget {
  const SessionResetScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SessionCubit, SessionState, SessionState>(
      selector: (state) => state,
      builder: (context, state) {
        return KeyedSubtree(key: ValueKey(state), child: child);
      },
    );
  }
}
