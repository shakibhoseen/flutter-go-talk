import 'package:either_dart/either.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/cursor_pagination_response.dart';
import 'package:whatsapp_flutter_go/core/state/cursor/local_sync_cursor_pagination_bloc.dart';

import '../../home/data/http_chat_repository.dart';
import '../../home/model/chat_message.dart';

class InboxMessageListCursorBloc
    extends LocalSyncCursorPaginationBloc<ChatMessage> {
  final repository = HttpChatRepository();
  final pageSize = 20;
  final String conversationId;

  InboxMessageListCursorBloc({required this.conversationId})
    : super(InitialState());

  @override
  String itemIdentity(ChatMessage item) => item.id;

  @override
  Future<Either<CursorPaginationResponse<ChatMessage>, String>> handleEvent(
    event,
  ) async {
    final response = await repository.getMessages(
      conversationId,
      limit: pageSize,
      beforeId: nextCursor,
    );

    setCursor(model: response);
    return Left(response);
  }

  void execute({bool? pageFromStart}) {
    add(FetchDataWithQueryEvent(
        query: {},
        clearPageWithNewData: pageFromStart ?? false));
  }
}
