import 'dart:convert';
import 'package:http/http.dart' as http;

class GfwAuthService {
  final String email = "rictorJunior8@gmail.com";
  final String password = "C#AiGT9static22"; 
  final String baseUrl = "https://data-api.globalforestwatch.org";

  Future<String?> getApiKey() async {
    try {
      // STEP 1: Get Token
      final tokenResp = await http.post(
        Uri.parse("$baseUrl/auth/token"),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': email, 'password': password},
      );

      if (tokenResp.statusCode != 200) return null;
      final accessToken = jsonDecode(tokenResp.body)['data']['access_token'];

      // STEP 2: Create/Fetch API Key
      final apiKeyResp = await http.post(
        Uri.parse("$baseUrl/auth/apikey"),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "alias": "EcoLens_App",
          "email": email,
          "organization": "EcoLens",
          "domains": [] 
        }),
      );

      final apiData = jsonDecode(apiKeyResp.body);

      // --- FIXED LOGIC BASED ON YOUR LOG ---
      if (apiData['status'] == 'success') {
        // GFW returns a direct object for this endpoint
        return apiData['data']['api_key']; 
      }
      return null;
    } catch (e) {
      print("🚨 GFW Error: $e");
      return null;
    }
  }
}