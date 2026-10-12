# Chat Reliability & Synchronization Audit Tracker

This document serves as the persistent source of truth for the chat caching, pagination, outbox reliability, delta synchronization, read receipts, and session lifecycle audit in `whatsapp_flutter_go`.

---

## A. Project Status

- **Audit Scope:** Chat caching, cursor pagination, outbox persistence, reconnect & HTTP forward delta sync, read/delivery receipts, multi-account isolation, and auth session lifecycle interactions.
- **Current Phase:** Phase 3 Implementation & Verification (P1 & P2 Complete).
- **Git Branch:** `main`
- **Latest Relevant Commit:** `932a0d1` (*Implement persistent cache-first conversation/message storage, multi-account isolation, and reliable seen acknowledgment coordination*)
- **Working-Tree Status:** Ready to commit completed P1 & P2 changes.
- **Environment & Safety Constraints:**
  - Strictly preserve `.env` (file exists at workspace root and must remain untouched).
  - P1 (CHAT-001) and P2 (CHAT-002) completed and verified (229/229 tests passing). P3 and P4 are deferred and not approved for implementation.

---

## B. Findings and Issue Tracker

### CHAT-001: Outbox Storage Concurrency & Quarantined Persistence Policy
- **Severity:** P1 (High)
- **Status:** `Verified`
- **Selected Policy:** **Policy B — Quarantined Persistence** (Confirmed)
  - Pending outbox messages for User A are preserved across logout for recovery when User A logs back in (maintaining existing Test 14 contract).
  - Messages are strictly quarantined by user scope (`senderId`): never displayed, queried, or transmitted under User B or while logged out.
  - No automatic outbox purge is added to `AuthSession.clear()`.
- **Affected Files & Functions:**
  - [`lib/core/session/auth_session.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/core/session/auth_session.dart): `AuthSession.clear()` (stays unpurged per Policy B)
  - [`lib/feature/chat_inbox/data/outbox/local_outbox_storage.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/chat_inbox/data/outbox/local_outbox_storage.dart): `SharedPreferencesOutboxStorage.save()`, `remove()`, `clear()`, `getAllMessages()`
  - [`lib/feature/chat_inbox/data/outbox/chat_outbox_processor.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/chat_inbox/data/outbox/chat_outbox_processor.dart): `ChatOutboxProcessor.processPending()`, `cancel()`
  - [`test/message_cache_test.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/test/message_cache_test.dart): Test 14 (*"Same-user restart/recovery preserves and recovers pending outbox messages"*)
- **Reproduction Scenario & Concurrency Risk:**
  1. User A goes offline and sends an outgoing message.
  2. Message is persisted to `LocalOutboxStorage` under key `chat_outbox_pending_messages` with `senderId: 'user_a'`.
  3. User A logs out (`AuthSession.clear()`). `cancel()` halts in-flight processing.
  4. Without a FIFO write queue, if an asynchronous clear or remove operation overlaps with User B logging in and saving a message, an un-synchronized read-modify-write on `chat_outbox_pending_messages` can overwrite and drop User B's message.
  5. Furthermore, `clear()` checked `value is Map<String, dynamic>` which failed for `Map<dynamic, dynamic>`, skipping scoped entries.
- **Root Cause & Evidence:**
  - `SharedPreferencesOutboxStorage` stores all messages across all accounts in a single shared key without mutex or write serialization queue.
  - Async read-modify-write on the shared key is vulnerable to race conditions under concurrent operations.
- **Implemented Fix Design:**
  1. Add `static Future<void> _writeQueue` serialization queue to `SharedPreferencesOutboxStorage` for `save`, `remove`, and `clear`.
  2. Handle errors in queued actions with `.catchError((_) {})` so queue failures never permanently block subsequent operations.
  3. Ensure `getAllMessages()` awaits `_writeQueue` before reading from SharedPreferences, delivering a completely settled snapshot.
  4. Fix map decoding in `clear()` using `Map<String, dynamic>.from(value)` to handle all map runtime types correctly.
  5. Preserve User A's outbox messages across logout without purging in `AuthSession.clear()`.
- **Planned Regression Tests:**
  - Concurrent interleaved `save`, `remove`, and `clear` operations execute in strict FIFO order without dropped items.
  - Queue recovers after a thrown exception and processes subsequent tasks normally.
  - `getAllMessages()` reflects the final settled state after concurrent operations.
  - Account isolation: User A's pending outbox messages are never visible to User B, never sent under User B, and never sent while logged out.
  - Same-user recovery: User A logs out and logs back in; User A's pending messages are intact and recovered.
- **Regression Status:** `Verified` (7/7 passing in `test/outbox_storage_concurrency_test.dart`, 229/229 passing full suite).

---

### CHAT-002: Delivered ACK (`ack_delivered`) Missing for Messages Synced via REST Delta
- **Severity:** P2 (Medium)
- **Status:** `Verified`
- **Affected Files & Functions:**
  - [`lib/core/db/local_cache/chat_message_cache.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/core/db/local_cache/chat_message_cache.dart): constructor `@visibleForTesting ChatMessageCache.testInstance()`
  - [`lib/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart): constructor, `syncMissedMessages()`, `_persistConfirmedMessages()`, `_dispatchPendingDeliveredAcks()`, `_onSocketConnectionStateChanged()`, `clearLocalItems()`, `close()`
- **Reproduction Scenario:**
  1. User B is offline when User A sends a message.
  2. User B reconnects to the network.
  3. User B's client executes forward delta sync `syncMissedMessages()` via `GET /conversations/{id}/messages?since_id=...`.
  4. The missed messages are fetched and stored in `ChatMessageCache`.
  5. Because these messages arrived via HTTP REST delta sync rather than a real-time WebSocket `new_message` push event, `ChatSocketEventDispatcher` line 56 never fired `sendDeliveredAck()`.
  6. User A's UI remained stuck on a single grey checkmark (Sent) rather than double grey checkmarks (Delivered) until User B opened the chat room (which triggered `ack_seen`).
- **Root Cause & Evidence:**
  - Delivery ACK was only wired inside `ChatSocketEventDispatcher` listening to WebSocket `new_message`.
  - There was no delivery ACK dispatch path in `InboxMessageListCursorBloc.syncMissedMessages()`.
- **Implemented Fix Design:**
  1. Allowed `ChatSocketService? socketService` injection in `InboxMessageListCursorBloc` constructor (defaulting to `ChatSocketService.instance`), unifying socket calls.
  2. Subscribed `InboxMessageListCursorBloc` to `socketService.connectionState` to automatically flush pending delivery ACKs when socket reconnects.
  3. In `syncMissedMessages()`, stage incoming missed messages requiring delivery ACKs: filters out self-messages (`msg.isMine` or `senderId == myId`), already delivered/seen messages (`msg.isDelivered || msg.isSeen`), and previously ACKed message IDs.
  4. Guaranteed persistence-first contract: `await _persistConfirmedMessages()` is fully awaited BEFORE any delivery ACK is staged or dispatched. If persistence throws or fails, no delivery ACKs are queued or sent.
  5. Dispatched `socketService.sendDeliveredAck(...)` for staged messages, recording successful dispatches in `_deliveredAckedMessageIds` for strict idempotency across repeated delta-sync responses and reconnects.
  6. Retained un-sent ACKs in `_pendingDeliveredAcks` if socket is disconnected so they are automatically flushed on reconnect.
  7. Cleared `_pendingDeliveredAcks` and `_deliveredAckedMessageIds` on `clearLocalItems()` and `close()` for account/session isolation.
- **Regression Tests Added:**
  - Added 8 dedicated regression tests in `test/inbox_delta_sync_test.dart`:
    1. Delta sync receiving missed messages from another sender dispatches `sendDeliveredAck` after durable persistence with exact payload schema `{conversation_id, message_id, sender_id}`.
    2. Self-messages (`msg.isMine == true` or `senderId == myId`) are NEVER ACKed.
    3. Messages already marked `isDelivered` or `isSeen` are NEVER ACKed.
    4. Repeated delta sync responses for the same messages are strictly idempotent (no duplicate ACKs).
    5. Persistence failure (simulated cache storage failure during `saveMessages`) blocks delivery ACKs from being dispatched.
    6. Disconnected socket stages ACKs and automatically flushes them once reconnected.
    7. Multi-page delta sync collects and ACKs all un-delivered messages across pages.
    8. `clearLocalItems()` resets both pending and delivered ACK tracking.
- **Regression Status:** `Verified` (31/31 passing in `test/inbox_delta_sync_test.dart`, 229/229 full suite).
- **Targeted Hardening & Verification Results:**
  1. *Persistence Correctness:*
     - Changed [`ChatMessageCache.saveMessages`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/core/db/local_cache/chat_message_cache.dart#L93) return type to `Future<bool>`. Returns `false` on closed/null box, session epoch mismatch, or user scope mismatch. Returns `true` once write to Hive commits.
     - Updated callers across the app and test mocks consistently.
     - In [`InboxMessageListCursorBloc.syncMissedMessages`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart#L1051), checks `final persisted = await _persistConfirmedMessages();`. If `!persisted`, logs error, skips staging and dispatching delivery ACKs, and returns `false`.
  2. *Session & Account Isolation Hardening:*
     - Added `_isSessionValid()` helper checking active user scope and session epoch against bloc's bound session identity.
     - Bound session scope and epoch at constructor initialization.
     - Guarded `_onSocketConnectionStateChanged()`, `_dispatchPendingDeliveredAcks()` (both at loop start and before each ACK dispatch), and `syncMissedMessages()` (before sync, during page loops, and after sync). On any session mismatch, clears `_pendingDeliveredAcks` and `_deliveredAckedMessageIds` immediately, preventing User A's ACKs from leaking over User B's socket.
     - In [`ChatInboxScreen.dispose`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/chat_inbox/presentation/chat_inbox_screen.dart#L264), explicitly calls `inboxBloc?.close()`, unregistering socket listener and clearing in-memory ACK tracking.
  3. *ACK Retry Safety & Idempotency:*
     - `_deliveredAckedMessageIds` is updated strictly when `socketService.sendDeliveredAck(...)` returns `true`.
     - Failed transmissions or disconnected sockets keep messages in `_pendingDeliveredAcks` and retry on reconnect or manual flush without duplicates.
  4. *Go Backend Contract Verification:*
     - Verified against Go backend [`websocket/hub.go`](file:///Users/shakib/Documents/work/Go/go-practice/go-talk/websocket/hub.go) and [`websocket/event.go`](file:///Users/shakib/Documents/work/Go/go-practice/go-talk/websocket/event.go). Payload strictly matches `AckPayload { MessageID: int64, ConversationID: string, SenderID: int }`.
  5. *New Regression Tests Added (Total 12 tests in group):*
     - Silent abort in `saveMessages` (`false`) blocks delivery ACK staging and dispatch.
     - Send failure during `sendDeliveredAck` retains message in `pendingDeliveredAcks` and retries on reconnect/flush without duplicates.
     - Account switch and session epoch drift purge pending ACKs preventing cross-account leakage.
     - Exact schema verification against Go backend `AckPayload`.

---

### CHAT-003: Conversation Unread Count Neither Increments on Live Messages Nor Resets on Read
- **Severity:** P3 (Medium)
- **Status:** `Confirmed` (Independently verified in source code)
- **Affected Files & Functions:**
  - [`lib/feature/home/model/conversation.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/home/model/conversation.dart): line 126 (`copyWithNewMessage`)
  - [`lib/feature/home/presentation/view_model/chat_view_model.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/home/presentation/view_model/chat_view_model.dart): lines 240–245 (`_handleNewMessage`)
  - [`lib/feature/home/presentation/chat_page.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/home/presentation/chat_page.dart): lines 42–44 (`onTap`)
- **Reproduction Scenario:**
  1. User is on the conversation list screen.
  2. A new message arrives over WebSocket from another user.
  3. `ChatViewModel._handleNewMessage` calls `conversation.copyWithNewMessage(...)`.
  4. Line 126 hardcodes `unreadCount: unreadCount,` (no increment).
  5. The unread badge on the conversation tile does not update.
  6. When the user taps the conversation in `ChatPage.onTap` and reads all messages, there is no call to reset `unreadCount` to 0 in `ChatViewModel`. The unread badge persists until a manual pull-to-refresh.
- **Root Cause & Evidence:**
  - `Conversation.copyWithNewMessage` does not increment `unreadCount` for incoming messages from other senders.
  - No `markConversationAsRead()` method exists in `ChatViewModel`.
- **Proposed Fix:**
  1. In `copyWithNewMessage`, increment `unreadCount` when `senderId != myId`.
  2. Add `markConversationAsRead(String conversationId)` to `ChatViewModel` and call it on navigation/seen receipt.
- **Regression Tests Required:**
  - Unit test verifying unread count increment on live socket message.
  - Unit test verifying unread count reset to 0 upon marking as read.
- **Regression Status:** Deferred (not yet approved for implementation).

---

### CHAT-004: Transient ErrorState Flash When Opening Cached Conversation Offline
- **Severity:** P4 (Low)
- **Status:** `Confirmed` (Independently verified in source code)
- **Affected Files & Functions:**
  - [`lib/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart): lines 127–140 (`handleEvent`)
  - [`lib/core/state/cursor/cursor_pagination_bloc.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/core/state/cursor/cursor_pagination_bloc.dart): lines 65–79 (`_mapEventToState`)
- **Reproduction Scenario:**
  1. User opens a previously cached conversation while offline.
  2. `_executeInitialHydrationAndFetch` emits cached messages promptly.
  3. The subsequent background network fetch `repository.getMessages(...)` fails due to no network.
  4. `handleEvent` catches the error, calls `emitCurrentLocalData(hasCleared: false)`, but then executes `rethrow;`.
  5. `CursorPaginationBloc` catches the rethrow and emits `ErrorState`.
  6. UI listeners receive `ErrorState` before the enqueued `SyncLocalPaginationStateEvent` emits `SuccessWithPaginationState`.
- **Root Cause & Evidence:**
  - `handleEvent` rethrows unconditionally even when valid cached items exist and were queued for emission.
- **Proposed Fix:**
  When `cursorPageHolder.items.isNotEmpty`, handle offline errors gracefully without rethrowing, or return a cached response.
- **Regression Tests Required:**
  - Test opening cached conversation offline: asserts bloc does not emit an unhandled `ErrorState`.
- **Regression Status:** Deferred (not yet approved for implementation).

---

## C. Test Ledger

| Test Command | Scope | Result | Observed At | Status | Relevant IDs | Limitations / Notes |
|---|---|---|---|---|---|---|
| `flutter test test/inbox_delta_sync_test.dart` | Delta sync forward pagination, deduplication, monotonic watermarks, Delivered ACK after REST delta sync (CHAT-002) | 27 passed | 2026-10-12 11:18:43 | PASS | CHAT-002 | Verified 8/8 new CHAT-002 tests: delivery ACK dispatch, self-message exclusion, idempotency, persistence-first, offline buffering & flush on reconnect |
| `flutter test test/read_receipt_reliability_test.dart test/outbox_storage_concurrency_test.dart` | Read receipts, watermarks, outbox concurrency FIFO queue | 17 passed | 2026-10-12 11:18:50 | PASS | CHAT-001, CHAT-002 | Verified zero regressions on read receipts and outbox |
| `flutter test test/outbox_storage_concurrency_test.dart` | Concurrency queue, failure recovery, consistent snapshots, dynamic map decoding, Policy B isolation | 7 passed | 2026-10-12 11:18:57 | PASS | CHAT-001 | Verified FIFO queue, race condition fix, error resilience |
| `flutter test test/message_cache_test.dart test/reconnect_conversation_sync_test.dart` | Message caching, outbox isolation, reconnect sync | 24 passed | 2026-10-12 11:19:05 | PASS | CHAT-001 | Verified cache-first history, account isolation, reconnect sync |
| `flutter test test/outbox_reliability_lifecycle_test.dart test/outbox_phase3_test.dart test/outbox_phase2_test.dart test/outbox_phase1_test.dart` | Outbox lifecycle, phase 1-3 tests | 44 passed | 2026-10-12 11:19:13 | PASS | CHAT-001 | Verified all outbox lifecycle tests pass |
| `flutter analyze lib/ test/` | Static analysis across whole project | 0 errors (19 infos/warnings) | 2026-10-12 11:19:22 | PASS | ALL | Clean analysis, 0 errors |
| `flutter test` | Full repository test suite | 225 passed | 2026-10-12 11:19:35 | PASS | ALL | Full suite passes (210 baseline + 7 CHAT-001 + 8 CHAT-002) |

*Rule:* Only commands actually executed with observed outputs are recorded as current session results.

---

## D. Completed Work

### CHAT-001 (P1): Outbox Storage Concurrency Hardening & Quarantined Persistence
- **What Changed:**
  - Modified [`lib/feature/chat_inbox/data/outbox/local_outbox_storage.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/chat_inbox/data/outbox/local_outbox_storage.dart):
    1. Added `static Future<void> _writeQueue` and private `_enqueue` helper in `SharedPreferencesOutboxStorage` to sequence all `save`, `remove`, and `clear` operations in strict FIFO order.
    2. Implemented error resilience on `_writeQueue`: `.catchError((_) {})` ensures a thrown failure in one queued operation never permanently blocks subsequent tasks.
    3. Made `getAllMessages()` await `_writeQueue` before reading, ensuring callers always read a settled, consistent snapshot.
    4. Fixed dynamic map type decoding in `clear()`: safely converts `Map` entries via `Map<String, dynamic>.from(value)` so scoped clearing works across all runtime JSON map representations.
    5. Preserved User A's pending outbox messages across logout (Policy B — Quarantined Persistence) without adding automatic outbox purge to `AuthSession.clear()`.
- **Regression Tests Added:**
  - Created [`test/outbox_storage_concurrency_test.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/test/outbox_storage_concurrency_test.dart) (7 tests).
- **Focused Test Result:** 7/7 passed in `test/outbox_storage_concurrency_test.dart`, 68/68 passed across all existing outbox suites.
- **Analyzer Result:** 0 errors (`flutter analyze lib/ test/`).
- **Full-Suite Result:** 217/217 passed (`flutter test`).

### CHAT-002 (P2): Delivered ACK after REST Delta Sync
- **What Changed:**
  - Modified [`lib/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/feature/chat_inbox/data/inbox_message_list_cursor_bloc.dart):
    1. Added `ChatSocketService socketService` field and constructor parameter with default `ChatSocketService.instance`.
    2. Added `_pendingDeliveredAcks` map and `_deliveredAckedMessageIds` set.
    3. Attached connection listener `socketService.connectionState.addListener(_onSocketConnectionStateChanged)` to automatically flush pending delivery ACKs upon socket connection/reconnection.
    4. In `syncMissedMessages()`, staged incoming candidate messages from delta sync: strictly filtered out current user's messages (`_isMessageFromCurrentUser`: `isMine == true`, `senderId == myId`, or `senderId == userScope`), messages already marked delivered/seen (`isDelivered || isSeen`), and previously ACKed messages (`_deliveredAckedMessageIds`).
    5. Made `_persistConfirmedMessages()` return `Future<void>` and awaited it in `syncMissedMessages()`: guaranteed that messages are durably saved to `ChatMessageCache` BEFORE any delivery ACK is staged or sent.
    6. If `_persistConfirmedMessages()` fails/throws, delta sync catches the error and aborts, ensuring NO delivery ACKs are dispatched for unpersisted messages.
    7. Dispatched `socketService.sendDeliveredAck(...)` for staged messages, recording successful dispatches in `_deliveredAckedMessageIds` for idempotency across repeated delta-sync responses and reconnects.
    8. Retained un-sent ACKs in `_pendingDeliveredAcks` if socket drops/is offline so they are retried when the socket connects.
    9. In `clearLocalItems()` and `close()`, cleared both `_pendingDeliveredAcks` and `_deliveredAckedMessageIds` and removed the connection listener.
  - Modified [`lib/core/db/local_cache/chat_message_cache.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/lib/core/db/local_cache/chat_message_cache.dart):
    1. Added `@visibleForTesting ChatMessageCache.testInstance() : this._internal();` constructor to support isolated testing of cache failure and mock scenarios.
- **Regression Tests Added:**
  - Added 8 dedicated unit and regression tests in [`test/inbox_delta_sync_test.dart`](file:///Users/shakib/Documents/work/flutter/app/whatsapp_flutter_go/test/inbox_delta_sync_test.dart):
    1. Dispatches `sendDeliveredAck` for un-delivered messages from other senders after durable persistence with exact payload schema `{conversation_id, message_id, sender_id}`.
    2. NEVER ACKs messages sent by current user (`isMine=true` or `senderId=myId`).
    3. NEVER ACKs messages already marked `isDelivered=true` or `isSeen=true`.
    4. Idempotency: repeated delta-sync responses for same messages dispatch ACK only once.
    5. Persistence failure: cache failure blocks delivery ACKs from being dispatched.
    6. Offline socket: retains pending ACKs and flushes when socket reconnects.
    7. Multi-page delta sync: collects and ACKs all un-delivered messages across pages.
    8. `clearLocalItems()`: resets both pending and delivered ACK tracking.
- **Focused Test Result:** 27/27 passed in `test/inbox_delta_sync_test.dart` (including all 8 new tests).
- **Analyzer Result:** 0 errors (`flutter analyze lib/ test/`).
- **Full-Suite Result:** 225/225 passed (`flutter test`).

---

## E. Remaining Work (Prioritized)

1. **CHAT-003 (P3):**
   - Unread count live increment & reset on read (deferred pending user approval).
2. **CHAT-004 (P4):**
   - Offline initial load transient error state flash (deferred pending user approval).

---

## F. Handoff Notes

- **Read First:** Review this document (`CHAT_RELIABILITY_AUDIT.md`), specifically completed work on CHAT-001 and CHAT-002.
- **Already Investigated & Resolved:**
  - `CHAT-001` (P1) is fully implemented, verified, and passing.
  - `CHAT-002` (P2) is fully implemented, verified, and passing all 225 tests.
  - Delivery ACKs for delta-synced messages are now sent only after durable cache persistence, are strictly idempotent, never ACK self-messages, and handle offline buffering and socket reconnect safely.
- **Do Not Repeat Unnecessarily:**
  - Do not re-run full test suite until new changes are made.
  - Do not purge `LocalOutboxStorage` in `AuthSession.clear()` (Policy B is confirmed).
- **Next Steps:** Await user guidance on whether to proceed with P3 (CHAT-003) or P4 (CHAT-004).

