import 'dart:convert';

import 'package:cric_score/sync/cloud_store.dart';

/// An in-memory stand-in for Firestore with the same behaviour for the
/// operations sync uses: atomic batches, merges, server time, and queries
/// on one collection.
class MemoryCloudStore implements CloudStore {
  final Map<String, Map<String, Object?>> docs = {};
  DateTime Function() clock = DateTime.now;

  /// When set, every commit fails with this error, as when offline.
  Object? failWith;

  /// Sees every batch, for tests that check how writes are grouped.
  void Function(List<CloudWrite>)? onCommit;

  @override
  Future<Map<String, Object?>?> get(String path) async =>
      docs.containsKey(path) ? _copy(docs[path]!) : null;

  @override
  Future<List<CloudDoc>> query(
    String collection, {
    String? whereField,
    Object? isEqualTo,
    String? orderBy,
    int? limit,
  }) async {
    final depth = collection.split('/').length + 1;
    var found = [
      for (final e in docs.entries)
        if (e.key.startsWith('$collection/') &&
            e.key.split('/').length == depth &&
            (whereField == null || e.value[whereField] == isEqualTo))
          CloudDoc(e.key.split('/').last, _copy(e.value)),
    ];
    if (orderBy != null) {
      found.sort(
        (a, b) => (a.data[orderBy]! as Comparable<Object>).compareTo(
          b.data[orderBy]!,
        ),
      );
    }
    if (limit != null) found = found.take(limit).toList();
    return found;
  }

  @override
  Future<void> commit(List<CloudWrite> writes) async {
    if (failWith != null) throw failWith!;
    onCommit?.call(writes);
    final now = clock();
    for (final w in writes) {
      switch (w) {
        case CloudSet(:final path, :final data, :final merge):
          final value = {
            for (final e in data.entries)
              e.key: e.value is ServerTime ? now : e.value,
          };
          docs[path] = merge ? {...?docs[path], ...value} : value;
        case CloudDelete(:final path):
          docs.remove(path);
      }
    }
  }

  /// Like Firestore, readers get their own copy.
  static Map<String, Object?> _copy(Map<String, Object?> data) {
    final dates = {
      for (final e in data.entries)
        if (e.value is DateTime) e.key: e.value,
    };
    final rest = {
      for (final e in data.entries)
        if (e.value is! DateTime) e.key: e.value,
    };
    return {
      ...(jsonDecode(jsonEncode(rest)) as Map).cast<String, Object?>(),
      ...dates,
    };
  }
}
