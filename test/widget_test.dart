import 'package:android_logger/models/event_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('event categories stay limited to the seven supported types', () {
    expect(EventType.values.map((type) => type.name), [
      'battery',
      'network',
      'charging',
      'app',
      'screen',
      'audio',
      'time',
    ]);
  });
}
