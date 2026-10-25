import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_providers.dart';
import '../data/providers.dart';
import 'cloud_store.dart';
import 'sync_service.dart';

/// Tests override this with an in-memory store.
final cloudStoreProvider = Provider<CloudStore>(
  (ref) => FirestoreCloudStore(FirebaseFirestore.instance),
);

/// A random id for this installation, kept in the device database.
final deviceIdProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  final existing = await db.setting('deviceId');
  if (existing != null) return existing;
  final id = const Uuid().v4();
  await db.setSetting('deviceId', id);
  return id;
});

enum SyncStatus { idle, syncing, offline }

/// Keeps the cloud copy up to date while someone is signed in: a full sync
/// on sign-in and when the app comes back to the foreground, and an upload
/// shortly after every change.
class SyncController extends Notifier<SyncStatus> {
  StreamSubscription<void>? _changes;
  AppLifecycleListener? _lifecycle;
  Timer? _debounce;
  Timer? _retry;
  bool _running = false;
  bool _again = false;

  @override
  SyncStatus build() {
    final uid = ref.watch(currentUidProvider);
    ref.onDispose(_stop);
    if (uid == null) return SyncStatus.idle;

    final db = ref.watch(databaseProvider);
    // Any local change that needs uploading.
    _changes =
        (db.selectOnly(db.matches)
              ..addColumns([db.matches.id])
              ..where(db.matches.needsUpload))
            .watch()
            .listen((_) => _schedule());
    _lifecycle = AppLifecycleListener(onResume: () => _run(full: true));
    Future.microtask(() => _run(full: true));
    return SyncStatus.syncing;
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _run);
  }

  /// Runs one sync at a time; a request during a run queues one more.
  Future<void> _run({bool full = false}) async {
    if (_running) {
      _again = true;
      return;
    }
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    _running = true;
    state = SyncStatus.syncing;
    try {
      final service = SyncService(
        db: ref.read(databaseProvider),
        cloud: ref.read(cloudStoreProvider),
        uid: uid,
        deviceId: await ref.read(deviceIdProvider.future),
      );
      if (full) {
        await service.syncAll();
      } else {
        await service.pushDeletions();
        await service.pushPending();
      }
      state = SyncStatus.idle;
    } on Object catch (e) {
      debugPrint('Sync failed, will retry: $e');
      state = SyncStatus.offline;
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 30), () => _run(full: true));
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        _schedule();
      }
    }
  }

  /// Runs when the account changes or the app closes; safe to call twice.
  void _stop() {
    _changes?.cancel();
    _changes = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _debounce?.cancel();
    _debounce = null;
    _retry?.cancel();
    _retry = null;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);
