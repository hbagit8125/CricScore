import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

void main() {
  test('schema version starts at 1', () {
    expect(engineSchemaVersion, 1);
  });
}
