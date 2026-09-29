

import 'package:flutter/cupertino.dart';
import 'package:get_it/get_it.dart';

import '../navigation/navigation_service.dart';
import '../services/my_shared_pref.dart';
import '../session/session_cubit.dart';

final locator = GetIt.instance;

MySharedPref get appData => locator.get<MySharedPref>();

RouteObserver<PageRoute> get screenLifecycleObserver =>
    locator.get<RouteObserver<PageRoute>>();
AppNavigatorObserver get appNavigatorObserver =>
    locator.get<AppNavigatorObserver>();


Future<void> diSetup() async {
  // to do


  locator.registerLazySingleton<RouteObserver<PageRoute>>(
    () => RouteObserver<PageRoute>(),
  );
  locator.registerLazySingleton<AppNavigatorObserver>(
    () => AppNavigatorObserver(),
  );

  locator.registerLazySingleton<MySharedPref>(() => MySharedPref());
  final sessionCubit = SessionCubit();
  locator.registerSingleton<SessionCubit>(sessionCubit);

}
