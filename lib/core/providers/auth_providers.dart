import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuroguard/core/services/auth_service.dart';

// 1. Raw Firebase auth stream — who is logged in right now?
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// 2. Firestore user data — role, isPaired, paired IDs
// Only runs when a user is actually logged in.
final userDataProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  // Watches authStateProvider — re-fetches if auth changes
  final authState = ref.watch(authStateProvider);

  // If still loading or no user, return null immediately
  return authState.when(
    data: (user) {
      if (user == null) return Future.value(null);
      return AuthService().getUserData();
    },
    loading: () => Future.value(null),
    error: (_, __) => Future.value(null),
  );
});