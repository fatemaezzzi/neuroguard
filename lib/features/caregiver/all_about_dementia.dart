import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AllAboutDementiaPage1(),
  ));
}

// ══════════════════════════════════════════════════════
//  PAGE 1
// ══════════════════════════════════════════════════════
class AllAboutDementiaPage1 extends StatelessWidget {
  const AllAboutDementiaPage1({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── full-screen scrollable background image
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Image.asset(
              'assets/all-about-dementia-pg1.png',
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
          ),

          // ── arrow pinned bottom-right
          Positioned(
            bottom: 28,
            right: 28,
            child: _NavArrow(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AllAboutDementiaPage2(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
//  PAGE 2
// ══════════════════════════════════════════════════════
class AllAboutDementiaPage2 extends StatelessWidget {
  const AllAboutDementiaPage2({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── full-screen scrollable background image
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Image.asset(
              'assets/all-about-dementia-pg2.png',
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
          ),

          // ── back arrow pinned bottom-right
          Positioned(
            bottom: 28,
            right: 28,
            child: _NavArrow(
              onTap: () => Navigator.pop(context),
              isBack: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
//  NAV ARROW WIDGET
// ══════════════════════════════════════════════════════
class _NavArrow extends StatelessWidget {
  final VoidCallback onTap;
  final bool isBack;

  const _NavArrow({required this.onTap, this.isBack = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          color: Color(0xFFBBF024), // lime green matching design
          shape: BoxShape.circle,
        ),
        child: Icon(
          isBack ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
          color: Colors.black,
          size: 26,
        ),
      ),
    );
  }
}