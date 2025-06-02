import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'state/selection_model.dart';
import 'login/login.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'landing.dart';
import 'config/firebase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: "assets/.env");
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => SelectionModel(),
      child: const AuthWatcher(),
    ),
  );
}

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
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        Widget home;
        if (snapshot.connectionState == ConnectionState.waiting) {
          home = const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasData) {
          home = const Landing();
        } else {
          home = const LoginPage();
        }

        return MaterialApp(
          title: 'Landing Page',
          theme: ThemeData(
            scaffoldBackgroundColor: const Color(0xff021e84),
          ),
          debugShowCheckedModeBanner: false,
          home: home,
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
      },
    );
  }
}

