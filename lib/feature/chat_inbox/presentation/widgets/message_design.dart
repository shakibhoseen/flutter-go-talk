import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/helper/my_ui_import.dart';
import 'package:whatsapp_flutter_go/core/widgets/cute_avatar.dart';

import '../../../home/model/chat_message.dart';
import '../../../../core/session/auth_session.dart';

enum BubblePosition {
  single,
  first,
  middle,
  last,
}

Widget bottomDesign({
  required String value,
  required Function pickImageFromGallery,
  required Function removePic,
  required Function sendMessage,
  required TextEditingController messageController,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border(
        top: BorderSide(
          color: AppColors.neutralColor.shade100,
          width: 1.0,
        ),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.neutralColor.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      if (value == '') {
                        pickImageFromGallery();
                      } else {
                        removePic();
                      }
                    },
                    icon: Icon(
                      value == ''
                          ? Icons.add_circle_outline_rounded
                          : Icons.cancel_outlined,
                      color: AppColors.cyanAccent,
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AppColors.neutralColor.shade900,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(
                          fontSize: 14.5,
                          color: AppColors.neutralColor.shade400,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.cyanAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyanAccent.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: () => sendMessage(),
              icon: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

BorderRadius _getBubbleRadius({
  required bool isMine,
  required BubblePosition position,
}) {
  const double rBig = 18.0;
  const double rSmall = 4.0;

  if (isMine) {
    // Outgoing (Mine on Right): Left corners facing center are always round (rBig)
    switch (position) {
      case BubblePosition.single:
        return const BorderRadius.only(
          topLeft: Radius.circular(rBig),
          topRight: Radius.circular(rBig),
          bottomLeft: Radius.circular(rBig),
          bottomRight: Radius.circular(rSmall),
        );
      case BubblePosition.first:
        return const BorderRadius.only(
          topLeft: Radius.circular(rBig),
          topRight: Radius.circular(rBig),
          bottomLeft: Radius.circular(rBig),
          bottomRight: Radius.circular(rSmall),
        );
      case BubblePosition.middle:
        return const BorderRadius.only(
          topLeft: Radius.circular(rBig),
          topRight: Radius.circular(rSmall),
          bottomLeft: Radius.circular(rBig),
          bottomRight: Radius.circular(rSmall),
        );
      case BubblePosition.last:
        return const BorderRadius.only(
          topLeft: Radius.circular(rBig),
          topRight: Radius.circular(rSmall),
          bottomLeft: Radius.circular(rBig),
          bottomRight: Radius.circular(rBig),
        );
    }
  } else {
    // Incoming (Other on Left): Right corners facing center are always round (rBig)
    switch (position) {
      case BubblePosition.single:
        return const BorderRadius.only(
          topLeft: Radius.circular(rBig),
          topRight: Radius.circular(rBig),
          bottomRight: Radius.circular(rBig),
          bottomLeft: Radius.circular(rSmall),
        );
      case BubblePosition.first:
        return const BorderRadius.only(
          topLeft: Radius.circular(rBig),
          topRight: Radius.circular(rBig),
          bottomRight: Radius.circular(rBig),
          bottomLeft: Radius.circular(rSmall),
        );
      case BubblePosition.middle:
        return const BorderRadius.only(
          topLeft: Radius.circular(rSmall),
          topRight: Radius.circular(rBig),
          bottomRight: Radius.circular(rBig),
          bottomLeft: Radius.circular(rSmall),
        );
      case BubblePosition.last:
        return const BorderRadius.only(
          topLeft: Radius.circular(rSmall),
          topRight: Radius.circular(rBig),
          bottomRight: Radius.circular(rBig),
          bottomLeft: Radius.circular(rBig),
        );
    }
  }
}

Widget designMessage(
  ChatMessage model,
  Function resentMessage,
  bool isCompare,
  int before,
  bool todayIndicator,
  bool showSenderName,
  bool showProfile,
  bool isGroup, {
  BubblePosition position = BubblePosition.single,
  bool isSameSenderAbove = true,
  List<ReadReceiptUser>? readBy,
  int? readCount,
}) {
  final hold = isCompare
      ? showTimeOrNot(
          before,
          model.sentAt.millisecondsSinceEpoch,
          isSameSender: isSameSenderAbove,
        )
      : null;
  final isMine = model.isMine;

  return Column(
    children: [
      if (hold != null) hold.$1,
      if (todayIndicator)
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.neutralColor.shade200,
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            '${model.timeStamp?.dateCompare}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.neutralColor.shade600,
            ),
          ),
        ),
      if (showSenderName && !isMine && isGroup)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 48, bottom: 3),
            child: Text(
              model.senderName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.cyanDark,
              ),
            ),
          ),
        ),
      Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMine && isGroup)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0, bottom: 1),
                  child: showProfile
                      ? CuteAvatar(
                          name: model.senderName,
                          imageUrl: model.senderAvatar,
                          size: 28,
                          showOnlineDot: false,
                        )
                      : const SizedBox(width: 28),
                ),
              Builder(
                builder: (context) {
                  final screenWidth = MediaQuery.sizeOf(context).width;
                  final isShortMessage =
                      !model.message.contains('\n') && model.message.length <= 20;

                  final timeAndCheckWidget = Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${model.timeStamp?.hourMinute}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w400,
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppColors.neutralColor.shade400,
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 3.5),
                        model.isSeen
                            ? const Icon(
                                Icons.done_all_rounded,
                                size: 14,
                                color: AppColors.seenNavy,
                              )
                            : (model.isDelivered
                                ? Icon(
                                    Icons.done_all_rounded,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.65),
                                  )
                                : Icon(
                                    Icons.done_rounded,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.65),
                                  )),
                      ],
                    ],
                  );

                  return Container(
                    constraints: BoxConstraints(
                      maxWidth: screenWidth * 0.76,
                      minWidth: 50,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6.5,
                    ),
                    decoration: BoxDecoration(
                      color: isMine ? AppColors.cyanAccent : Colors.white,
                      borderRadius: _getBubbleRadius(
                        isMine: isMine,
                        position: position,
                      ),
                      border: isMine
                          ? null
                          : Border.all(
                              color: AppColors.neutralColor.shade200,
                              width: 0.8,
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: isMine
                              ? AppColors.cyanAccent.withValues(alpha: 0.22)
                              : Colors.black.withValues(alpha: 0.03),
                          blurRadius: 5,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                    child: isShortMessage
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  model.message,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    height: 1.25,
                                    color: isMine
                                        ? Colors.white
                                        : AppColors.neutralColor.shade900,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              timeAndCheckWidget,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  model.message,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    height: 1.3,
                                    color: isMine
                                        ? Colors.white
                                        : AppColors.neutralColor.shade900,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              timeAndCheckWidget,
                            ],
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      Builder(
        builder: (context) {
          final myId = AuthSession.tokens?.user?.id?.toString();
          final effectiveReadBy = readBy ?? model.readBy;
          final effectiveReadCount = readCount ?? model.readCount;
          final otherReadBy = effectiveReadBy
              .where((u) => u.userId.toString() != myId)
              .toList();

          if (!isGroup || otherReadBy.isEmpty) return const SizedBox();

          final isMeInReadBy =
              effectiveReadBy.any((u) => u.userId.toString() == myId);
          final totalOtherReaders =
              isMeInReadBy ? effectiveReadCount - 1 : effectiveReadCount;
          final visibleCount = otherReadBy.length > 3 ? 3 : otherReadBy.length;
          final extraCount = totalOtherReaders - visibleCount;

          return Padding(
            padding: const EdgeInsets.only(right: 14.0, top: 2.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ...otherReadBy.take(3).map(
                  (user) => Padding(
                    padding: const EdgeInsets.only(left: 2.0),
                    child: CuteAvatar(
                      name: user.name,
                      imageUrl: user.avatarUrl,
                      size: 14,
                      showOnlineDot: false,
                    ),
                  ),
                ),
                if (extraCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 3.0),
                    child: Text(
                      '+$extraCount',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.neutralColor.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ],
  );
}

(Widget, bool) showTimeOrNot(
  int before,
  int after, {
  bool isSameSender = true,
}) {
  int difference = (before - after).abs();

  if (difference < 600000) {
    // Gap 1: Less than 10 minutes
    // Same sender is tightly grouped (2.5dp); different sender has gentle separation (10dp)
    return (UIHelper.verticalSpace(isSameSender ? 2.5 : 10.0), false);
  } else if (difference < 3600000) {
    // Gap 2: 10 minutes to 1 hour (small gap)
    return (UIHelper.verticalSpace(14.0), true);
  } else {
    // Gap 3: 1 hour or more (more gap)
    return (UIHelper.verticalSpace(26.0), true);
  }
}
