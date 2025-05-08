import 'package:shared_preferences/shared_preferences.dart';

const String _apiKeyKey = 'gemini_api_key';

/// Saves the Gemini API key to persistent storage.
Future<void> saveApiKey(String apiKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_apiKeyKey, apiKey);
}

/// Retrieves the Gemini API key from persistent storage.
///
/// Returns the API key as a String, or null if no key is found.
Future<String?> getApiKey() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_apiKeyKey);
}
