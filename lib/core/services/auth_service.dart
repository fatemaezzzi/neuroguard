import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;

  // ── SIGN UP ────────────────────────────────────────────────────────────
  Future<String?> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = cred.user!.uid;

    await _db.collection('users').doc(uid).set({
      'uid': uid,
      'name': name,
      'email': email,
      'role': role,
      'created_at': FieldValue.serverTimestamp(),
      'is_paired': false,
      'paired_caregiver_id': null,
      'paired_patient_id': null,
    });

    return uid;
  }

  // ── SIGN IN ────────────────────────────────────────────────────────────
  Future<User?> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return cred.user;
  }

  // ── SIGN OUT ───────────────────────────────────────────────────────────
  Future<void> signOut() => _auth.signOut();

  // ── GET USER DATA (cache-first, server fallback) ──────────────────────
  // Uses cache for speed. Falls back to server on cache miss or when
  // paired but patient name not yet cached (one-time post-pairing refresh).
  Future<Map<String, dynamic>?> getUserData() async {
    if (currentUid == null) return null;
    final ref = _db.collection('users').doc(currentUid);

    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (cached.exists) {
        final data = cached.data()!;
        // One-time server fetch if paired but patient name not yet cached
        if (data['is_paired'] == true && data['paired_patient_name'] == null) {
          final fresh = await ref.get(const GetOptions(source: Source.server));
          return fresh.data();
        }
        return data;
      }
    } catch (_) {
      // Cache miss on fresh install — fall through to server
    }

    final doc = await ref.get(const GetOptions(source: Source.server));
    return doc.data();
  }

  // ── GET ROLE ───────────────────────────────────────────────────────────
  Future<String?> getUserRole() async {
    final data = await getUserData();
    return data?['role'] as String?;
  }

  // ── IS PAIRED ─────────────────────────────────────────────────────────
  Future<bool> isPaired() async {
    final data = await getUserData();
    return data?['is_paired'] == true;
  }

  // ── PAIR PATIENT TO CAREGIVER ──────────────────────────────────────────
  Future<void> pairPatientToCaregiver({
    required String patientId,
    required String caregiverId,
    String patientName = 'Patient',
  }) async {
    final batch = _db.batch();

    batch.set(
      _db.collection('users').doc(patientId),
      {'is_paired': true, 'paired_caregiver_id': caregiverId},
      SetOptions(merge: true),
    );

    batch.set(
      _db.collection('users').doc(caregiverId),
      {
        'is_paired': true,
        'paired_patient_id': patientId,
        'paired_patient_name': patientName,  // cached to avoid second read on dashboard load
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  // ── GET LINKED PATIENT ID ──────────────────────────────────────────────
  Future<String?> getLinkedPatientId() async {
    final data = await getUserData();
    return data?['paired_patient_id'] as String?;
  }

  // ── GET LINKED CAREGIVER ID ────────────────────────────────────────────
  Future<String?> getLinkedCaregiverId() async {
    final data = await getUserData();
    return data?['paired_caregiver_id'] as String?;
  }

  // ── GET ANY USER BY ID ─────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getUserById(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }
}