import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. Auth stream — never disposed (app-lifetime listener is correct here)
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// 2. Firestore user data stream — autoDispose is CRITICAL here.
//    Without it, switching accounts keeps the old user's stream alive,
//    causing the new login to buffer while two streams fight each other.
//
//    With autoDispose:
//    - Stream is killed the moment no widget watches it (i.e. on logout)
//    - When a new user logs in, a fresh stream opens against the correct UID doc
//    - First emission is from Firestore offline cache → instant, no buffering
final userDataProvider = StreamProvider.autoDispose<Map<String, dynamic>?>((
  ref,
) {
  final authState = ref.watch(authStateProvider);

  // keepAlive for 2 seconds during screen transitions so we don't
  // re-fetch when AuthGate briefly unmounts during navigation
  final link = ref.keepAlive();
  Future.delayed(const Duration(seconds: 2), () {
    link.close();
  });

  return authState.when(
    data: (user) {
      if (user == null) {
        // Explicitly return null stream — no Firestore listener open while logged out
        return Stream.value(null);
      }

      // Open a fresh listener scoped to THIS user's UID only.
      // autoDispose guarantees this is torn down on logout before the
      // next user's stream is created — no overlap, no buffering.
      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .map((snap) => snap.data());
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

// 3. Convenience: role string
final userRoleProvider = Provider.autoDispose<String?>((ref) {
  return ref.watch(userDataProvider).value?['role'] as String?;
});

// 4. Convenience: paired status
final isPairedProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(userDataProvider).value?['is_paired'] == true;
});
