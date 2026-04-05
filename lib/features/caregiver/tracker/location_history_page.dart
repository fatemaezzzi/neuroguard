// lib/features/caregiver/tracker/location_history_page.dart
//
// LocationHistoryPage — Patient Location Trail (Caregiver Side)
// Rethemed to match NeuroGuard's black + lime-green + purple design language.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:neuroguard/core/services/location_history_service.dart';

final _dateFmt = DateFormat('d MMM y');
final _timeFmt = DateFormat('h:mm a');
final _fullFmt = DateFormat('d MMM, h:mm a');

class LocationHistoryPage extends StatefulWidget {
  final String patientId;
  final String patientName;

  const LocationHistoryPage({
    Key? key,
    required this.patientId,
    required this.patientName,
  }) : super(key: key);

  @override
  State<LocationHistoryPage> createState() => _LocationHistoryPageState();
}

class _LocationHistoryPageState extends State<LocationHistoryPage>
    with SingleTickerProviderStateMixin {

  // ── Theme — matches NeuroGuard black+lime+purple palette ──────────────────
  static const Color _bg         = Color(0xFF0A0A0A);   // true black bg
  static const Color _card       = Color(0xFF161616);   // slightly lifted card
  static const Color _cardBorder = Color(0xFF242424);   // subtle border
  static const Color _lime       = Color(0xFFB5E800);   // primary lime accent
  static const Color _purple     = Color(0xFF7B2FBE);   // secondary purple
  static const Color _white      = Color(0xFFFFFFFF);
  static const Color _grey       = Color(0xFF888888);
  static const Color _trailColor = Color(0xFFB5E800);   // lime trail on map

  // ── State ─────────────────────────────────────────────────────────────────
  List<LocationHistoryEntry> _entries = [];
  bool _isLoading = true;
  bool _isOffline = false;

  _DateRange _selectedRange = _DateRange.today;
  LocationHistoryEntry? _highlighted;

  final MapController _mapController = MapController();
  bool _mapReady = false;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _isLoading = true);

    final (from, to) = _selectedRange.range;
    final svc = LocationHistoryService();

    List<LocationHistoryEntry> entries = await svc.getRemoteHistory(
      patientId: widget.patientId,
      limit: 500,
      from: from,
      to: to,
    );

    if (entries.isEmpty) {
      entries = await svc.getLocalHistory(
        patientId: widget.patientId,
        limit: 500,
        from: from,
        to: to,
      );
      if (mounted) setState(() => _isOffline = entries.isNotEmpty);
    } else {
      if (mounted) setState(() => _isOffline = false);
    }

    if (!mounted) return;

    entries.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    setState(() {
      _entries = entries;
      _isLoading = false;
      _highlighted = entries.isNotEmpty ? entries.last : null;
    });

    if (_mapReady && entries.length > 1) _fitTrail();
  }

  // ── Map helpers ───────────────────────────────────────────────────────────

  LatLng _toLatLng(LocationHistoryEntry e) => LatLng(e.latitude, e.longitude);

  void _fitTrail() {
    if (_entries.isEmpty || !_mapReady) return;
    final lats = _entries.map((e) => e.latitude);
    final lngs = _entries.map((e) => e.longitude);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(lats.reduce((a, b) => a < b ? a : b),
              lngs.reduce((a, b) => a < b ? a : b)),
          LatLng(lats.reduce((a, b) => a > b ? a : b),
              lngs.reduce((a, b) => a > b ? a : b)),
        ),
        padding: const EdgeInsets.fromLTRB(40, 80, 40, 200),
      ),
    );
  }

  void _jumpTo(LocationHistoryEntry entry) {
    setState(() => _highlighted = entry);
    if (_mapReady) _mapController.move(_toLatLng(entry), 17.0);
    _tabController.animateTo(0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildTopBar(),
          _buildFilterRow(),
          if (_isOffline) _buildOfflineBanner(),
          _buildTabBar(),
          Expanded(
            child: _isLoading
                ? _buildLoader()
                : _entries.isEmpty
                ? _buildEmpty()
                : TabBarView(
              controller: _tabController,
              children: [_buildMapTab(), _buildTimelineTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _cardBorder)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: _white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LOCATION HISTORY',
                      style: TextStyle(
                        color: _lime,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      widget.patientName,
                      style: const TextStyle(
                        color: _white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              // Lime refresh button — matches app's primary button style
              GestureDetector(
                onTap: _load,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _lime,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: Colors.black, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter chips ──────────────────────────────────────────────────────────

  Widget _buildFilterRow() {
    return Container(
      color: _card,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _DateRange.values.map((range) {
            final selected = _selectedRange == range;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedRange = range);
                  _load();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? _lime : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: selected ? _lime : _cardBorder),
                  ),
                  child: Text(
                    range.label,
                    style: TextStyle(
                      color: selected ? Colors.black : _grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Offline banner ────────────────────────────────────────────────────────

  Widget _buildOfflineBanner() {
    return Container(
      color: const Color(0xFF2A1800),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: const [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFFFB84D), size: 15),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — showing locally cached data',
              style: TextStyle(
                color: Color(0xFFFFB84D),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: _card,
      child: TabBar(
        controller: _tabController,
        indicatorColor: _lime,
        indicatorWeight: 3,
        labelColor: _lime,
        unselectedLabelColor: _grey,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.map_rounded, size: 17), text: 'MAP'),
          Tab(
              icon: Icon(Icons.timeline_rounded, size: 17),
              text: 'TIMELINE'),
        ],
      ),
    );
  }

  // ── Map tab ───────────────────────────────────────────────────────────────

  Widget _buildMapTab() {
    final center = _highlighted != null
        ? _toLatLng(_highlighted!)
        : _entries.isNotEmpty
        ? _toLatLng(_entries.last)
        : const LatLng(19.0760, 72.8777);

    final trailPoints = _entries.map(_toLatLng).toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15.0,
            minZoom: 8.0,
            maxZoom: 20.0,
            onMapReady: () {
              setState(() => _mapReady = true);
              if (_entries.length > 1) _fitTrail();
            },
          ),
          children: [
            TileLayer(
              urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.yourteam.neuroguard',
              maxNativeZoom: 19,
            ),
            if (trailPoints.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                  points: trailPoints,
                  color: _trailColor.withOpacity(0.8),
                  strokeWidth: 4.0,
                  borderColor: Colors.black.withOpacity(0.35),
                  borderStrokeWidth: 1.5,
                ),
              ]),
            MarkerLayer(
              markers: _entries.asMap().entries.map((kv) {
                final idx = kv.key;
                final entry = kv.value;
                final isFirst = idx == 0;
                final isLast = idx == _entries.length - 1;
                final isHigh = _highlighted == entry;

                Color dotColor = _lime.withOpacity(0.6);
                double size = 9;

                if (isFirst) { dotColor = _purple;  size = 13; }
                if (isLast)  { dotColor = _lime;     size = 15; }
                if (isHigh && !isLast && !isFirst) {
                  dotColor = _white;
                  size = 13;
                }

                return Marker(
                  point: _toLatLng(entry),
                  width: size + 14,
                  height: size + 14,
                  child: GestureDetector(
                    onTap: () => setState(() => _highlighted = entry),
                    child: Center(
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.black.withOpacity(0.5),
                              width: 1.5),
                          boxShadow: (isHigh || isLast)
                              ? [
                            BoxShadow(
                              color: dotColor.withOpacity(0.7),
                              blurRadius: 10,
                              spreadRadius: 3,
                            )
                          ]
                              : null,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Fit-to-trail
        Positioned(
          top: 12,
          left: 12,
          child: GestureDetector(
            onTap: _fitTrail,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _cardBorder),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 8)
                ],
              ),
              child: const Icon(Icons.fit_screen_rounded,
                  color: _white, size: 20),
            ),
          ),
        ),

        // Legend
        Positioned(
          top: 12,
          right: 12,
          child: _buildLegend(),
        ),

        // Selected fix card
        if (_highlighted != null)
          Positioned(
            bottom: 16,
            left: 12,
            right: 12,
            child: _buildSelectedFixCard(_highlighted!),
          ),
      ],
    );
  }

  Widget _buildSelectedFixCard(LocationHistoryEntry entry) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _lime.withOpacity(0.45), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: _lime.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 2),
          BoxShadow(
              color: Colors.black.withOpacity(0.6), blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: _lime, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.location_on_rounded,
                color: Colors.black, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullFmt.format(entry.recordedAt),
                  style: const TextStyle(
                      color: _white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.latitude.toStringAsFixed(5)}, '
                      '${entry.longitude.toStringAsFixed(5)}',
                  style: TextStyle(color: _grey, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _chip(
            '±${entry.accuracy.toStringAsFixed(0)}m',
            entry.accuracy < 20 ? _lime : const Color(0xFFFFB84D),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.5), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendRow(_purple, 'Start'),
          const SizedBox(height: 5),
          _legendRow(_lime, 'Latest'),
          const SizedBox(height: 5),
          _legendRow(_lime.withOpacity(0.5), 'Path'),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 9,
            height: 9,
            decoration:
            BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: _grey, fontSize: 10)),
      ],
    );
  }

  // ── Timeline tab ──────────────────────────────────────────────────────────

  Widget _buildTimelineTab() {
    final reversed = _entries.reversed.toList();
    final grouped = <String, List<LocationHistoryEntry>>{};
    for (final e in reversed) {
      grouped.putIfAbsent(_dateFmt.format(e.recordedAt), () => []).add(e);
    }
    final days = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: days.length,
      itemBuilder: (_, i) {
        final day = days[i];
        final dayList = grouped[day]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _lime,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      day.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${dayList.length} fixes',
                      style: TextStyle(color: _grey, fontSize: 11)),
                ],
              ),
            ),
            ...dayList.asMap().entries.map((kv) {
              final idx = kv.key;
              final entry = kv.value;
              final isFirst = idx == dayList.length - 1 &&
                  days.indexOf(day) == days.length - 1;
              final isLast =
                  idx == 0 && days.indexOf(day) == 0;
              final isHigh = _highlighted == entry;

              return _buildTimelineRow(
                entry: entry,
                isFirst: isFirst,
                isLast: isLast,
                isHighlighted: isHigh,
                onTap: () => _jumpTo(entry),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildTimelineRow({
    required LocationHistoryEntry entry,
    required bool isFirst,
    required bool isLast,
    required bool isHighlighted,
    required VoidCallback onTap,
  }) {
    final dotColor = isFirst
        ? _purple
        : isLast
        ? _lime
        : _lime.withOpacity(0.45);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: isHighlighted
              ? _lime.withOpacity(0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHighlighted
                ? _lime.withOpacity(0.3)
                : Colors.transparent,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: isFirst ? 20 : 0,
                      bottom: isLast ? 20 : 0,
                      child: Container(
                          width: 2,
                          color: _lime.withOpacity(0.1)),
                    ),
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        border:
                        Border.all(color: Colors.black, width: 2),
                        boxShadow: (isLast || isHighlighted)
                            ? [
                          BoxShadow(
                            color: dotColor.withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 11, horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _timeFmt.format(entry.recordedAt),
                              style: TextStyle(
                                color: isHighlighted ? _lime : _white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${entry.latitude.toStringAsFixed(4)}, '
                                  '${entry.longitude.toStringAsFixed(4)}',
                              style: TextStyle(
                                  color: _grey, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _chip(
                            '±${entry.accuracy.toStringAsFixed(0)}m',
                            entry.accuracy < 20
                                ? _lime
                                : const Color(0xFFFFB84D),
                          ),
                          if (entry.speed > 0.5) ...[
                            const SizedBox(height: 4),
                            _chip(
                              '${(entry.speed * 3.6).toStringAsFixed(1)} km/h',
                              _grey,
                            ),
                          ],
                          if (!entry.synced) ...[
                            const SizedBox(height: 4),
                            _chip('OFFLINE',
                                const Color(0xFFFFB84D)),
                          ],
                        ],
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          color: _grey.withOpacity(0.35), size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── Loader ────────────────────────────────────────────────────────────────

  Widget _buildLoader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              color: _lime,
              strokeWidth: 3,
              backgroundColor: _lime.withOpacity(0.12),
            ),
          ),
          const SizedBox(height: 18),
          Text('Loading history…',
              style: TextStyle(
                  color: _grey,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _lime.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
                border:
                Border.all(color: _lime.withOpacity(0.22)),
              ),
              child: Icon(Icons.location_off_rounded,
                  color: _lime.withOpacity(0.45), size: 38),
            ),
            const SizedBox(height: 20),
            const Text(
              'No location data\nfor this period',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'History is recorded every 15 minutes\nwhile the app is running',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _grey, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _load,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  color: _lime,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'RETRY',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Date range enum ───────────────────────────────────────────────────────────

enum _DateRange {
  today('Today'),
  last24h('Last 24h'),
  last3d('3 Days'),
  last7d('7 Days'),
  last30d('30 Days');

  final String label;
  const _DateRange(this.label);

  (DateTime?, DateTime?) get range {
    final now = DateTime.now();
    switch (this) {
      case _DateRange.today:
        return (DateTime(now.year, now.month, now.day), null);
      case _DateRange.last24h:
        return (now.subtract(const Duration(hours: 24)), null);
      case _DateRange.last3d:
        return (now.subtract(const Duration(days: 3)), null);
      case _DateRange.last7d:
        return (now.subtract(const Duration(days: 7)), null);
      case _DateRange.last30d:
        return (now.subtract(const Duration(days: 30)), null);
    }
  }
}