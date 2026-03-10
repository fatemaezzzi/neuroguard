import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:neuroguard/features/shared/widgets/navigation_widget.dart';

class VitalsPage extends StatelessWidget {
  const VitalsPage({super.key});

  static const TextStyle _hugeBlack = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 22,
    letterSpacing: 1.5,
    color: Colors.black,
  );

  static const TextStyle _hugeGreen = TextStyle(
    fontFamily: 'MicrosoftSansSerifBold',
    fontWeight: FontWeight.w900,
    fontSize: 22,
    letterSpacing: 1.5,
    color: Color(0xFFCCFF00),
  );

  static const TextStyle _smallBody = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Colors.black54,
  );

  static const TextStyle _smallBold = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  );

  static const double _overlapVeloStatus   = 28.0;
  static const double _overlapStatusPocket = -23.0;
  static const double _overlapPocketVibra  = 23.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: CaregiverBottomNav(
        onSettingsTap: () {},
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              _buildBlobChain(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlobChain() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;

        final double h1 = w * (190 / 364);
        final double h2 = w * (159 / 364);
        final double h3 = w * (81  / 364);
        final double h4 = w * (151 / 350);

        final double topVelo   = 0;
        final double topStatus = h1 - _overlapVeloStatus;
        final double topPocket = topStatus + h2 - _overlapStatusPocket;
        final double topVibra  = topPocket + h3 - _overlapPocketVibra;
        final double totalHeight = topVibra + h4;

        return SizedBox(
          width: w,
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [

              // ── LAYER 1 (BACK): statussleeping ───────────────────────
              Positioned(
                top: topStatus,
                left: 0,
                right: 0,
                height: h2,
                child: Stack(
                  children: [
                    Image.asset('assets/statussleeping.png',
                        width: w, height: h2, fit: BoxFit.fill),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('STATUS', style: _hugeGreen),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: const [
                                Text('SLEEPING', style: _hugeBlack),
                                SizedBox(height: 2),
                                Text('low movement, on bed', style: _smallBody),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── LAYER 2: pocketcheck ──────────────────────────────────
              Positioned(
                top: topPocket,
                left: 0,
                right: 0,
                height: h3,
                child: Stack(
                  children: [
                    Image.asset('assets/pocketcheck.png',
                        width: w, height: h3, fit: BoxFit.fill),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('POCKET CHECK', style: _hugeBlack),
                            Image.asset('assets/arrow.png',
                                width: 30,
                                height: 30,
                                color: const Color(0xFFCCFF00)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── LAYER 3: lastvibrationtest ────────────────────────────
              Positioned(
                top: topVibra,
                left: 0,
                right: 0,
                height: h4,
                child: Stack(
                  children: [
                    Image.asset('assets/lastvibrationtest.png',
                        width: w, height: h4, fit: BoxFit.fill),
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text('LAST VIBRATION TEST', style: _hugeBlack),
                          SizedBox(height: 4),
                          Text('10:30', style: _smallBold),
                          SizedBox(height: 2),
                          Text('ON/OFF PERSON', style: _hugeBlack),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── LAYER 4 (FRONT): velostatgraph ───────────────────────
              Positioned(
                top: topVelo,
                left: 0,
                right: 0,
                height: h1,
                child: Stack(
                  children: [
                    Image.asset('assets/velostatgraph.png',
                        width: w, height: h1, fit: BoxFit.fill),
                    const Positioned(
                      top: 18,
                      left: 24,
                      child: Text('VELOSTAT GRAPH', style: _hugeBlack),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: h1 * 0.38,
                      bottom: 16,
                      child: _buildChart(),
                    ),
                  ],
                ),
              ),

            ],
          ),
        );
      },
    );
  }

  Widget _buildChart() {
    final spots = [
      const FlSpot(0, 1.2),
      const FlSpot(1, 1.8),
      const FlSpot(2, 1.5),
      const FlSpot(3, 2.1),
      const FlSpot(4, 1.9),
      const FlSpot(5, 1.6),
      const FlSpot(6, 2.3),
      const FlSpot(7, 2.0),
      const FlSpot(8, 1.7),
      const FlSpot(9, 2.2),
    ];

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: 9,
        minY: 0,
        maxY: 3,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.black.withOpacity(0.7),
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.black.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }
}