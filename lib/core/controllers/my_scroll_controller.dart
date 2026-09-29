import 'package:flutter/cupertino.dart';
import '../state/cursor/cursor_pagination_bloc.dart';
import '../state/model/list_and_page_holder.dart';

import '../state/common_base_bloc.dart';

class MyScrollController {
  final ScrollController _scrollController;
  final CommonPaginationBloc commonPaginationBloc;
  final VoidCallback onPageAvailableHit;
  final double _scrollThreshold;
  final bool isReverse;
  bool _canTriggerNextPage = true;

  final ListAndPageHolder? listAndPageHolder;

  MyScrollController(
    this.commonPaginationBloc,
    this.onPageAvailableHit, {
    double scrollThreshold = 200.0,
    this.isReverse = false,
    this.listAndPageHolder,
  }) : _scrollController = ScrollController(),
       _scrollThreshold = scrollThreshold {
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;

    final bool isNearEdge;
    if (isReverse) {
      final distanceToTop = position.maxScrollExtent - position.pixels;
      isNearEdge = distanceToTop <= _scrollThreshold;
    } else {
      isNearEdge = position.pixels >= position.maxScrollExtent - _scrollThreshold;
    }

    if (!isNearEdge) {
      _canTriggerNextPage = true;
      return;
    }

    if (!commonPaginationBloc.getIsLoading()) {
      _canTriggerNextPage = true;
    }

    if (commonPaginationBloc.getIsNoPageAvailable()) {
      return;
    }
    if (commonPaginationBloc.getIsLoading() || !_canTriggerNextPage) {
      return;
    }
    final holder = listAndPageHolder;
    if (holder != null &&
        holder.currentPage != commonPaginationBloc.currentPage) {
      return;
    }
    _canTriggerNextPage = false;
    onPageAvailableHit();
  }

  ScrollController get controller => _scrollController;

  void dispose() {
    _scrollController.dispose();
  }
}

class MyCursorScrollController {
  final ScrollController _scrollController;
  final CursorPaginationBloc cursorPaginationBloc;
  final VoidCallback onPageAvailableHit;
  final double _scrollThreshold;
  final bool isReverse;
  bool _canTriggerNextPage = true;

  final CursorDataHolder cursorDataHolder;

  MyCursorScrollController(
    this.cursorPaginationBloc,
    this.onPageAvailableHit, {
    double scrollThreshold = 200.0,
    this.isReverse = false,
    required this.cursorDataHolder,
  }) : _scrollController = ScrollController(),
       _scrollThreshold = scrollThreshold {
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;

    final bool isNearEdge;
    if (isReverse) {
      // Reversed list (e.g. chat): load more when near top (maxScrollExtent)
      final distanceToTop = position.maxScrollExtent - position.pixels;
      isNearEdge = distanceToTop <= _scrollThreshold;
    } else {
      // Normal list: load more when near bottom (maxScrollExtent)
      isNearEdge = position.pixels >= position.maxScrollExtent - _scrollThreshold;
    }

    if (!isNearEdge) {
      _canTriggerNextPage = true;
      return;
    }

    if (!cursorPaginationBloc.getIsLoading()) {
      _canTriggerNextPage = true;
    }

    if (cursorPaginationBloc.getIsNoPageAvailable()) {
      return;
    }
    if (cursorPaginationBloc.getIsLoading() || !_canTriggerNextPage) {
      return;
    }
    if (cursorDataHolder.nextCursor != cursorPaginationBloc.nextCursor) {
      return;
    }
    _canTriggerNextPage = false;
    onPageAvailableHit();
  }

  ScrollController get controller => _scrollController;

  void dispose() {
    _scrollController.dispose();
  }
}
