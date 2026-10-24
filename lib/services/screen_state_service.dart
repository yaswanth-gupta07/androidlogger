import '../models/detected_event.dart';
import '../models/event_type.dart';

/// Screen on/off plus the public USER_PRESENT signal.
///
/// The first observed on/off value is a baseline and is not logged as a
/// change. Later transitions are logged. USER_PRESENT is Android's supported
/// notice that the user dismissed the keyguard. It does not reveal lock-screen
/// content, and it is only delivered while this process is alive.
class ScreenStateService {
  ScreenStateService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  String? _display;
  DateTime? _lastPresent;

  List<DetectedEvent> consume(String state) {
    switch (state) {
      case 'on':
      case 'off':
        final previous = _display;
        _display = state;
        if (previous == null || previous == state) {
          return const [];
        }
        return [
          DetectedEvent(
            type: EventType.screen,
            description: state == 'on'
                ? 'Screen turned on'
                : 'Screen turned off',
          ),
        ];
      case 'user_present':
        final current = _now();
        final last = _lastPresent;
        if (last != null &&
            current.difference(last) < const Duration(seconds: 2)) {
          return const [];
        }
        _lastPresent = current;
        return const [
          DetectedEvent(
            type: EventType.screen,
            description: 'User present after lock screen',
          ),
        ];
      default:
        return const [];
    }
  }
}
