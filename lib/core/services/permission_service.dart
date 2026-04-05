import 'package:permission_handler/permission_handler.dart';

enum LocationPermissionLevel { always, foregroundOnly, denied }

class PermissionService {

  /// Call this once on app startup (e.g., in main.dart or splash screen).
  /// Each permission is only requested if it has not been granted yet.
  static Future<void> requestAllPermissions() async {
    await _requestMicrophonePermission();
    await _requestCameraPermission();
    await _requestLocationPermission();
  }

  // ✅ NEW: typed check for use before starting FGS
  static Future<LocationPermissionLevel> getLocationPermissionLevel() async {
    if (await Permission.locationAlways.isGranted) {
      return LocationPermissionLevel.always;
    }
    if (await Permission.location.isGranted) {
      return LocationPermissionLevel.foregroundOnly;
    }
    return LocationPermissionLevel.denied;
  }

  static Future<bool> isBackgroundLocationGranted() async =>
      await Permission.locationAlways.isGranted;

  // --- MICROPHONE ---
  static Future<bool> _requestMicrophonePermission() async {
    // ✅ Check first — skip entirely if already granted
    if (await Permission.microphone.isGranted) {
      print('Microphone: already GRANTED, skipping request');
      return true;
    }

    final status = await Permission.microphone.request();

    if (status.isGranted) {
      print('Microphone: GRANTED');
      return true;
    } else if (status.isPermanentlyDenied) {
      // ✅ Do NOT auto-open settings — let the user trigger this from the UI
      print('Microphone: PERMANENTLY DENIED (user must enable in Settings manually)');
    }
    return false;
  }

  // --- CAMERA ---
  static Future<bool> _requestCameraPermission() async {
    // ✅ Check first — skip entirely if already granted
    if (await Permission.camera.isGranted) {
      print('Camera: already GRANTED, skipping request');
      return true;
    }

    final status = await Permission.camera.request();

    if (status.isGranted) {
      print('Camera: GRANTED');
      return true;
    } else if (status.isPermanentlyDenied) {
      // Do NOT auto-open settings — let the user trigger this from the UI
      print('Camera: PERMANENTLY DENIED (user must enable in Settings manually)');
    }
    return false;
  }

  // --- LOCATION ---
  // Note: Background location must be requested AFTER foreground is granted
  static Future<bool> _requestLocationPermission() async {
    // Check foreground first — skip if already granted
    if (await Permission.location.isGranted) {
      print('Location (foreground): already GRANTED, skipping request');

      // Still check background separately
      if (!await Permission.locationAlways.isGranted) {
        final background = await Permission.locationAlways.request();
        if (background.isGranted) {
          print('Location (background): GRANTED');
        } else if (background.isPermanentlyDenied) {
          // Do NOT auto-open settings
          print('Location (background): PERMANENTLY DENIED');
        }
      } else {
        print('Location (background): already GRANTED, skipping request');
      }
      return true;
    }

    // Step 1: Request foreground location
    final foreground = await Permission.location.request();

    if (!foreground.isGranted) {
      print('Location (foreground): DENIED');
      return false;
    }

    print('Location (foreground): GRANTED');

    // Step 2: Request background only after foreground is confirmed (Android 10+)
    if (!await Permission.locationAlways.isGranted) {
      final background = await Permission.locationAlways.request();
      if (background.isGranted) {
        print('Location (background): GRANTED');
        return true;
      } else if (background.isPermanentlyDenied) {
        // Do NOT auto-open settings
        print('Location (background): PERMANENTLY DENIED');
      }
    } else {
      print('Location (background): already GRANTED, skipping request');
      return true;
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

  // --- OPEN SETTINGS (call this only from a UI button/dialog, never automatically) ---
  /// Show this only when a feature fails due to a permanently denied permission.
  /// Example: display a dialog with "Go to Settings" button that calls this.
  static Future<void> openSettings() async {
    await openAppSettings();
  }
}