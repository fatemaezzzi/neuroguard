import 'package:permission_handler/permission_handler.dart';

class PermissionService {

  /// Call this once on app startup (e.g., in main.dart or splash screen)
  static Future<void> requestAllPermissions() async {
    await _requestMicrophonePermission();
    await _requestCameraPermission();
    await _requestLocationPermission();
  }

  // --- MICROPHONE ---
  static Future<bool> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();

    if (status.isGranted) {
      print('Microphone: GRANTED');
      return true;
    } else if (status.isPermanentlyDenied) {
      // User clicked "Never ask again" — send them to Settings
      openAppSettings();
    }
    return false;
  }

  // --- CAMERA ---
  static Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      print('Camera: GRANTED');
      return true;
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
    return false;
  }

  // --- LOCATION ---
  // Note: Background location must be requested AFTER foreground is granted
  static Future<bool> _requestLocationPermission() async {
    // Step 1: Request foreground location first
    final foreground = await Permission.location.request();

    if (!foreground.isGranted) {
      print('Location (foreground): DENIED');
      return false;
    }

    print('Location (foreground): GRANTED');

    // Step 2: Now request background location (Android 10+)
    final background = await Permission.locationAlways.request();

    if (background.isGranted) {
      print('Location (background): GRANTED');
      return true;
    } else if (background.isPermanentlyDenied) {
      openAppSettings();
    }

    return false;
  }

  // --- CHECK STATUS (use anywhere in app before using a feature) ---
  static Future<bool> isMicrophoneGranted() async =>
      await Permission.microphone.isGranted;

  static Future<bool> isCameraGranted() async =>
      await Permission.camera.isGranted;

  static Future<bool> isLocationGranted() async =>
      await Permission.location.isGranted;
}