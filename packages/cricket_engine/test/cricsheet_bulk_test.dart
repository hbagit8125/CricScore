// Replays every Cricsheet match in a local folder. Not part of CI; run with
//   CRICSHEET_DIR=/path/to/unzipped/json dart test test/cricsheet_bulk_test.dart
@Tags(['bulk'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/cricsheet.dart';

void main() {
  final dir = Platform.environment['CRICSHEET_DIR'];
  test(
    'replay every match in CRICSHEET_DIR',
    () {
      final files =
          Directory(dir!)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.json'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      var ok = 0;
      var skipped = 0;
      final failures = <String, List<String>>{};
      final corrections = <String, int>{};
      for (final f in files) {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final r = replayCricsheet(f.path, json);
        r.corrections.forEach(
          (k, v) => corrections.update(k, (n) => n + v, ifAbsent: () => v),
        );
        if (r.skipped != null) {
          skipped++;
        } else if (r.ok) {
          ok++;
        } else {
          failures[f.path] = r.mismatches;
        }
      }
      final out = StringBuffer()
        ..writeln(
          'matches: ${files.length}, ok: $ok, skipped: $skipped, failed: ${failures.length}',
        )
        ..writeln('corrections: $corrections');
      for (final e in failures.entries) {
        out.writeln('${e.key}: ${e.value.take(3).join(' | ')}');
      }
      File(
        Platform.environment['CRICSHEET_REPORT'] ?? 'cricsheet_report.txt',
      ).writeAsStringSync(out.toString());
      // ignore: avoid_print
      print(out.toString().split('\n').take(3).join('\n'));
    },
    skip: dir == null ? 'Set CRICSHEET_DIR to run' : false,
    timeout: Timeout.none,
  );
}
