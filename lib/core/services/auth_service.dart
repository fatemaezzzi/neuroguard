import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  // ✅ EXISTING
  String? get currentUid => _auth.currentUser?.uid;

  // ✅ ADD THIS (for compatibility with your UI code)
  String? get currentUserId => _auth.currentUser?.uid;

  // ── SIGN UP ─────────────────────────────────────────
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

  // ── SIGN IN ─────────────────────────────────────────
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

  // ── SIGN OUT ────────────────────────────────────────
  Future<void> signOut() => _auth.signOut();

  // ── GET ROLE ───────────────────────────────────────
  Future<String?> getUserRole() async {
    if (currentUid == null) return null;
    final doc = await _db.collection('users').doc(currentUid).get();
    return doc.data()?['role'] as String?;
  }

  // ── GET USER DATA ──────────────────────────────────
  // ── GET USER DATA (cache-first for speed) ─────────────────────────────
  // On first call after login, tries local Firestore cache first.
  // Falls back to server if cache miss. This eliminates the cold-start
  // network round-trip that was causing login delay.
  Future<Map<String, dynamic>?> getUserData() async {
    if (currentUid == null) return null;
    final ref = _db.collection('users').doc(currentUid);

    try {
      // Try cache first — instant on subsequent logins
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (cached.exists) return cached.data();
    } catch (_) {
      // Cache miss on fresh install — fall through to server
    }

    final doc = await ref.get(const GetOptions(source: Source.server));
    return doc.data();
  }

  // ── GET ROLE ───────────────────────────────────────────────────────────

  // ── IS PAIRED ─────────────────────────────────────────────────────────
  // ── IS PAIRED ──────────────────────────────────────
  Future<bool> isPaired() async {
    final data = await getUserData();
    return data?['is_paired'] == true;
  }

  // ── PAIR PATIENT ↔ CAREGIVER ───────────────────────
  Future<void> pairPatientToCaregiver({
    required String patientId,
    required String caregiverId,
  }) async {
    final batch = _db.batch();

    // Update patient doc
    batch.update(_db.collection('users').doc(patientId), {
      'is_paired': true,
      'paired_caregiver_id': caregiverId,
    });

    // Update caregiver doc
    batch.update(_db.collection('users').doc(caregiverId), {
      'is_paired': true,
      'paired_patient_id': patientId,
    });

    await batch.commit();
  }

  // ── GET LINKED PATIENT ID ──────────────────────────
  // ── GET LINKED PATIENT ID ──────────────────────────────────────────────
  Future<String?> getLinkedPatientId() async {
    final data = await getUserData();
    return data?['paired_patient_id'] as String?;
  }

  // ── GET LINKED CAREGIVER ID ────────────────────────────────────────────
  // ── GET LINKED CAREGIVER ID ────────────────────────
  Future<String?> getLinkedCaregiverId() async {
    final data = await getUserData();
    return data?['paired_caregiver_id'] as String?;
  }

  // ── GET ANY USER BY ID ─────────────────────────────
  Future<Map<String, dynamic>?> getUserById(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }
}