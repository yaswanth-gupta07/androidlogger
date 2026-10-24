import 'dart:async';

import 'package:flutter/material.dart';

/// Rebuilds [builder] once a second so relative times stay current.
class NowBuilder extends StatefulWidget {
  const NowBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<NowBuilder> createState() => _NowBuilderState();
}

class _NowBuilderState extends State<NowBuilder> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
