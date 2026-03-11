import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NavigateHomePage — Patient's in-app navigation map
//
// Opened when patient taps the LOCATION button on PatientHome.
// Replaces the old navigate_home_service.dart which opened a browser.
//
// Shows:
//   • Live blue "YOU" dot  — updates every 5 seconds from device GPS
//   • Red "HOME" pin       — reads safeZone.centerLat/Lng from Firestore
//   • Blue route polyline  — drawn via OSRM (free, no API key)
//   • Distance + walk time — bottom card, auto-refreshes as patient moves
//   • TTS voice guidance   — speaks calmly on open
//   • "I'm Home!" button   — closes page + notifies caregiver
//   • ⊕ Re-centre button   — snaps map back to patient position
// ─────────────────────────────────────────────────────────────────────────────

class NavigateHomePage extends StatefulWidget {
  final String patientId;
  const NavigateHomePage({Key? key, required this.patientId}) : super(key: key);

  @override
  State<NavigateHomePage> createState() => _NavigateHomePageState();
}

class _NavigateHomePageState extends State<NavigateHomePage>
    with TickerProviderStateMixin {

  // ─── Colours ──────────────────────────────────────────────────────────────
  static const Color _lime    = Color(0xFFB5E800);
  static const Color _darkBg  = Color(0xFF1A1A1A);
  static const Color _cardBg  = Color(0xFF242424);
  static const Color _blue    = Color(0xFF2196F3);
  static const Color _red     = Color(0xFFE53935);

  // ─── Map ──────────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // ─── Data ─────────────────────────────────────────────────────────────────
  LatLng? _patientPos;
  LatLng? _homePos;
  List<LatLng> _routePoints = [];
  double? _distanceMeters;
  int?    _durationSeconds;

  // ─── UI state ─────────────────────────────────────────────────────────────
  bool   _isLoading  = true;
  String _loadingMsg = 'Finding your location…';

  // ─── Background tasks ─────────────────────────────────────────────────────
  Timer? _liveTimer;
  final FlutterTts _tts = FlutterTts();

  // ─── Pulse animation for patient dot ──────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ──────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.3).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _boot();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _pulseCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Boot sequence
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _boot() async {
    // 1. Read home coords from Firestore (same path GeofenceService uses)
    _setMsg('Reading home location…');
    final home = await _fetchHomeCoords();
    if (home == null) {
      _setMsg('Home location not set.\nAsk your caregiver to set the Safe Zone.');
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    _homePos = home;

    // 2. Get patient GPS
    _setMsg('Getting your position…');
    final pos = await _fetchGPS();
    if (pos == null) {
      _setMsg('Could not get your location.\nPlease make sure GPS is on.');
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    _patientPos = pos;

    // 3. Draw walking route via OSRM
    _setMsg('Drawing route…');
    await _fetchRoute();

    // 4. Hide loading, show map
    if (mounted) setState(() => _isLoading = false);

    // 5. Fit map to show full route
    if (_mapReady && _routePoints.isNotEmpty) {
      _fitRoute();
    }

    // 6. Speak calm message
    await _speak();

    // 7. Notify caregiver via Firestore
    await _notifyCaregiver(status: 'NAVIGATING');

    // 8. Start live position refresh every 5 seconds
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _liveUpdate());
  }

  void _setMsg(String msg) {
    if (mounted) setState(() => _loadingMsg = msg);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Data fetchers
  // ──────────────────────────────────────────────────────────────────────────

  Future<LatLng?> _fetchHomeCoords() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.patientId)
          .get();
      final data = doc.data();
      if (data == null || data['safeZone'] == null) return null;
      final sz = data['safeZone'] as Map<String, dynamic>;
      return LatLng(
        (sz['centerLat'] as num).toDouble(),
        (sz['centerLng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<LatLng?> _fetchGPS() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return LatLng(last.latitude, last.longitude);
      return null;
    }
  }

  // OSRM walking route — completely free, no API key
  Future<void> _fetchRoute() async {
    if (_patientPos == null || _homePos == null) return;
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/'
            '${_patientPos!.longitude},${_patientPos!.latitude};'
            '${_homePos!.longitude},${_homePos!.latitude}'
            '?overview=full&geometries=geojson',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;

      final body   = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final route    = routes[0] as Map<String, dynamic>;
      final coords   = (route['geometry'] as Map)['coordinates'] as List;
      // OSRM gives [lng, lat] — flip to LatLng(lat, lng)
      final points   = coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      if (mounted) setState(() {
        _routePoints    = points;
        _distanceMeters = (route['distance'] as num).toDouble();
        _durationSeconds = (route['duration'] as num).toInt();
      });
    } catch (_) {
      // Route failed — map still shows with just the two pins
    }
  }

  void _fitRoute() {
    if (_routePoints.isEmpty) return;
    final lats = _routePoints.map((p) => p.latitude);
    final lngs = _routePoints.map((p) => p.longitude);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(lats.reduce((a, b) => a < b ? a : b),
              lngs.reduce((a, b) => a < b ? a : b)),
          LatLng(lats.reduce((a, b) => a > b ? a : b),
              lngs.reduce((a, b) => a > b ? a : b)),
        ),
        padding: const EdgeInsets.fromLTRB(48, 100, 48, 240),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Live update (every 5s)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _liveUpdate() async {
    final pos = await _fetchGPS();
    if (pos == null || !mounted) return;

    // Check if patient moved >15m before re-fetching route (saves OSRM calls)
    final moved = _patientPos == null ? 999.0 : Geolocator.distanceBetween(
      _patientPos!.latitude, _patientPos!.longitude,
      pos.latitude, pos.longitude,
    );

    setState(() => _patientPos = pos);

    if (moved > 15) await _fetchRoute();

    // Push to Firestore so caregiver tracker also updates in real-time
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.patientId)
          .update({
        'liveLocation.latitude':  pos.latitude,
        'liveLocation.longitude': pos.longitude,
        'liveLocation.timestamp': FieldValue.serverTimestamp(),
        'liveLocation.isStale':   false,
      });
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TTS
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _speak() async {
    if (_distanceMeters == null) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.42);
    await _tts.setVolume(1.0);

    final String msg;
    if (_distanceMeters! < 200) {
      msg = 'You are very close to home. Keep walking, you are almost there.';
    } else if (_distanceMeters! < 1000) {
      msg = "Don't worry. I will guide you home. "
          "You are about ${_distanceMeters!.round()} metres away. "
          "Follow the blue line on the map.";
    } else {
      msg = "Don't worry. I will guide you home. "
          "You are about ${(_distanceMeters! / 1000).toStringAsFixed(1)} kilometres away. "
          "Follow the blue line on the map.";
    }
    await _tts.speak(msg);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Firestore event logging (notifies caregiver's TrackerPage stream)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _notifyCaregiver({required String status}) async {
    if (_patientPos == null || _homePos == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.patientId)
          .update({
        'navigateHomeEvent': {
          'patientLat':             _patientPos!.latitude,
          'patientLng':             _patientPos!.longitude,
          'homeLat':                _homePos!.latitude,
          'homeLng':                _homePos!.longitude,
          'distanceFromHomeMeters': _distanceMeters ?? 0,
          'triggeredAt':            FieldValue.serverTimestamp(),
          'status':                 status,
        },
      });
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Re-centre button
  // ──────────────────────────────────────────────────────────────────────────

  void _centreOnPatient() {
    if (_patientPos != null && _mapReady) {
      _mapController.move(_patientPos!, 17.0);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // "I'm Home!" button
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _onImHome() async {
    _liveTimer?.cancel();
    await _tts.speak('Welcome home! You made it.');
    await _notifyCaregiver(status: 'ARRIVED');
    if (mounted) Navigator.pop(context);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomCard()),
          if (_isLoading) _buildLoader(),
        ],
      ),
    );
  }

  // ─── Map ──────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final center = _patientPos ?? _homePos ?? const LatLng(19.0760, 72.8777);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15.5,
        minZoom: 10.0,
        maxZoom: 20.0,
        onMapReady: () {
          setState(() => _mapReady = true);
          if (_routePoints.isNotEmpty) _fitRoute();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.yourteam.neuroguard',
          maxNativeZoom: 19,
        ),
        // Blue walking route
        if (_routePoints.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
              points:            _routePoints,
              color:             _blue,
              strokeWidth:       5.5,
              borderColor:       Colors.white.withOpacity(0.35),
              borderStrokeWidth: 1.5,
            ),
          ]),
        // Home pin
        if (_homePos != null)
          MarkerLayer(markers: [
            Marker(point: _homePos!, width: 60, height: 76, child: _homePin()),
          ]),
        // Patient dot
        if (_patientPos != null)
          MarkerLayer(markers: [
            Marker(point: _patientPos!, width: 60, height: 60, child: _patientDot()),
          ]),
      ],
    );
  }

  Widget _homePin() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _red, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: _red.withOpacity(0.5), blurRadius: 12, spreadRadius: 2)],
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 24),
        ),
        Container(width: 3, height: 10, color: _red),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(4)),
          child: const Text('HOME', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }

  Widget _patientDot() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: _pulseAnim.value,
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: _blue.withOpacity(0.18),
                shape: BoxShape.circle,
                border: Border.all(color: _blue.withOpacity(0.45), width: 1.5),
              ),
            ),
          ),
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: _blue, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: _blue.withOpacity(0.6), blurRadius: 8, spreadRadius: 2)],
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(4)),
              child: const Text('YOU', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [_darkBg.withOpacity(0.92), _darkBg.withOpacity(0.0)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 36),
            child: Row(
              children: [
                _iconBtn(Icons.arrow_back_rounded, () => Navigator.pop(context)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WALKING HOME',
                          style: TextStyle(color: Colors.white54, fontSize: 11,
                              letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                      Text('Follow the blue line',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                // ⊕ Re-centre on patient
                _iconBtn(Icons.my_location_rounded, _centreOnPatient, color: _lime),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {Color color = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: _cardBg.withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  // ─── Bottom info card ─────────────────────────────────────────────────────

  Widget _buildBottomCard() {
    final dist = _distanceMeters;
    final dur  = _durationSeconds;

    final String distText = dist == null
        ? 'Calculating route…'
        : dist < 1000
        ? '${dist.round()} m to home'
        : '${(dist / 1000).toStringAsFixed(1)} km to home';

    final String timeText = dur == null
        ? ''
        : dur < 60 ? 'Less than 1 min walk' : '~${(dur / 60).ceil()} min walk';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _blue.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.directions_walk_rounded, color: _blue, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(distText,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    if (timeText.isNotEmpty)
                      Text(timeText,
                          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
                  ],
                ),
              ),
              // Legend
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _legend(_blue, 'You'),
                  const SizedBox(height: 4),
                  _legend(_red,  'Home'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton.icon(
              onPressed: _onImHome,
              icon: const Icon(Icons.home_rounded, size: 22),
              label: const Text("I'm Home!",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _lime,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }

  // ─── Loading overlay ──────────────────────────────────────────────────────

  Widget _buildLoader() {
    return Container(
      color: _darkBg.withOpacity(0.90),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 50, height: 50,
              child: CircularProgressIndicator(color: Color(0xFFB5E800), strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_loadingMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 17,
                      fontWeight: FontWeight.w600, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}