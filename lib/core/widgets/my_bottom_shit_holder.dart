import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class MyBottomShitHolder extends StatelessWidget {
  const MyBottomShitHolder({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            child: Center(
              child: Container(
                height: 5,
                width: 45,
                decoration: ShapeDecoration(
                  color: AppColors.neutralColor.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
