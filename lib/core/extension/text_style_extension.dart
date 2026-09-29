import 'package:flutter/material.dart';

extension MyTextExtenstion on TextStyle? {
  TextStyle? get regular => this?.copyWith(fontWeight: FontWeight.w400);

  TextStyle? get light => this?.copyWith(fontWeight: FontWeight.w300);

  TextStyle? get medium => this?.copyWith(fontWeight: FontWeight.w500);

  TextStyle? get semiBold => this?.copyWith(fontWeight: FontWeight.w600);

  TextStyle? get bold => this?.copyWith(fontWeight: FontWeight.w700);

  TextStyle? get extraBold => this?.copyWith(fontWeight: FontWeight.w800);

  TextStyle? get black => this?.copyWith(fontWeight: FontWeight.w900);
}

extension MyColorExtenstion on TextStyle? {
  TextStyle? setColor(Color color) => this?.copyWith(color: color);
}
