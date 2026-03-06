import 'package:flutter/material.dart';

// =============================================================================
//  COLOUR TOKENS
// =============================================================================
const Color kBg    = Color(0xFF0A0A0A);
const Color kLime  = Color(0xFFCCFF00);
const Color kWhite = Color(0xFFFFFFFF);

// =============================================================================
//  ASSET PATHS  --  exact filenames from assets/ folder
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
//  APP ENTRY
// =============================================================================
void main() => runApp(const NeuroGuardApp());

class NeuroGuardApp extends StatelessWidget {
  const NeuroGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: kBg),
      home: const CaregiverHomePage(),
    );
  }
}

// =============================================================================
//  CAREGIVER HOME PAGE
//  Wrapped in SingleChildScrollView so it never overflows on small screens.
// =============================================================================
class CaregiverHomePage extends StatelessWidget {
  const CaregiverHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      // Bottom nav stays fixed; only the content above scrolls
      bottomNavigationBar: const BottomNavBar(),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [

              // 1. HERO BLOB  (no horizontal padding -- bleeds full width)
              HeroBlob(),

              SizedBox(height: 30),

              // 2. SPY CALL | LOCATE | SNAP TRIGGER
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: QuickActionRow(),
              ),

              SizedBox(height: 20),

              // 3. VITALS BANNER
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: VitalsBanner(),
              ),

              SizedBox(height: 20),

              // 4. REPORTS | ALL ABOUT DEMENTIA
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: BottomBlobRow(),
              ),

              SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  1. HERO BLOB
//  The lime blob PNG bleeds full width. Text sits dead-centre over it.
//  Height is kept proportional: roughly 42% of a 680px screen = ~200px.
// =============================================================================
class HeroBlob extends StatelessWidget {
  const HeroBlob({super.key});

  @override
  Widget build(BuildContext context) {
    // Use LayoutBuilder so the blob scales correctly on every screen width
    return LayoutBuilder(
      builder: (context, constraints) {
        // Blob height = 62% of its width (matches the original aspect ratio)
        final double blobHeight = constraints.maxWidth * 0.90;

        return SizedBox(
          height: blobHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Blob PNG -- fill full width, no padding
              Positioned.fill(
                child: Image.asset(
                  kImgHeroBlob,
                  fit: BoxFit.fill,
                  alignment: Alignment.center,
                ),
              ),
              // Greeting text
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Hey Sasha,',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kBg,
                      fontFamily: 'MicrosoftSansSerifBold',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  Text(
                    'Check up on Raj.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
//
//  Layout (from screenshot):
//    [  SPY CALL  ] [   LOCATE   ] [ SNAP TRIGGER ]
//
//  - SPY CALL  : Expanded, height 82px, uses color_4_.png  (cream shape)
//  - LOCATE    : Fixed 100x100, uses locate-button.png, label on top
//  - SNAP TRIG : Expanded, height 82px, uses snaptriggerbutton.png
//
//  The LOCATE blob is vertically centred and slightly taller than the side tiles.
// =============================================================================
class QuickActionRow extends StatelessWidget {
  const QuickActionRow({super.key});

  @override
  Widget build(BuildContext context) {
    const double rowH    = 100; // total row height driven by locate blob
    const double sideH   = 80;  // side tiles are slightly shorter
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
              onTap: () {},
              child: SizedBox(
                height: sideH,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // PNG provides the cream blob shape
                    Positioned.fill(
                      child: Image.asset(
                        kImgSpyCall,
                        fit: BoxFit.fill,
                      ),
                    ),
                    const Text(
                      'SPY\nCALL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kBg,
                        fontFamily: 'Roboto',
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.35,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // LOCATE
          GestureDetector(
            onTap: () {},
            child: SizedBox(
              width: locateW,
              height: locateH,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    kImgLocate,
                    width: locateW,
                    height: locateH,
                    fit: BoxFit.contain,
                  ),
                  const Text(
                    'LOCATE',
                    style: TextStyle(
                      color: kWhite,
                      fontFamily: 'Roboto',
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // SNAP TRIGGER
          Expanded(
            child: GestureDetector(
              onTap: () {},
              child: SizedBox(
                height: sideH,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        kImgSnapTrigger,
                        fit: BoxFit.fill,
                      ),
                    ),
                    const Text(
                      'SNAP\nTRIGGER',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kBg,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Roboto',
                        height: 1.35,
                        letterSpacing: 0.3,
                      ),
                    ),
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
//  Full-width image, "VITALS" label left-aligned.
//  Height ~80px matches the original.
// =============================================================================
class VitalsBanner extends StatelessWidget {
  const VitalsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 80,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF6B3FD4), // purple matching the original
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Text(
          'VITALS',
          style: TextStyle(
            color: kWhite,
            fontSize: 26,
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  4. BOTTOM BLOB ROW
//  Two blobs side by side, each ~140px, spaced evenly.
//  REPORTS label is dark (blob is cream).
//  ALL ABOUT DEMENTIA label is white (blob is purple).
// =============================================================================
class BottomBlobRow extends StatelessWidget {
  const BottomBlobRow({super.key});

  @override
  Widget build(BuildContext context) {
    // Each blob takes ~45% of available width so they sit naturally spaced
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
                onTap: () {},
                child: SizedBox(
                  width: blobSize,
                  height: blobSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        kImgReports,
                        width: blobSize,
                        height: blobSize,
                        fit: BoxFit.contain,
                      ),
                      const Text(
                        'REPORTS',
                        style: TextStyle(
                          color: kBg,
                          fontSize: 26,
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ALL ABOUT DEMENTIA
              GestureDetector(
                onTap: () {},
                child: SizedBox(
                  width: blobSize,
                  height: blobSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        kImgAllAbout,
                        width: blobSize,
                        height: blobSize,
                        fit: BoxFit.contain,
                      ),
                      const Text(
                        'ALL\nABOUT\nDEMENTIA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: kWhite,
                          fontSize: 26,
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          height: 1.4,
                        ),
                      ),
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
//  5. BOTTOM NAV BAR  (fixed via Scaffold.bottomNavigationBar)
//  Home  = lime filled circle  |  Settings = lime outlined circle
// =============================================================================
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: kBg,
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            NavImageButton(
              imgPath: kImgNavHome,
              isActive: true,
              onTap: () {},
            ),
            NavImageButton(
              imgPath: kImgNavSettings,
              isActive: false,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class NavImageButton extends StatelessWidget {
  final String imgPath;
  final bool isActive;
  final VoidCallback onTap;

  const NavImageButton({
    super.key,
    required this.imgPath,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: isActive ? kLime : Colors.transparent,
          shape: BoxShape.circle,
          border: isActive
              ? null
              : Border.all(color: kLime, width: 1.8),
        ),
        padding: const EdgeInsets.all(13),
        child: Image.asset(
          imgPath,
          fit: BoxFit.contain,
          color: isActive ? kBg : kLime,
          colorBlendMode: BlendMode.srcIn,
        ),
      ),
    );
  }
}