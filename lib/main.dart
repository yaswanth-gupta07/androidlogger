import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'app.dart';
import 'bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AndroidLoggerBootstrap());
}

class AndroidLoggerBootstrap extends StatefulWidget {
  const AndroidLoggerBootstrap({super.key});

  @override
  State<AndroidLoggerBootstrap> createState() => _AndroidLoggerBootstrapState();
}

class _AndroidLoggerBootstrapState extends State<AndroidLoggerBootstrap> {
  AppScope? _scope;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final scope = await buildAppScope();
      if (!mounted) {
        scope.dispose();
        return;
      }
      setState(() => _scope = scope);
    } catch (error, stackTrace) {
      developer.log(
        'Unable to start Android Logger',
        name: 'bootstrap',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _scope?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    if (scope != null) {
      return AndroidLoggerApp(scope: scope);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6E6A)),
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _failed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Unable to start Android Logger.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading device information...'),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
