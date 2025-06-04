import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static String get serverUrl => dotenv.env['API_URL'] ?? 'http://localhost:8000';
} 