
import 'dart:io';

import 'package:another_flushbar/flushbar.dart';
import 'package:another_flushbar/flushbar_route.dart';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:whatsapp_flutter_go/gen/assets.gen.dart';

enum FlasType { error, success }

class Utils {
  static fieldFocusChanged(
    BuildContext context,
    FocusNode currentNode,
    FocusNode nextNode,
  ) {
    currentNode.unfocus();
    FocusScope.of(context).requestFocus(nextNode);
  }

  static showToastMessage(String message) {
    Fluttertoast.showToast(
      msg: message,
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }

  static showFlashBarMessage(
      String message, FlasType type, BuildContext context) {
    showFlushbar(
        context: context,
        flushbar: Flushbar(
          title: type == FlasType.success ? "Success" : "Error",
          icon: Icon(
            type == FlasType.success ? Icons.thumb_up : Icons.error,
            color: Colors.white,
          ),
          message: message,
          backgroundColor: type == FlasType.success ? Colors.green : Colors.red,
          titleColor: Colors.white,
          messageColor: Colors.white,
          duration: const Duration(seconds: 2),
        )..show(context));
  }

  static Widget profileImage(String? imageUrl, {bool isFile = false}) {
    if(isFile && imageUrl!=null) return Image.file(File(imageUrl), fit: BoxFit.cover,);
    if (imageUrl == null || imageUrl == 'default' || imageUrl == '') {
      return Image.asset(
        Assets.images.packlyLoadingImageIcon.path,
        fit: BoxFit.cover,
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
    );
  }
}
