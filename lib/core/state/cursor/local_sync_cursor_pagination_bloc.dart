import '../common_base_bloc.dart';
import 'cursor_pagination_bloc.dart';
import 'cursor_pagination_response.dart';

/// Shared cursor-pagination behavior for screens that need local list syncing.
///
/// It keeps one bloc-owned visible item list, dedupes paginated results by item key,
/// and can emit a fresh success state after local upsert/remove/replace operations.
abstract class LocalSyncCursorPaginationBloc<ItemType>
    extends
        CursorPaginationBloc<
          CommonEvent,
          CommonState,
          CursorPaginationResponse<ItemType>
        > {
  LocalSyncCursorPaginationBloc(super.initialState);

  final CursorDataHolder<ItemType> cursorPageHolder = CursorDataHolder<ItemType>();
  CursorPaginationResponse<ItemType>? saveResponse;

  /// Must return a stable, non-null identity for each item.
  String itemIdentity(ItemType item);

  @override
  void doActionBeforeEmitSuccessWithPaginationState(
    SuccessWithPaginationState<CursorPaginationResponse<ItemType>> state,
  ) {
    final response = state.data;
    saveResponse = response;
    final mergedItems = _mergeCursorItems(
      existingItems: state.hasCleared ? <ItemType>[] : cursorPageHolder.items,
      incomingItems: response.data ?? <ItemType>[],
    );

    _storeLocalSnapshot(items: mergedItems, responseSource: response);
  }

  /// Merges an incoming item into an existing item with the same identity.
  /// Subclasses can override this to preserve monotonic status flags (e.g. delivered, seen).
  ItemType mergeItem(ItemType existing, ItemType incoming) => incoming;

  bool upsertLocalItem(
    ItemType item, {
    bool insertAtStart = true,
    bool emitState = true,
    bool incrementTotalOnInsert = false,
  }) {
    final items = List<ItemType>.from(cursorPageHolder.items);
    final key = itemIdentity(item);
    final index = items.indexWhere((existing) => itemIdentity(existing) == key);

    if (index >= 0) {
      items[index] = mergeItem(items[index], item);
    } else if (insertAtStart) {
      items.insert(0, item);
      if (incrementTotalOnInsert) {
        _adjustTotal(1);
      }
    } else {
      items.add(item);
      if (incrementTotalOnInsert) {
        _adjustTotal(1);
      }
    }

    _storeLocalSnapshot(items: items);
    if (emitState) {
      emitCurrentLocalData();
    }
    return true;
  }

  bool removeLocalItemByIdentity(
    String identity, {
    bool emitState = true,
    bool decrementTotalOnRemove = false,
  }) {
    final items = List<ItemType>.from(cursorPageHolder.items);
    final previousLength = items.length;
    items.removeWhere((item) => itemIdentity(item) == identity);

    final removedCount = previousLength - items.length;
    if (removedCount == 0) {
      return false;
    }

    if (decrementTotalOnRemove) {
      _adjustTotal(-removedCount);
    }
    _storeLocalSnapshot(items: items);
    if (emitState) {
      emitCurrentLocalData();
    }
    return true;
  }

  void replaceLocalItems(
    List<ItemType> items, {
    bool emitState = true,
    bool hasCleared = true,
    CursorPaginationResponse<ItemType>? responseSource,
  }) {
    _storeLocalSnapshot(items: items, responseSource: responseSource);
    if (emitState) {
      emitCurrentLocalData(hasCleared: hasCleared);
    }
  }

  void clearLocalItems({bool resetPaginationState = false}) {
    cursorPageHolder.items = [];
    cursorPageHolder.nextCursor = null;
    saveResponse = null;

    if (resetPaginationState) {
      resetCursorPaginationState();
    }
  }

  @override
  void onReset(ResetEvent event) {
    super.onReset(event);
    if (event.clearsData) {
      clearLocalItems();
    }
  }

  void emitCurrentLocalData({bool hasCleared = false}) {
    final response = saveResponse;
    if (response == null) {
      return;
    }

    add(
      SyncLocalPaginationStateEvent<CursorPaginationResponse<ItemType>>(
        data: response,
        hasCleared: hasCleared,
      ),
    );
  }

  List<ItemType> _mergeCursorItems({
    required Iterable<ItemType> existingItems,
    required Iterable<ItemType> incomingItems,
  }) {
    final mergedItems = List<ItemType>.from(existingItems);
    final indexByIdentity = <String, int>{};

    for (var i = 0; i < mergedItems.length; i++) {
      indexByIdentity[itemIdentity(mergedItems[i])] = i;
    }

    for (final incoming in incomingItems) {
      final identity = itemIdentity(incoming);
      final existingIndex = indexByIdentity[identity];

      if (existingIndex == null) {
        indexByIdentity[identity] = mergedItems.length;
        mergedItems.add(incoming);
      } else {
        mergedItems[existingIndex] = mergeItem(mergedItems[existingIndex], incoming);
      }
    }

    return mergedItems;
  }

  void _storeLocalSnapshot({
    required List<ItemType> items,
    CursorPaginationResponse<ItemType>? responseSource,
  }) {
    cursorPageHolder.items = items;
    cursorPageHolder.nextCursor = nextCursor;
    final source = responseSource ?? saveResponse;
    if (source == null) {
      return;
    }

    saveResponse = CursorPaginationResponse<ItemType>.fromJson(
      json: source.toJson(),
      fromJsonFactory: source.fromJsonFactory,
      toJsonFactory: source.toJsonFactory,
    )..data = List<ItemType>.from(items);
  }

  void _adjustTotal(int delta) {
    final currentTotal = saveResponse?.total;
    if (currentTotal == null) {
      return;
    }
    final nextTotal = currentTotal + delta;
    saveResponse?.total = nextTotal < 0 ? 0 : nextTotal;
  }
}
