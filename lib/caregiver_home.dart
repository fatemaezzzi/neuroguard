import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  COLOUR TOKENS
// ─────────────────────────────────────────────────────────────────────────────
const Color kBg = Color(0xFF0A0A0A);
const Color kLime = Color(0xFFCCFF00);
const Color kPurple = Color(0xFF8B3FDB);
const Color kCream = Color(0xFFF2EDE0);
const Color kWhite = Color(0xFFFFFFFF);

// ─────────────────────────────────────────────────────────────────────────────
//  IMAGE ASSET PATHS  (drop your Figma-exported PNGs here)
// ─────────────────────────────────────────────────────────────────────────────
//  Place these files in:  assets/images/
//  Register in pubspec.yaml under flutter > assets:
//    - assets/images/blob_lime_star.png
//    - assets/images/blob_purple_squircle.png
//    - assets/images/blob_cream_flower.png
//    - assets/images/blob_purple_petal.png
const String kImgLimeStar = 'assets/images/blob_lime_star.png';
const String kImgPurpleSquircle = 'assets/images/blob_purple_squircle.png';
const String kImgCreamFlower = 'assets/images/blob_cream_flower.png';
const String kImgPurplePetal = 'assets/images/blob_purple_petal.png';

// ─────────────────────────────────────────────────────────────────────────────
//  FONT  – Use a bold condensed font like "Space Grotesk" or "Bebas Neue"
//          Add to pubspec.yaml and google_fonts package, or replace with
//          your project's font family.
// ─────────────────────────────────────────────────────────────────────────────

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: kBg),
      home: const CaregiverHomePage(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CAREGIVER HOME PAGE
// ─────────────────────────────────────────────────────────────────────────────
class CaregiverHomePage extends StatelessWidget {
  const CaregiverHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. HERO BLOB ──────────────────────────────────────────────
            _HeroBlob(),

            // ── 2. SPY CALL | LOCATE | SNAP TRIGGER ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _QuickActionRow(),
            ),

            // ── 3. VITALS BANNER ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _VitalsBanner(),
            ),

            // ── 4. REPORTS | ALL ABOUT DEMENTIA ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _BottomBlobRow(),
            ),

            const Spacer(),

            // ── 5. BOTTOM NAV ─────────────────────────────────────────────
            _BottomNavBar(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  1 · HERO BLOB
//      The lime PNG is full-width, text sits centred on top of it.
// ─────────────────────────────────────────────────────────────────────────────
class _HeroBlob extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Lime star PNG — fill the full area
          Positioned.fill(
            child: Image.asset(
              kImgLimeStar,
              fit: BoxFit.contain,
            ),
          ),
          // Greeting text centred over blob
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Hey Sasha,',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kBg,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              Text(
                'Check up on Raj.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kBg,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  2 · QUICK ACTION ROW
//      ┌──────────────┐  ┌────────────────┐  ┌──────────────┐
//      │  SPY CALL    │  │    LOCATE      │  │ SNAP TRIGGER │
//      │  (cream)     │  │  (purple blob) │  │  (cream)     │
//      └──────────────┘  └────────────────┘  └──────────────┘
//
//  Layout rules from screenshot:
//   • SPY CALL & SNAP TRIGGER are equal-width cream tiles, height ≈ 80
//   • LOCATE blob sits in the centre column, slightly taller (≈ 100)
//   • The cream tiles have organic bottom corners (pill-like on one side)
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Fixed height for the whole row — driven by the taller centre blob
    const double rowHeight = 104;
    const double sideHeight = 80;
    const double blobSize = 104; // LOCATE blob is square

    return SizedBox(
      height: rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
      // ── SPY CALL ──────────────────────────────────────────────────
      Expanded(
      child: Align(
      alignment: Alignment.centerLeft,
        child: _CreамTile(
        label: 'SPY\nCALL',
        height: sideHeight,
        // top-left & top-right square; bottom-left rounded pill;
        // bottom-right square (butts against LOCATE)
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(10),
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(10),
        ),
        onTap: () {},
      ),
    ),
    ),

    const SizedBox(width: 8),

    // ── LOCATE (purple blob PNG) ──────────────────────────────────
    GestureDetector(
    onTap: () {},
    child: SizedBox(
    width: blobSize,
    height: blobSize,
    child: Stack(
    alignment: Alignment.center,
    children: [
    Image.asset(
    kImgPurpleSquircle,
    width: blobSize,
    height: blobSize,
    fit: BoxFit.contain,
    ),
    const Text(
    'LOCATE',
    style: TextStyle(
    color: kWhite,
    fontSize: 13,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.8,
    ),
    ),
    ],
    ),
    ),
    ),

    const SizedBox(width: 8),

    // ── SNAP TRIGGER ──────────────────────────────────────────────
    Expanded(
    child: Align(
    alignment: Alignment.centerRight,
    child: _CreамTile(
    label: 'SNAP\nTRIGGER',
    height: sideHeight,
    borderRadius: const BorderRadius.only(
    topLeft: Radius.circular(10),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(10),
    bottomRight: Radius.circular(40),
    ),
    onTap: () {},
    ),
    ),
    ),
    ],
    ),
    );
  }
}

/// Reusable cream action tile
class _CreамTile extends StatelessWidget {
final String label;
final double height;
final BorderRadius borderRadius;
final VoidCallback onTap;

const _CreамTile({
  required this.label,
  required this.height,
  required this.borderRadius,
  required this.onTap,
});

@override
Widget build(BuildContext context) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: kCream,
        borderRadius: borderRadius,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: kBg,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          height: 1.35,
          letterSpacing: 0.3,
        ),
      ),
    ),
  );
}
}

// ─────────────────────────────────────────────────────────────────────────────
//  3 · VITALS BANNER
//      Full-width purple pill, text left-aligned
// ─────────────────────────────────────────────────────────────────────────────
class _VitalsBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 78,
        decoration: BoxDecoration(
          color: kPurple,
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Text(
          'VITALS',
          style: TextStyle(
            color: kWhite,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  4 · BOTTOM BLOB ROW
//      REPORTS (cream flower, left half) | ALL ABOUT DEMENTIA (purple petal, right half)
//      Both blobs are roughly equal size, each filling their half of the row.
// ─────────────────────────────────────────────────────────────────────────────
class _BottomBlobRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const double blobSize = 140;

    return SizedBox(
      height: blobSize,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── REPORTS (cream flower blob) ───────────────────────────────
          GestureDetector(
            onTap: () {},
            child: SizedBox(
              width: blobSize,
              height: blobSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    kImgCreamFlower,
                    width: blobSize,
                    height: blobSize,
                    fit: BoxFit.contain,
                  ),
                  const Text(
                    'REPORTS',
                    style: TextStyle(
                      color: kBg,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── ALL ABOUT DEMENTIA (purple petal blob) ────────────────────
          GestureDetector(
            onTap: () {},
            child: SizedBox(
              width: blobSize,
              height: blobSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    kImgPurplePetal,
                    width: blobSize,
                    height: blobSize,
                    fit: BoxFit.contain,
                  ),
                  const Text(
                    'ALL\nABOUT\nDEMENTIA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kWhite,
                      fontSize: 11,
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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  5 · BOTTOM NAV BAR
//      Home icon (lime filled circle) | Settings icon (lime outlined circle)
// ─────────────────────────────────────────────────────────────────────────────
class _BottomNavBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavButton(
            icon: Icons.home_rounded,
            isActive: true,
            onTap: () {},
          ),
          _NavButton(
            icon: Icons.settings_rounded,
            isActive: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isActive ? kLime : Colors.transparent,
          shape: BoxShape.circle,
          border: isActive
              ? null
              : Border.all(color: kLime, width: 1.8),
        ),
        child: Icon(
          icon,
          color: isActive ? kBg : kLime,
          size: 26,
        ),
      ),
    );
  }
}