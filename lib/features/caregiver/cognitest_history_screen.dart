import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class CogniTestHistoryScreen extends StatefulWidget {
  const CogniTestHistoryScreen({super.key});

  @override
  State<CogniTestHistoryScreen> createState() =>
      _CogniTestHistoryScreenState();
}

class _CogniTestHistoryScreenState extends State<CogniTestHistoryScreen> {
  String _selectedView = 'WEEKLY';
  int? _selectedIndex;

  // ── Palette ────────────────────────────────────────────────
  static const Color _bg = Color(0xFF000000);
  static const Color _cardBg = Color(0xFF0D0D1A);
  static const Color _purple = Color(0xFF7C3AED);
  static const Color _purpleLight = Color(0xFFA78BFA);
  static const Color _purpleDim = Color(0xFF2A1A5E);
  static const Color _lime = Color(0xFFB5F20E);
  static const Color _textPrimary = Color(0xFFE2E8F0);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _divider = Color(0xFF111827);
  static const Color _cyan = Color(0xFF00BFFF);

  // ── Data ───────────────────────────────────────────────────
  final List<Map<String, dynamic>> _sessions = [
    {'date': 'MAR 3, 2026', 'time': '2.3s', 'value': 2.3},
    {'date': 'MAR 4, 2026', 'time': '2.3s', 'value': 2.3},
    {'date': 'MAR 5, 2026', 'time': '2.6s', 'value': 2.6},
    {'date': 'MAR 6, 2026', 'time': '3.1s', 'value': 3.1},
    {'date': 'MAR 7, 2026', 'time': '2.8s', 'value': 2.8},
    {'date': 'MAR 8, 2026', 'time': '2.3s', 'value': 2.3},
  ];

  List<FlSpot> get _weeklySpots => List.generate(
    _sessions.length,
        (i) => FlSpot(i.toDouble(), _sessions[i]['value'] as double),
  );

  final List<FlSpot> _monthlySpots = const [
    FlSpot(0, 2.1), FlSpot(1, 2.4), FlSpot(2, 3.2), FlSpot(3, 2.7),
    FlSpot(4, 3.5), FlSpot(5, 2.3), FlSpot(6, 2.8), FlSpot(7, 3.1),
    FlSpot(8, 2.6), FlSpot(9, 2.9), FlSpot(10, 3.3), FlSpot(11, 2.4),
  ];

  List<FlSpot> get _activeSpots =>
      _selectedView == 'WEEKLY' ? _weeklySpots : _monthlySpots;

  // ── Helpers ────────────────────────────────────────────────
  Color _timeColor(double v) {
    if (v > 3.0) return const Color(0xFFF87171);
    if (v > 2.5) return const Color(0xFFFBBF24);
    return _purpleLight;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildTitle(),
                    const SizedBox(height: 20),
                    _buildToggleButtons(),
                    const SizedBox(height: 20),
                    _buildChart(),
                    const SizedBox(height: 24),
                    _buildSessionList(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  // ── Title ──────────────────────────────────────────────────
  Widget _buildTitle() {
    return const Text(
      'COGNITEST - HISTORY',
      style: TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontFamily: 'MicrosoftSanSerifBold',
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      ),
    );
  }

  // ── Toggle ─────────────────────────────────────────────────
  Widget _buildToggleButtons() {
    return Row(
      children: ['WEEKLY', 'MONTHLY'].map((label) {
        final isActive = _selectedView == label;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: label == 'WEEKLY' ? 8 : 0),
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedView = label;
                _selectedIndex = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 25),
                decoration: BoxDecoration(
                  color: isActive ? _purple : _purpleDim,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: isActive
                      ? [
                    BoxShadow(
                      color: _purple.withOpacity(0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    )
                  ]
                      : null,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Roboto',
                    fontSize: 20,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Chart ──────────────────────────────────────────────────
  Widget _buildChart() {
    return Container(
      height: 140,
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 10),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1B4B)),
      ),
      child: LineChart(
        LineChartData(
          minY: 1.2,
          maxY: 4.8,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 0.6,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Color(0xFF1E1B4B),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: 0.5,
                getTitlesWidget: (value, _) {
                  if (value % 0.5 != 0) return const SizedBox.shrink();
                  return Text(
                    '${value.toStringAsFixed(1)}s',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 9,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, _) {
                  final spots = _activeSpots;
                  if (value.toInt() >= spots.length) {
                    return const SizedBox.shrink();
                  }
                  final label = _selectedView == 'WEEKLY'
                      ? 'D${value.toInt() + 1}'
                      : 'W${value.toInt() + 1}';
                  return Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 9,
                    ),
                  );
                },
              ),
            ),
            topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: 3.0,
                color: const Color(0xFFEF4444).withOpacity(0.25),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: _activeSpots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: _purpleLight,
              barWidth: 2,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 3,
                  color: _purple,
                  strokeWidth: 1.5,
                  strokeColor: _purpleLight,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _purple.withOpacity(0.18),
                    _purple.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1A1A2E),
              tooltipBorder:
              const BorderSide(color: _purple, width: 1),
              tooltipBorderRadius: BorderRadius.circular(8),
              getTooltipItems: (touchedSpots) => touchedSpots
                  .map((s) => LineTooltipItem(
                '${s.y.toStringAsFixed(1)}s',
                const TextStyle(
                  color: _purpleLight,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Session List ───────────────────────────────────────────
  Widget _buildSessionList() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Text(
                'DATE',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.only(right: 32),
                child: Text(
                  'TIME',
                  style: TextStyle(
                    color: _textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF1E1B4B), height: 1),

        // Rows
        ...List.generate(_sessions.length, (i) {
          final session = _sessions[i];
          final isSelected = _selectedIndex == i;
          final value = session['value'] as double;

          return Column(
            children: [
              InkWell(
                onTap: () =>
                    setState(() => _selectedIndex = isSelected ? null : i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.fromLTRB(
                    isSelected ? 8 : 0,
                    14,
                    0,
                    isSelected ? 10 : 14,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _purple.withOpacity(0.06)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(isSelected ? 8 : 0),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session['date'] as String,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Avg hover time: ${value.toStringAsFixed(1)}s',
                                style: const TextStyle(
                                  color: _purple,
                                  fontSize: 18,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        session['time'] as String,
                        style: TextStyle(
                          color: _timeColor(value),
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 14),
                      _PlayButton(),
                    ],
                  ),
                ),
              ),
              const Divider(color: _divider, height: 1),
            ],
          );
        }),
      ],
    );
  }

  // ── Bottom Nav ─────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF050508),
        border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavButton(
            child: const Icon(Icons.home_rounded, color: _lime, size: 26),
            onTap: () {},
          ),
          _NavButton(
            child: const Icon(Icons.settings_rounded, color: _lime, size: 26),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ── Small Widgets ──────────────────────────────────────────────
class _PlayButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFA78BFA), width: 1.5),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Color(0xFFA78BFA),
        size: 16,
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _NavButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1A2A00),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: child),
      ),
    );
  }
}