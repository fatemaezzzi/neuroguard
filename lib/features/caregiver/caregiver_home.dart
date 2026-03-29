import 'package:flutter/material.dart';
import 'vitals_page.dart';
import 'reports_page.dart';
import 'all_about_dementia.dart'; // contains AllAboutDementiaPage1
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';
import 'package:neuroguard/features/caregiver/tracker/tracker_page.dart';
import 'package:neuroguard/features/shared/settings_screen.dart';
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
const String kImgNavHome     = 'assets/Vectorhome.png';
const String kImgNavSettings = 'assets/Vectorsettings.png';

// =============================================================================
//  CAREGIVER HOME PAGE
// =============================================================================
class CaregiverHomePage extends StatelessWidget {
  const CaregiverHomePage({super.key});

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
              const HeroBlob(),
              const SizedBox(height: 30),

              // 2. SPY CALL | LOCATE | SNAP TRIGGER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: QuickActionRow(
                  onSpyCall:     () {},  // TODO: wire when SpyCall page is ready
                  onLocate:      () => _go(
                    context,
                    const TrackerPage(
                      patientId:   'patient_01',   // replace with real patient ID from auth
                      patientName: 'Raj',          // replace with real patient name
                    ),
                  ),
                  onSnapTrigger: () {},  // TODO: wire when SnapTrigger page is ready
                ),
              ),
              const SizedBox(height: 20),

              // 3. VITALS BANNER  →  VitalsPage
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VitalsBanner(
                  onTap: () => _go(context, const VitalsPage()),
                ),
              ),
              const SizedBox(height: 20),

              // 4. REPORTS | ALL ABOUT DEMENTIA
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BottomBlobRow(
                  onReports:  () => _go(context, const ReportsPage()),
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
  const HeroBlob({super.key});

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
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Hey Sasha,',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kBg,
                        fontFamily: 'MicrosoftSansSerifBold',
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      )),
                  Text('Check up on Raj.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kBg,
                        fontFamily: 'MicrosoftSansSerifBold',
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      )),
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

          // SPY CALL
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

          // LOCATE
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

          // SNAP TRIGGER
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
//  3. VITALS BANNER
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
//  4. BOTTOM BLOB ROW
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

              // REPORTS
              GestureDetector(
                onTap: onReports,
                child: SizedBox(
                  width: blobSize,
                  height: blobSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(kImgReports,
                          width: blobSize,
                          height: blobSize,
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

              // ALL ABOUT DEMENTIA
              GestureDetector(
                onTap: onAllAbout,
                child: SizedBox(
                  width: blobSize,
                  height: blobSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(kImgAllAbout,
                          width: blobSize,
                          height: blobSize,
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

// =============================================================================
//  5. BOTTOM NAV BAR
// =============================================================================