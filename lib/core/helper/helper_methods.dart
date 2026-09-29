import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../navigation/navigation_service.dart';
import '../theme/app_colors.dart';
import '../../gen/assets.gen.dart';

Future<void> rotation() async {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: AppColors.foundationWhite,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.foundationWhite,
    systemNavigationBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
}

extension FutureDialogExtension<T> on Future<T> {
  /// Extension that shows a loading dialog until the future completes.
  Future<T> showLoadingDialog(
      [BuildContext? context, bool barrierDismissible = false]) async {
    // Show the loading dialog
    // store the dialog route
    ModalRoute<void>? dialogRoute;
    final bContext = context ?? NavigationService.context;
    if (bContext.mounted) {
      dialogRoute = DialogRoute(
        context: bContext,
        barrierDismissible: barrierDismissible,
        // Prevents the dialog from being dismissed manually
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: Lottie.asset(Assets.animationJson.packlyLoading1),
        ),
      );
      if (context != null) {
        Navigator.of(context).push(dialogRoute);
      } else {
        NavigationService.pushModalRoute(dialogRoute);
      }
    }

    try {
      return await this;
    } finally {
      // // Dismiss the dialog after the future completes
      if (dialogRoute != null && dialogRoute.isActive) {
        if (context != null) {
          Navigator.of(context).removeRoute(dialogRoute);
        } else {
          NavigationService.removeModalRoute(dialogRoute);
        }
      }
    }
  }
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _snackBarController;
bool _isComingSoonVisible = false;

void showComingSoonMessage(BuildContext context) {
  if (_isComingSoonVisible) return;

  final messenger = ScaffoldMessenger.of(context);
  _isComingSoonVisible = true;

  _snackBarController = messenger.showSnackBar(
    const SnackBar(
      content: Text("Coming Soon!"),
      duration: Duration(seconds: 2),
    ),
  );

  _snackBarController!.closed.then((_) {
    _isComingSoonVisible = false;
    _snackBarController = null;
  });
}

/// Force dismiss (call this before navigation or on button tap)
void dismissComingSoonMessage() {
  _snackBarController?.close();
  _snackBarController = null;
  _isComingSoonVisible = false;
}
