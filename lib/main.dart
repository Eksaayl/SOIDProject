// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'state/selection_model.dart';
import 'login/login.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => SelectionModel(),
      child: const AuthWatcher(),
    ),
  );
}

/// Listens to FirebaseAuth changes and clears the model on sign-out.
class AuthWatcher extends StatefulWidget {
  const AuthWatcher({super.key});
  @override
  State<AuthWatcher> createState() => _AuthWatcherState();
}

class _AuthWatcherState extends State<AuthWatcher> {
  User? _prev;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_prev != null && user == null) {
        context.read<SelectionModel>().setAll({});
      }
      _prev = user;
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MyApp();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Landing Page',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xff021e84),
      ),
      debugShowCheckedModeBanner: false,
      home: const LoginPage(),

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],

      supportedLocales: const [
        Locale('en'),
      ],
    );
  }
}

