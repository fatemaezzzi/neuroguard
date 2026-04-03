// lib/features/safezone/safezone_editor.dart
//
// SafeZoneEditorPage — rewired to use SafeZoneEditorNotifier (Riverpod).
//
// CHANGES FROM ORIGINAL
//   • Extends ConsumerStatefulWidget / ConsumerState
//   • All local state (_centerPoint, _radiusMeters, _isLoadingExisting,
//     _isSaving, _isFetchingGPS, _hasUnsavedChanges) REMOVED — read from
//     safeZoneEditorProvider
//   • _loadExistingZone() + _saveSafeZone() logic MOVED to notifier
//   • setState() calls for state fields REPLACED with notifier.setCenter() /
//     setRadius() / save()
//   • Animations and map controller are unchanged — they require a
//     TickerProvider so they remain in the widget
//
// SURGICAL SCOPE: GeofenceService, models, palette, and all widget structure
// are unchanged.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:neuroguard/core/providers/location_providers.dart';

class SafeZoneEditorPage extends ConsumerStatefulWidget {
  final String patientId;
  final String patientName;

  const SafeZoneEditorPage({
    Key? key,
    required this.patientId,
    required this.patientName,
  }) : super(key: key);

  @override
  ConsumerState<SafeZoneEditorPage> createState() =>
      _SafeZoneEditorPageState();
}

class _SafeZoneEditorPageState extends ConsumerState<SafeZoneEditorPage>
    with SingleTickerProviderStateMixin {
  // ─── Map ──────────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // ─── Animation (stays in widget — needs TickerProvider) ───────────────────
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnim;

  // ─── NeuroGuard Palette ───────────────────────────────────────────────────
  static const Color _darkBg = Color(0xFF0D0D1A);
  static const Color _cardBg = Color(0xFF1A1A2E);
  static const Color _purple = Color(0xFF7B2FBE);
  static const Color _green  = Color(0xFF9BFF4F);
  static const Color _teal   = Color(0xFF2DD4BF);
  static const Color _amber  = Color(0xFFFFB84D);
  static const Color _red    = Color(0xFFFF3B3B);
  static const Color _white  = Color(0xFFFFFFFF);

  // ─── Radius presets ───────────────────────────────────────────────────────
  static const List<_RadiusPreset> _presets = [
    _RadiusPreset(label: 'House',         meters: 100,  icon: Icons.home_rounded),
    _RadiusPreset(label: 'Block',         meters: 300,  icon: Icons.location_city_rounded),
    _RadiusPreset(label: 'Neighbourhood', meters: 600,  icon: Icons.map_rounded),
    _RadiusPreset(label: 'Wide',          meters: 1000, icon: Icons.public_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // All state is read from the provider — no local mutable fields
    final editorState = ref.watch(safeZoneEditorProvider(widget.patientId));

    // When load completes and a saved zone exists, animate map to it
    ref.listen<SafeZoneEditorState>(
      safeZoneEditorProvider(widget.patientId),
          (prev, next) {
        if (prev?.isLoadingExisting == true &&
            next.isLoadingExisting == false &&
            next.centerPoint != null &&
            _mapReady) {
          _mapController.move(next.centerPoint!, 15.5);
        }
      },
    );

    return WillPopScope(
      onWillPop: () => _onWillPop(editorState),
      child: Scaffold(
        backgroundColor: _darkBg,
        body: Stack(
          children: [
            _buildMap(editorState),
            if (editorState.centerPoint == null && !editorState.isLoadingExisting)
              _buildCrosshairHint(),
            _buildTopBar(editorState),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildBottomPanel(editorState),
            ),
            if (editorState.isLoadingExisting) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MAP
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildMap(SafeZoneEditorState s) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: s.centerPoint ?? const LatLng(19.0760, 72.8777),
        initialZoom: 15.0,
        minZoom: 10.0,
        maxZoom: 20.0,
        onMapReady: () => setState(() => _mapReady = true),
        onTap: (_, latLng) {
          HapticFeedback.selectionClick();
          ref
              .read(safeZoneEditorProvider(widget.patientId).notifier)
              .setCenter(latLng);
          _mapController.move(latLng, _mapController.camera.zoom);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.yourteam.neuroguard',
          maxNativeZoom: 19,
        ),
        if (s.centerPoint != null)
          CircleLayer(circles: [
            CircleMarker(
              point: s.centerPoint!,
              radius: s.radiusMeters,
              useRadiusInMeter: true,
              color: _teal.withOpacity(0.13),
              borderColor: _teal,
              borderStrokeWidth: 2.0,
            ),
          ]),
        if (s.centerPoint != null)
          CircleLayer(circles: [
            CircleMarker(
              point: s.centerPoint!,
              radius: s.radiusMeters * 0.75,
              useRadiusInMeter: true,
              color: Colors.transparent,
              borderColor: _teal.withOpacity(0.25),
              borderStrokeWidth: 1.0,
            ),
          ]),
        if (s.centerPoint != null)
          MarkerLayer(markers: [
            Marker(
              point: s.centerPoint!,
              width: 60, height: 60,
              child: _buildCentreMarker(),
            ),
          ]),
      ],
    );
  }

  Widget _buildCentreMarker() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: _pulseAnim.value,
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color:  _teal.withOpacity(0.18),
                  shape:  BoxShape.circle,
                  border: Border.all(
                      color: _teal.withOpacity(0.35), width: 1.5),
                ),
              ),
            ),
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color:  _teal,
                shape:  BoxShape.circle,
                border: Border.all(color: _white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                      color: _teal.withOpacity(0.55),
                      blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: const Icon(Icons.home_rounded,
                  color: Colors.white, size: 15),
            ),
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CROSSHAIR HINT
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildCrosshairHint() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        _cardBg.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(color: _teal.withOpacity(0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_rounded, color: _teal, size: 36),
            const SizedBox(height: 8),
            const Text(
              'Tap the map to place\nthe safe zone centre',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w600, height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar(SafeZoneEditorState s) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: [_darkBg.withOpacity(0.96), Colors.transparent],
            stops: const [0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
            child: Row(
              children: [
                _topBarButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () async {
                    if (await _onWillPop(s)) Navigator.pop(context);
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.patientName.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white38, fontSize: 10,
                          letterSpacing: 1.8, fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        'Edit Safe Zone',
                        style: TextStyle(
                          color: _white, fontSize: 20,
                          fontWeight: FontWeight.w800, letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                _topBarButton(
                  icon:    s.isFetchingGPS
                      ? Icons.hourglass_top_rounded
                      : Icons.my_location_rounded,
                  color:   _amber,
                  tooltip: 'Use my current location',
                  onTap:   s.isFetchingGPS ? null : _useCurrentLocation,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBarButton({
    required IconData icon,
    VoidCallback? onTap,
    Color color = Colors.white,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 42, height: 42,
          decoration: BoxDecoration(
            color:        _cardBg.withOpacity(0.9),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: onTap == null
                  ? Colors.white10
                  : color.withOpacity(0.3),
            ),
          ),
          child: Icon(icon,
              color: onTap == null ? Colors.white24 : color, size: 20),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BOTTOM PANEL
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildBottomPanel(SafeZoneEditorState s) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color:        _cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border:       Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.55),
              blurRadius: 40, offset: const Offset(0, -8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Presets ────────────────────────────────────────────────────
          const Text('QUICK PRESETS',
              style: TextStyle(
                  color: Colors.white38, fontSize: 10,
                  letterSpacing: 1.8, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _buildPresetRow(s),

          const SizedBox(height: 20),

          // ── Radius slider ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Radius',
                  style: TextStyle(
                      color: _white, fontSize: 15,
                      fontWeight: FontWeight.w700)),
              _radiusBadge(s.radiusMeters),
            ],
          ),
          const SizedBox(height: 8),
          _buildSlider(s),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('50m',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                Text('1000m',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _buildZoneSummaryCard(s),
          const SizedBox(height: 20),
          _buildSaveButton(s),
        ],
      ),
    );
  }

  Widget _buildPresetRow(SafeZoneEditorState s) {
    return Row(
      children: _presets.map((preset) {
        final bool selected = (s.radiusMeters - preset.meters).abs() < 1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ref
                    .read(safeZoneEditorProvider(widget.patientId).notifier)
                    .setRadius(preset.meters.toDouble());
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? _teal.withOpacity(0.18)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:  selected ? _teal : Colors.white12,
                    width:  selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(preset.icon,
                        color: selected ? _teal : Colors.white38, size: 18),
                    const SizedBox(height: 4),
                    Text(
                      preset.label,
                      style: TextStyle(
                        color: selected ? _teal : Colors.white54,
                        fontSize: 9,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${preset.meters}m',
                      style: TextStyle(
                        color: selected ? _teal : Colors.white24,
                        fontSize: 8, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _radiusBadge(double radius) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color:        _teal.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _teal.withOpacity(0.4)),
      ),
      child: Text(
        '${radius.round()}m',
        style: const TextStyle(
          color: _teal, fontSize: 15,
          fontWeight: FontWeight.w800, letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildSlider(SafeZoneEditorState s) {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor:   _teal,
        inactiveTrackColor: Colors.white12,
        thumbColor:         _teal,
        overlayColor:       _teal.withOpacity(0.18),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
        trackHeight: 4,
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value:     s.radiusMeters,
        min:       50,
        max:       1000,
        divisions: 190,
        onChanged: (value) {
          ref
              .read(safeZoneEditorProvider(widget.patientId).notifier)
              .setRadius(value);
        },
      ),
    );
  }

  Widget _buildZoneSummaryCard(SafeZoneEditorState s) {
    if (s.centerPoint == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        _amber.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: _amber.withOpacity(0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: _amber, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tap anywhere on the map above to place the safe zone centre.',
                style: TextStyle(color: _amber, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        _teal.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: _teal.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color:        _teal.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield_rounded, color: _teal, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Safe Zone Preview',
                    style: TextStyle(
                        color: _white, fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${s.radiusMeters.round()}m radius  •  '
                      '${_radiusLabel(s.radiusMeters)}  •  '
                      '${s.centerPoint!.latitude.toStringAsFixed(4)}, '
                      '${s.centerPoint!.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
          if (s.hasUnsavedChanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:        _amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border:       Border.all(color: _amber.withOpacity(0.4)),
              ),
              child: const Text('Unsaved',
                  style: TextStyle(
                      color: _amber, fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(SafeZoneEditorState s) {
    final bool canSave = s.centerPoint != null && !s.isSaving;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity, height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: canSave
            ? [
          BoxShadow(
              color: _green.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ]
            : [],
      ),
      child: ElevatedButton(
        onPressed: canSave ? _saveSafeZone : null,
        style: ElevatedButton.styleFrom(
          backgroundColor:         _green,
          foregroundColor:         _darkBg,
          disabledBackgroundColor: Colors.white10,
          disabledForegroundColor: Colors.white24,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: s.isSaving
            ? const SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: Colors.black),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, size: 20),
            const SizedBox(width: 8),
            Text(
              s.hasUnsavedChanges
                  ? 'Save Safe Zone'
                  : 'Safe Zone Saved',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: _darkBg.withOpacity(0.75),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44, height: 44,
              child: CircularProgressIndicator(color: _purple, strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            const Text('Loading safe zone...',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ACTIONS
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    final notifier =
    ref.read(safeZoneEditorProvider(widget.patientId).notifier);
    notifier.setFetchingGPS(true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        _showSnackbar(
            message: 'Location permission denied. Please enable in settings.',
            isError: true);
        return;
      }

      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      if (!mounted) return;

      final LatLng myLocation = LatLng(pos.latitude, pos.longitude);
      notifier.setCenter(myLocation);

      if (_mapReady) _mapController.move(myLocation, 16.0);
      HapticFeedback.mediumImpact();
    } catch (_) {
      _showSnackbar(
          message: 'Could not get location. Try tapping the map instead.',
          isError: true);
    } finally {
      if (mounted) notifier.setFetchingGPS(false);
    }
  }

  Future<void> _saveSafeZone() async {
    HapticFeedback.mediumImpact();
    final notifier =
    ref.read(safeZoneEditorProvider(widget.patientId).notifier);
    final success = await notifier.save();

    if (!mounted) return;

    if (success) {
      HapticFeedback.heavyImpact();
      final radius =
          ref.read(safeZoneEditorProvider(widget.patientId)).radiusMeters;
      _showSnackbar(
        message: '✅  Safe zone saved — ${radius.round()}m radius',
        isError: false,
      );
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context, true);
    } else {
      _showSnackbar(
        message: 'Failed to save. Check your connection and try again.',
        isError: true,
      );
    }
  }

  Future<bool> _onWillPop(SafeZoneEditorState s) async {
    if (!s.hasUnsavedChanges) return true;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Unsaved Changes',
            style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
        content: const Text(
          'You have unsaved changes to the safe zone. Leave without saving?',
          style: TextStyle(color: Colors.white60, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing',
                style: TextStyle(color: _teal)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard',
                style: TextStyle(color: _red)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _showSnackbar({required String message, required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? _red : _teal,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        content: Text(
          message,
          style: TextStyle(
            color: isError ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600, fontSize: 13,
          ),
        ),
      ),
    );
  }

  String _radiusLabel(double meters) {
    if (meters <= 150) return 'House boundary';
    if (meters <= 400) return 'City block';
    if (meters <= 700) return 'Neighbourhood';
    return 'Wide area';
  }
}

class _RadiusPreset {
  final String   label;
  final int      meters;
  final IconData icon;
  const _RadiusPreset({
    required this.label,
    required this.meters,
    required this.icon,
  });
}