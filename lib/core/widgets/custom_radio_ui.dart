import 'package:flutter/material.dart';
import '../helper/my_ui_import.dart';

import '../theme/app_dimens.dart';

class CustomRadioUi extends StatelessWidget {
  const CustomRadioUi({
    super.key,
    this.selected = false,
    this.size,
    this.onChanged,
    this.strokeWidth,
    this.disable = false,
  });
  final Function(bool)? onChanged;
  final bool selected, disable;
  final Size? size;
  final double? strokeWidth;

  void externalOnTap() {
    onChanged?.call(true); // radio could not be unselect
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size?.height ?? AppDimens.spMin24,
      width: size?.width ?? AppDimens.spMin24,
      decoration: ShapeDecoration(
        shape: CircleBorder(
          side: selected
              ? BorderSide(
                  width: (size?.height != null ? (size!.height) / 3 : 8),
                  color: disable
                      ? AppColors.neutralColor.shade300
                      : AppColors.primaryColor,
                )
              : BorderSide(
                  width: strokeWidth ?? 2,
                  color: disable
                      ? AppColors.neutralColor.shade300
                      : AppColors.neutralColor.shade400,
                ),
        ),
      ),
    );
  }
}
