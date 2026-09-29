import 'dart:async';

import 'package:flutter/material.dart';

import 'application/startup/app_bootstrap.dart';
import 'core/helper/helper_methods.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep `main()` as light as possible; do heavy async initialization after
  // the first frame to reduce "slow cold start" on low-end devices.
  runApp(const AppBootstrap());

  unawaited(rotation());
}
