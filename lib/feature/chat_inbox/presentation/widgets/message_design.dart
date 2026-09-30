import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:whatsapp_flutter_go/core/helper/my_ui_import.dart';

import 'package:whatsapp_flutter_go/core/config/app_flavor_config.dart';
import 'package:whatsapp_flutter_go/core/db/network/network_service_type.dart';

import '../../../../gen/assets.gen.dart';
import '../../../home/model/chat_message.dart';

String _getFullUrl(String path) {
  if (path.isEmpty) return "";
  if (path.startsWith("http")) return path;
  final baseUrl = AppFlavorConfig.baseUrlFor(NetworkServiceType.chat);

  if (baseUrl.endsWith('/') && path.startsWith('/')) {
    return baseUrl + path.substring(1);
  } else if (!baseUrl.endsWith('/') && !path.startsWith('/')) {
    return '$baseUrl/$path';
  }
  return baseUrl + path;
}

Widget bottomDesign({
  required String value,
  required Function pickImageFromGallery,
  required Function removePic,
  required Function sendMessage,
  required TextEditingController messageController,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.deepPurple[50],
                shape: BoxShape.rectangle,
                border: Border.all(color: Colors.white),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UIHelper.horizontalSpace(7),
                  IconButton(
                    onPressed: () {
                      if (value == '') {
                        pickImageFromGallery();
                      } else {
                        removePic();
                      }
                    },
                    icon: Icon(
                      value == '' ? Icons.image : Icons.cancel_outlined,
                      color: Colors.blue,
                    ),
                  ),
                  UIHelper.horizontalSpace(6),
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      style: TextStyle(),
                      decoration: InputDecoration(
                        hintText: 'Message',
                        hintStyle: TextStyle(),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  // Consumer<UploadViewModel>(
                  //   builder: (context, value, child) {
                  //     String text = 'init ';
                  //     if (value.status == UploadStatus.running)
                  //       text = 'running';
                  //     else if (value.status == UploadStatus.success)
                  //       text = 'success';
                  //     return Text(
                  //       '${value.progress} $text',
                  //       style: Constants.customTextStyle(textSize: TextSize.sm),
                  //     );
                  //   },
                  // ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: 50,
          width: 50,
          child: FloatingActionButton(
            shape: const CircleBorder(side: BorderSide(color: Colors.white)),
            onPressed: () {
              sendMessage();
            },
            child: Icon(Icons.send, color: AppColors.primaryColor),
          ),
        ),
      ],
    ),
  );
}

Widget designMessage(
  ChatMessage model,
  Function resentMessage,
  bool isCompare,
  int before,
  bool todayIndicator,
  bool showSenderName,
  bool showProfile,
  bool isGroup,
) {
  final hold = isCompare
      ? showTimeOrNot(before, model.sentAt.millisecondsSinceEpoch)
      : null;
  return Column(
    children: [
      if (hold != null) hold.$1,
      if (todayIndicator)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade400, Colors.green.shade700],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [],
            image: DecorationImage(
              image: AssetImage(Assets.lightBg.path),
              fit: BoxFit.cover,
            ),
          ),
          child: Text(
            '${model.timeStamp?.dateCompare}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      if (todayIndicator) UIHelper.verticalSpace(20),
      if (showSenderName)
        Align(
          alignment: AlignmentGeometry.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 44, bottom: 2),
            child: Text(
              model.senderName,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ),
      Align(
        alignment: model.isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              /*              if (model.isFailed ?? false)
                IconButton(
                    iconSize: 24,
                    onPressed: () {
                      resentMessage(model);
                    },
                    icon: const Icon(
                      Icons.error,
                      color: Colors.red,
                    )),*/
              if (!model.isMine && isGroup)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ClipOval(
                    child: (showProfile)
                        ? CachedNetworkImage(
                            imageUrl: _getFullUrl(model.senderAvatar),
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.grey.shade300,
                              child: const Icon(
                                Icons.person,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : SizedBox(width: 28),
                  ),
                ),
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: model.isMine
                      ? Colors.red.shade400
                      : Colors.grey.shade100,
                  image: DecorationImage(
                    image: AssetImage(Assets.darkBg.path),
                    opacity: 0.7,
                    fit: BoxFit.cover,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: model.isMine
                        ? const Radius.circular(20)
                        : const Radius.circular(0),
                    topRight: model.isMine
                        ? const Radius.circular(0)
                        : const Radius.circular(20),
                    bottomLeft: model.isMine
                        ? const Radius.circular(20)
                        : const Radius.circular(12),
                    bottomRight: model.isMine
                        ? const Radius.circular(12)
                        : const Radius.circular(20),
                  ),
                  boxShadow: [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flex(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      direction: model.message.length > 18
                          ? Axis.vertical
                          : Axis.horizontal,
                      children: [
                        Text(
                          model.message,
                          overflow: TextOverflow.clip,
                          style: TextStyle(fontSize: 12, color: Colors.black),
                        ),
                        UIHelper.horizontalSpace8,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            model.isMine ?? false
                                ? model.isSeen
                                      ? Icon(
                                          FontAwesomeIcons.checkDouble.data,
                                          size: 12,
                                          color: Colors.green,
                                        )
                                      : Icon(
                                          FontAwesomeIcons.check.data,
                                          size: 12,
                                          color: Colors.grey,
                                        )
                                : Container(),
                            Text(
                              '${model.timeStamp?.hourMinute}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      if (model.readBy.isNotEmpty)
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // लুপ চালিয়ে ছোট ছোট Avatar দেখাব
            ...model.readBy.map(
              (user) => Padding(
                padding: const EdgeInsets.only(left: 2.0),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: _getFullUrl(user.avatarUrl),
                    width: 14,
                    height: 14,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => CircleAvatar(
                      radius: 7,
                      backgroundColor: Colors.grey.shade300,
                      child: const Icon(
                        Icons.person,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (model.readCount > 3)
              Text('+${model.readCount - 3}', style: TextStyle(fontSize: 10)),
          ],
        ),
    ],
  );
}

(Widget, bool) showTimeOrNot(int before, int after) {
  //space, name show or not/profile show or not
  int difference = (before - after).abs();

  if (difference < 3600000) {
    // Less than an hour
    if (difference < 600000) {
      // Less than 10 minutes
      return (UIHelper.verticalSpace(3), false); // Small; // Tiny
    } else {
      return (UIHelper.verticalSpace(24), true); // Mid-sized
    }
  } else {
    return (UIHelper.verticalSpace(32), true); // Big
  }
}
