import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';

class CustomDivider extends StatelessWidget {
  const CustomDivider({super.key, this.indent, this.endDent});

  final double? indent;
  final double? endDent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: .6,
      color: AppColors.neutralColor[200],
      width: double.infinity,
      margin: indent != null || endDent != null
          ? EdgeInsets.only(left: indent ?? 0, right: endDent ?? 0)
          : null,
    );
  }
}
