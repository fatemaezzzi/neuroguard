// lib/core/services/sms_service.dart
// DEBUG BUILD — all assert() replaced with print().

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ── Fallback key (used in background isolate where rootBundle fails) ──────────
// Replace with your actual Fast2SMS API key.
const String _kApiKeyFallback = 'YOUR_FAST2SMS_API_KEY_HERE';
// ─────────────────────────────────────────────────────────────────────────────

class SmsService {
  static final SmsService _instance = SmsService._();
  factory SmsService() => _instance;
  SmsService._();

  static const _baseUrl = 'https://www.fast2sms.com/dev/bulkV2';

  Future<bool> sendAlert({
    required List<String> phones,
    required String message,
  }) async {
    print('==================================================');
    print('[SmsService] SMS FUNCTION CALLED');
    print('[SmsService] Sending SMS to: $phones');
    print('[SmsService] Message: $message');
    print('==================================================');

    if (phones.isEmpty) {
      print('[SmsService] ERROR: No phones provided — aborting.');
      return false;
    }

    final apiKey = await _loadApiKey();
    print('[SmsService] API KEY LENGTH: ${apiKey.length}');

    if (apiKey.isEmpty || apiKey == '7grJ80cRMlC5jIwQo4KBqDzx3PmkUG6SaVFWiL2fEuXAb1vHdZicWeF3MTCyJlfIOnadhuzYs5H7xrwN') {
      print('[SmsService] API KEY LOAD FAILED — key is empty or still placeholder.');
      print('[SmsService] → Set _kApiKeyFallback in sms_service.dart');
      print('[SmsService] → OR provide assets/fast2sms_key.txt');
      return false;
    }

    print('[SmsService] Firing HTTP POST to Fast2SMS...');

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'authorization': apiKey,
          'Content-Type':  'application/json',
          'cache-control': 'no-cache',
        },
        body: jsonEncode({
          'route':    'q',
          'message':  message,
          'language': 'english',
          'flash':    0,
          'numbers':  phones.join(','),
        }),
      );

      print('[SmsService] HTTP ${response.statusCode}: ${response.body}');

      if (response.statusCode == 200) {
        final body     = jsonDecode(response.body) as Map<String, dynamic>;
        final accepted = body['return'] == true;
        if (accepted) {
          print('[SmsService] SUCCESS — SMS accepted by Fast2SMS');
        } else {
          print('[SmsService] REJECTED by Fast2SMS: ${body['message']}');
        }
        return accepted;
      } else {
        print('[SmsService] Non-200 — SMS not sent.');
        return false;
      }
    } catch (e, st) {
      print('[SmsService] EXCEPTION: $e');
      print('[SmsService] STACK: $st');
      return false;
    }
  }

  Future<String> _loadApiKey() async {
    try {
      final key = await rootBundle.loadString('assets/fast2sms_key.txt');
      final trimmed = key.trim();
      if (trimmed.isNotEmpty) {
        print('[SmsService] API key loaded from asset file.');
        return trimmed;
      }
    } catch (_) {
      print('[SmsService] rootBundle unavailable (background isolate) — using fallback key.');
    }
    return _kApiKeyFallback;
  }
}