import '../db/network/response/custom_pagination.dart';
import 'common_base_bloc.dart';
import 'model/list_and_page_holder.dart';

/// Shared offset-pagination behavior for screens that need local list syncing.
///
/// It keeps one bloc-owned visible list, dedupes paginated results by item key,
/// and can emit a fresh success state after local upsert/remove operations.
abstract class LocalSyncPaginationBloc<ItemType>
    extends
        CommonPaginationBloc<
          CommonEvent,
          CommonState,
          CustomPagination<ItemType>
        > {
  LocalSyncPaginationBloc(super.initialState);

  final ListAndPageHolder<ItemType> listData = ListAndPageHolder<ItemType>();
  CustomPagination<ItemType>? saveResponse;

  /// Must return a stable, non-null identity for each item.
  String itemIdentity(ItemType item);

  @override
  void doActionBeforeEmitSuccessWithPaginationState(
    SuccessWithPaginationState<CustomPagination<ItemType>> state,
  ) {
    final response = state.data;
    final mergedItems = _mergePageItems(
      existingItems: state.hasCleared ? <ItemType>[] : listData.list,
      incomingItems: response.data ?? <ItemType>[],
    );

    _storeLocalSnapshot(items: mergedItems, responseSource: response);
  }

  bool upsertLocalItem(
    ItemType item, {
    bool insertAtStart = false,
    bool emitState = true,
    bool incrementTotalOnInsert = false,
  }) {
    final items = List<ItemType>.from(listData.list);
    final key = itemIdentity(item);
    final index = items.indexWhere((existing) => itemIdentity(existing) == key);

    if (index >= 0) {
      items[index] = item;
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
    final items = List<ItemType>.from(listData.list);
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
    CustomPagination<ItemType>? responseSource,
  }) {
    _storeLocalSnapshot(items: items, responseSource: responseSource);
    if (emitState) {
      emitCurrentLocalData(hasCleared: hasCleared);
    }
  }

  void clearLocalItems({bool resetPaginationState = false}) {
    listData.list = [];
    listData.currentPage = 0;
    saveResponse = null;

    if (resetPaginationState) {
      currentPage = 0;
      totalPage = 0;
      nextPage = '';
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
      SyncLocalPaginationStateEvent<CustomPagination<ItemType>>(
        data: response,
        hasCleared: hasCleared,
      ),
    );
  }

  List<ItemType> _mergePageItems({
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
        mergedItems[existingIndex] = incoming;
      }
    }

    return mergedItems;
  }

  void _storeLocalSnapshot({
    required List<ItemType> items,
    CustomPagination<ItemType>? responseSource,
  }) {
    listData.list = items;
    listData.currentPage = currentPage;

    final source = responseSource ?? saveResponse;
    if (source == null) {
      return;
    }

    saveResponse = CustomPagination<ItemType>.fromJson(
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
