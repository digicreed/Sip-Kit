import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

import 'softphone_state.dart';
import 'screens/activation_screen.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SipKitDemoApp());
}

class SipKitDemoApp extends StatelessWidget {
  const SipKitDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SoftphoneState(),
      child: MaterialApp(
        title: 'SipKit Demo Softphone',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
          useMaterial3: true,
        ),
        home: const _RootRouter(),
      ),
    );
  }
}

class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SoftphoneState>();
    if (state.activationState == ActivationState.active) {
      return const HomeScreen();
    }
    return const ActivationScreen();
  }
}
