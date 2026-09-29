import 'dart:async';

import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';

import '../../../gen/assets.gen.dart';
import '../data/chat_repository.dart';
import '../data/http_chat_repository.dart';
import '../data/socket_event.dart';
import '../model/chat_message.dart';
import '../model/conversation.dart';

/// The 1:1/group thread — `hk`'s `MessageHomePage` equivalent.
///
/// History comes from `GET /conversations/{id}/messages`, newest page
/// first, then older pages on demand as the user scrolls up
/// (`before_id` = the oldest message id already loaded). Sending and
/// receiving both go over [ChatSocketService]: a sent message isn't added
/// to [_messages] directly — the server echoes it back as a `new_message`
/// event (same as anyone else's), so there's exactly one path into the list
/// instead of an optimistic copy racing the echo.
class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.conversation,
    this.repository = const HttpChatRepository(),
    this.pageSize = 5,
  });

  final Conversation conversation;
  final ChatRepository repository;
  final int pageSize;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  /// Oldest-first — matches the order the server sends each page in.
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  StreamSubscription<dynamic>? _socketSubscription;

  String? get _myId => AuthSession.tokens?.user?.id?.toString();

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
    _socketSubscription = ChatSocketService.instance.messages.listen(
      _handleSocketEvent,
    );
  }

  Future<void> _load() async {
    final messages = await widget.repository.getMessages(
      widget.conversation.id,
      limit: widget.pageSize,
    );
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(messages.data??[]);
      _hasMore = (messages.data??[]).length >= widget.pageSize;
      _loading = false;
    });
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    // `reverse: true`, so the oldest-message end is what scrolling *up*
    // approaches — that's `maxScrollExtent`, not zero.
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_messages.isEmpty) return;
    setState(() => _loadingMore = true);

    final cursor = await widget.repository.getMessages(
      widget.conversation.id,
      limit: widget.pageSize,
      beforeId: _messages.first.id,
    );
    final older = cursor.data??[];
    if (!mounted) return;
    setState(() {
      _messages.insertAll(0, older);
      _hasMore = older.length >= widget.pageSize;
      _loadingMore = false;
    });
  }

  void _handleSocketEvent(dynamic raw) {
    final event = decodeSocketEvent(raw);
    if (event == null || event['type'] != 'new_message') return;

    final payload = event['payload'];
    if (payload is! Map) return;
    final json = Map<String, dynamic>.from(payload);
    if (json['conversation_id']?.toString() != widget.conversation.id) return;

    setState(() {
      _messages.add(ChatMessage.fromJson(json, currentUserId: _myId));
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ChatSocketService.instance.sendMessage(
      conversationId: widget.conversation.id,
      content: text,
    );
    _controller.clear();
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.conversation.displayTitle)),
      // Same wallpaper-behind-bubbles structure as `hk`'s MessageHomePage —
      // just backed by our own [ChatMessage] model instead of Firebase's.
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.green.shade200,
          image: DecorationImage(
            image: AssetImage(Assets.lightBg.path),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? const Center(child: Text('Say hello 👋'))
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_loadingMore && index == _messages.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        final message =
                            _messages[_messages.length - 1 - index];
                        return Align(
                          alignment: message.isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.sizeOf(context).width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: message.isMine
                                  ? Colors.green.shade100
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(message.message),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.send), onPressed: _send),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
