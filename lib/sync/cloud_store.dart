import 'package:cloud_firestore/cloud_firestore.dart';

/// Marks a field to be set to the server's clock when written.
final class ServerTime {
  const ServerTime();
}

const serverTime = ServerTime();

/// One write in an atomic batch. Paths alternate collection and document,
/// e.g. `matches/abc/events/000001`.
sealed class CloudWrite {
  const CloudWrite(this.path);

  final String path;
}

final class CloudSet extends CloudWrite {
  const CloudSet(super.path, this.data, {this.merge = false});

  /// Values may be JSON types, [DateTime] or [serverTime].
  final Map<String, Object?> data;
  final bool merge;
}

final class CloudDelete extends CloudWrite {
  const CloudDelete(super.path);
}

final class CloudDoc {
  const CloudDoc(this.id, this.data);

  final String id;

  /// Timestamps come back as [DateTime].
  final Map<String, Object?> data;
}

/// The few cloud operations sync needs, so it can be tested without
/// Firebase.
abstract interface class CloudStore {
  Future<Map<String, Object?>?> get(String path);

  /// Documents directly in [collection], optionally filtered on one field,
  /// ordered by one field and limited.
  Future<List<CloudDoc>> query(
    String collection, {
    String? whereField,
    Object? isEqualTo,
    String? orderBy,
    int? limit,
  });

  /// Applies [writes] all together or not at all.
  Future<void> commit(List<CloudWrite> writes);
}

class FirestoreCloudStore implements CloudStore {
  FirestoreCloudStore(this._fs);

  final FirebaseFirestore _fs;

  @override
  Future<Map<String, Object?>?> get(String path) async {
    final snap = await _fs.doc(path).get();
    return snap.exists ? _fromFirestore(snap.data()!) : null;
  }

  @override
  Future<List<CloudDoc>> query(
    String collection, {
    String? whereField,
    Object? isEqualTo,
    String? orderBy,
    int? limit,
  }) async {
    Query<Map<String, Object?>> q = _fs.collection(collection);
    if (whereField != null) q = q.where(whereField, isEqualTo: isEqualTo);
    if (orderBy != null) q = q.orderBy(orderBy);
    if (limit != null) q = q.limit(limit);
    final snap = await q.get();
    return [
      for (final d in snap.docs) CloudDoc(d.id, _fromFirestore(d.data())),
    ];
  }

  @override
  Future<void> commit(List<CloudWrite> writes) {
    final batch = _fs.batch();
    for (final w in writes) {
      switch (w) {
        case CloudSet(:final path, :final data, :final merge):
          batch.set(
            _fs.doc(path),
            _toFirestore(data),
            SetOptions(merge: merge),
          );
        case CloudDelete(:final path):
          batch.delete(_fs.doc(path));
      }
    }
    return batch.commit();
  }

  static Map<String, Object?> _toFirestore(Map<String, Object?> data) => {
    for (final e in data.entries) e.key: _valueTo(e.value),
  };

  static Object? _valueTo(Object? v) => switch (v) {
    ServerTime() => FieldValue.serverTimestamp(),
    DateTime() => Timestamp.fromDate(v),
    Map() => {for (final e in v.entries) e.key as String: _valueTo(e.value)},
    List() => [for (final x in v) _valueTo(x)],
    _ => v,
  };

  static Map<String, Object?> _fromFirestore(Map<String, Object?> data) => {
    for (final e in data.entries) e.key: _valueFrom(e.value),
  };

  static Object? _valueFrom(Object? v) => switch (v) {
    Timestamp() => v.toDate(),
    Map() => {for (final e in v.entries) e.key as String: _valueFrom(e.value)},
    List() => [for (final x in v) _valueFrom(x)],
    _ => v,
  };
}
