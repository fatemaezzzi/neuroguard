import 'package:flutter/material.dart';
import 'package:neuroguard/features/caregiver/spy_call_page.dart';
import 'vitals_page.dart';
import 'reports_page.dart';
import 'all_about_dementia.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'package:neuroguard/features/caregiver/tracker/tracker_page.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';
import 'package:neuroguard/core/services/auth_service.dart';
import 'package:neuroguard/features/caregiver/medicine_reminders_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:neuroguard/main.dart';

// =============================================================================
//  COLOUR TOKENS
// =============================================================================
const Color kBg    = Color(0xFF0A0A0A);
const Color kLime  = Color(0xFFCCFF00);
const Color kWhite = Color(0xFFFFFFFF);

// =============================================================================
//  ASSET PATHS
// =============================================================================
const String kImgHeroBlob    = 'assets/top hero blob.png';
const String kImgLocate      = 'assets/locate-button.png';
const String kImgSpyCall     = 'assets/color_4_.png';
const String kImgSnapTrigger = 'assets/snaptriggerbutton.png';
const String kImgVitals      = 'assets/vitals-button.png';
const String kImgReports     = 'assets/reports-button.png';
const String kImgAllAbout    = 'assets/all-about-dementia-button.png';

// =============================================================================
//  CAREGIVER HOME PAGE
// =============================================================================
class CaregiverHomePage extends StatefulWidget {
  const CaregiverHomePage({super.key});

  @override
  State<CaregiverHomePage> createState() => _CaregiverHomePageState();
}

class _CaregiverHomePageState extends State<CaregiverHomePage> {
  final _authService = AuthService();

  String _caregiverName = '...';
  String _patientName   = '...';
  String _patientId     = '';
  bool   _loading       = true;

  @override
  void initState() {
    super.initState();
    _loadNames();
    _registerFcmToken();
    _listenForegroundNotifications();
  }

  // ── Load caregiver + patient names from Firestore ──────────────────────────
  Future<void> _loadNames() async {
    final data = await _authService.getUserData();
    if (data == null) return;

    final caregiverName = data['name'] as String? ?? 'Caregiver';
    final patientId     = data['paired_patient_id'] as String?;

    String patientName = 'Patient';
    if (patientId != null && patientId.isNotEmpty) {
      final patientData = await _authService.getUserById(patientId);
      patientName = patientData?['name'] as String? ?? 'Patient';
    }

    setState(() {
      _caregiverName = caregiverName;
      _patientName   = patientName;
      _patientId     = patientId ?? '';
      _loading       = false;
    });
  }

  // ── Save FCM token to Firestore ────────────────────────────────────────────
  Future<void> _registerFcmToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await saveFcmToken(uid);
  }

  // ── Show in-app banner when notification arrives while app is open ─────────
  void _listenForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (!mounted) return;
      final title = message.notification?.title ?? 'NeuroGuard Alert';
      final body  = message.notification?.body  ?? '';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kLime,
          duration: const Duration(seconds: 6),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: kBg, fontWeight: FontWeight.bold, fontSize: 14)),
              if (body.isNotEmpty)
                Text(body,
                    style: const TextStyle(color: kBg, fontSize: 12)),
            ],
          ),
        ),
      );
    });
  }

  void _go(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      bottomNavigationBar: CaregiverBottomNav(
        onSettingsTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // 1. HERO BLOB
              HeroBlob(
                caregiverName: _loading ? '...' : _caregiverName,
                patientName:   _loading ? '...' : _patientName,
              ),
              const SizedBox(height: 30),

              // 2. SPY CALL | LOCATE | SNAP TRIGGER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: QuickActionRow(
                  // SPY CALL — audio only
                  onSpyCall: _loading
                      ? () {}
                      : () => _go(
                    context,
                    SpyCallPage(
                      patientId:    _patientId,
                      caregiverId:  FirebaseAuth.instance.currentUser?.uid ?? '',
                      videoEnabled: false,
                    ),
                  ),
                  // LOCATE
                  onLocate: _loading
                      ? () {}
                      : () => _go(
                    context,
                    TrackerPage(
                      patientId:   _patientId,
                      patientName: _patientName,
                    ),
                  ),
                  // SNAP TRIGGER — audio + video
                  onSnapTrigger: _loading
                      ? () {}
                      : () => _go(
                    context,
                    SpyCallPage(
                      patientId:    _patientId,
                      caregiverId:  FirebaseAuth.instance.currentUser?.uid ?? '',
                      videoEnabled: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. MEDICINE REMINDERS BUTTON ← NEW
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MedicineButton(
                  onTap: _loading
                      ? () {}
                      : () => _go(
                    context,
                    MedicineRemindersPage(patientId: _patientId),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 4. VITALS BANNER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VitalsBanner(
                  onTap: _loading
                      ? () {}
                      : () => _go(
                    context,
                    VitalsPage(patientId: _patientId),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 5. REPORTS | ALL ABOUT DEMENTIA
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BottomBlobRow(
                  onReports: () => _loading
                      ? () {}
                      : _go(context, ReportsPage(patientId: _patientId)),
                  onAllAbout: () => _go(context, const AllAboutDementiaPage1()),
                ),
              ),
              const SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  1. HERO BLOB
// =============================================================================
class HeroBlob extends StatelessWidget {
  final String caregiverName;
  final String patientName;

  const HeroBlob({
    super.key,
    required this.caregiverName,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double blobHeight = constraints.maxWidth * 0.90;
        return SizedBox(
          height: blobHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Image.asset(kImgHeroBlob, fit: BoxFit.fill),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Hey $caregiverName,',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kBg,
                      fontFamily: 'MicrosoftSansSerifBold',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  Text(
                    'Check up on $patientName.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kBg,
                      fontFamily: 'MicrosoftSansSerifBold',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
//  2. QUICK ACTION ROW
//  No changes to the widget itself — callbacks are wired from CaregiverHomePage
// =============================================================================
class QuickActionRow extends StatelessWidget {
  final VoidCallback onSpyCall;
  final VoidCallback onLocate;
  final VoidCallback onSnapTrigger;

  const QuickActionRow({
    super.key,
    required this.onSpyCall,
    required this.onLocate,
    required this.onSnapTrigger,
  });

  @override
  Widget build(BuildContext context) {
    const double rowH    = 100;
    const double sideH   = 80;
    const double locateW = 100;
    const double locateH = 100;

    return SizedBox(
      height: rowH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onSpyCall,
              child: SizedBox(
                height: sideH,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                        child: Image.asset(kImgSpyCall, fit: BoxFit.fill)),
                    const Text('SPY\nCALL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: kBg,
                          fontFamily: 'Roboto',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.35,
                        )),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onLocate,
            child: SizedBox(
              width: locateW,
              height: locateH,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(kImgLocate,
                      width: locateW, height: locateH, fit: BoxFit.contain),
                  const Text('LOCATE',
                      style: TextStyle(
                        color: kWhite,
                        fontFamily: 'Roboto',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onSnapTrigger,
              child: SizedBox(
                height: sideH,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                        child: Image.asset(kImgSnapTrigger, fit: BoxFit.fill)),
                    const Text('SNAP\nTRIGGER',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: kBg,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Roboto',
                          height: 1.35,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  3. MEDICINE BUTTON ← NEW
// =============================================================================
class MedicineButton extends StatelessWidget {
  final VoidCallback onTap;
  const MedicineButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLime.withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kLime.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.medication_outlined,
                  color: kLime, size: 26),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MEDICINE REMINDERS',
                      style: TextStyle(
                        color: kWhite,
                        fontFamily: 'MicrosoftSansSerifBold',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      )),
                  SizedBox(height: 3),
                  Text('Set and manage medication schedule',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 22),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
//  4. VITALS BANNER
// =============================================================================
class VitalsBanner extends StatelessWidget {
  final VoidCallback onTap;
  const VitalsBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Image.asset(kImgVitals,
                width: double.infinity, fit: BoxFit.fitWidth),
            const Padding(
              padding: EdgeInsets.only(left: 20),
              child: Text('VITALS',
                  style: TextStyle(
                    color: kWhite,
                    fontSize: 26,
                    fontFamily: 'MicrosoftSansSerifBold',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
//  5. BOTTOM BLOB ROW
// =============================================================================
class BottomBlobRow extends StatelessWidget {
  final VoidCallback onReports;
  final VoidCallback onAllAbout;

  const BottomBlobRow({
    super.key,
    required this.onReports,
    required this.onAllAbout,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double blobSize = constraints.maxWidth * 0.44;
        return SizedBox(
          height: blobSize,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onReports,
                child: SizedBox(
                  width: blobSize,
                  height: blobSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(kImgReports,
                          width: blobSize, height: blobSize,
                          fit: BoxFit.contain),
                      const Text('REPORTS',
                          style: TextStyle(
                            color: kBg,
                            fontSize: 26,
                            fontFamily: 'MicrosoftSansSerifBold',
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          )),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: onAllAbout,
                child: SizedBox(
                  width: blobSize,
                  height: blobSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(kImgAllAbout,
                          width: blobSize, height: blobSize,
                          fit: BoxFit.contain),
                      const Text('ALL\nABOUT\nDEMENTIA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: kWhite,
                            fontSize: 26,
                            fontFamily: 'MicrosoftSansSerifBold',
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                            height: 1.4,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}