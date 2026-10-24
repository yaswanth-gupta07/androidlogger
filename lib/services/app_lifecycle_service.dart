import 'package:flutter/widgets.dart';

import '../models/detected_event.dart';
import '../models/event_type.dart';

/// Maps Flutter lifecycle states to one log line per real transition.
class LifecycleInterpreter {
  AppLifecycleState? _last;

  DetectedEvent? consume(AppLifecycleState state) {
    if (_last == state) {
      return null;
    }
    _last = state;
    final description = switch (state) {
      AppLifecycleState.resumed => 'Application resumed',
      AppLifecycleState.inactive => 'Application inactive',
      AppLifecycleState.paused => 'Application paused',
      AppLifecycleState.hidden => 'Application hidden',
      AppLifecycleState.detached => 'Application stopped',
    };
    return DetectedEvent(type: EventType.app, description: description);
  }
}

class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService({required this.onEvent, this.onResumed});

  final void Function(DetectedEvent event) onEvent;
  final void Function()? onResumed;
  final LifecycleInterpreter interpreter = LifecycleInterpreter();
  bool _attached = false;

  void attach() {
    if (_attached) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
  }

  void detach() {
    if (!_attached) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final event = interpreter.consume(state);
    if (event != null) {
      onEvent(event);
    }
    if (state == AppLifecycleState.resumed) {
      onResumed?.call();
    }
  }
}
