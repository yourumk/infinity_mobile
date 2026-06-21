import 'dart:ui';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import '../services/routing_service.dart';
import '../widgets/glass_card.dart';
import 'sales_page.dart';
import 'package:url_launcher/url_launcher.dart';

class FleetMapPage extends StatefulWidget {
  final dynamic targetVanId;
  const FleetMapPage({super.key, this.targetVanId});

  @override
  State<FleetMapPage> createState() => _FleetMapPageState();
}

class _FleetMapPageState extends State<FleetMapPage> {
  final ApiService _api = ApiService();
  final RoutingService _routing = RoutingService();
  final MapController _mapController = MapController();
  Timer? _syncTimer;
  // 🛠️ FIX SELECTOR & STATE : Abonnement à l'Event Bus
  StreamSubscription<int?>? _whSub;
  
  bool _isLoading = true;
  List<dynamic> _vans = [];
  List<dynamic> _warehouses = [];
  List<dynamic> _clients = [];
  bool _showClients = false;

  Map<int, List<LatLng>> _osrmRoutes = {};

  String _statusFilter = 'all';

  // 🟢 VUES HD/SD CORRIGÉES
  bool _isHD = false;
  int _currentLayerIndex = 0;

  final List<Map<String, dynamic>> _mapLayers = [
    {'name': '🗺️ Plan (Google)', 'short': 'Plan', 'url': 'http://mt{s}.google.com/vt/lyrs=m{hd}&x={x}&y={y}&z={z}', 'subdomains': ['0', '1', '2', '3']},
    {'name': '🌍 Satellite (Google)', 'short': 'Sat.', 'url': 'http://mt{s}.google.com/vt/lyrs=y{hd}&x={x}&y={y}&z={z}', 'subdomains': ['0', '1', '2', '3']},
    {'name': '⛰️ Relief (Google)', 'short': 'Relief', 'url': 'http://mt{s}.google.com/vt/lyrs=p{hd}&x={x}&y={y}&z={z}', 'subdomains': ['0', '1', '2', '3']},
    {'name': '🚦 Trafic (Google)', 'short': 'Trafic', 'url': 'http://mt{s}.google.com/vt/lyrs=m,traffic{hd}&x={x}&y={y}&z={z}', 'subdomains': ['0', '1', '2', '3']},
    {'name': '🏙️ Clair (Épuré)', 'short': 'Clair', 'url': 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{hd}.png', 'subdomains': ['a', 'b', 'c', 'd']},
    {'name': '🌙 Sombre (Nuit)', 'short': 'Nuit', 'url': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{hd}.png', 'subdomains': ['a', 'b', 'c', 'd']},
    {'name': '🛣️ OpenStreetMap', 'short': 'OSM', 'url': 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', 'subdomains': ['a', 'b', 'c']},
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadMapData();
    // 🟢 AUTO-SYNC toutes les 10 secondes pour voir les fourgons bouger
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadMapData(silent: true));
    
    // 🛠️ FIX SELECTOR & STATE : Écouter le changement de dépôt
    _whSub = _api.onWarehouseChanged.listen((_) {
      _loadMapData(silent: false); // silent: false pour afficher le loader (setState(() { _isLoading = true; }))
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _whSub?.cancel(); // 🛠️ FIX SELECTOR & STATE : Libération propre
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isHD = prefs.getBool('fleet_map_hd') ?? false;
      _currentLayerIndex = prefs.getInt('fleet_map_layer') ?? 0;
      if (_currentLayerIndex >= _mapLayers.length) _currentLayerIndex = 0;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fleet_map_hd', _isHD);
    await prefs.setInt('fleet_map_layer', _currentLayerIndex);
  }

  // 🟢 URL DYNAMIQUE RÉPARÉE
  String _getDynamicTileUrl() {
    final layer = _mapLayers[_currentLayerIndex];
    String rawUrl = layer['url'];
    bool isGoogle = rawUrl.contains('google');
    String hdParam = _isHD ? (isGoogle ? '&scale=2' : '@2x') : '';
    return rawUrl.replaceAll('{hd}', hdParam);
  }

  Future<void> _loadMapData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final data = await _api.getMapData();
      List<dynamic> clientsData = [];
      try {
        clientsData = await _api.getTiersWithQueue('client', '');
      } catch (_) {}

      if (mounted) {
        setState(() {
          _vans = data['vans'] ?? [];
          _warehouses = data['warehouses'] ?? [];
          _clients = clientsData.where((c) => c['geo_lat'] != null && c['geo_lng'] != null && c['geo_lat'].toString().isNotEmpty && c['geo_lng'].toString().isNotEmpty).toList();
          
          if (!silent) {
            _isLoading = false;
            // 🛠️ FIX MAP CRASH : Attendre que FlutterMap soit construit avant d'utiliser _mapController
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _recenterMap();
            });
          }
        });
        _calculateRoutes();
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _calculateRoutes() async {
    for (var van in _vans) {
      if (van['route_history'] != null) {
        List<dynamic> history = van['route_history'];
        if (history.length > 1) {
          List<LatLng> points = history
              .where((p) => p['geo_lat'] != null && p['geo_lng'] != null)
              .map((p) => LatLng(double.parse(p['geo_lat'].toString()), double.parse(p['geo_lng'].toString())))
              .toList();
          
          if (van['geo_lat'] != null) {
             points.add(LatLng(double.parse(van['geo_lat'].toString()), double.parse(van['geo_lng'].toString())));
          }
          
          if (points.length >= 2) {
             if (points.length > 90) {
               points = points.sublist(points.length - 90);
             }
             final route = await _routing.getRoute(points);
             if (route.isNotEmpty && mounted) {
                setState(() {
                  _osrmRoutes[van['van_id'] ?? van['id'] ?? 0] = route;
                });
             }
          }
        }
      }
    }
  }

  void _recenterMap() {
    List<LatLng> allPoints = [];
    final filteredVans = _statusFilter == 'all' ? _vans : _vans.where((v) => v['status'] == _statusFilter).toList();
    
    for (var v in filteredVans) {
      if (v['geo_lat'] != null) allPoints.add(LatLng(double.parse(v['geo_lat'].toString()), double.parse(v['geo_lng'].toString())));
    }
    for (var w in _warehouses) {
      if (w['latitude'] != null) allPoints.add(LatLng(double.parse(w['latitude'].toString()), double.parse(w['longitude'].toString())));
    }

    if (widget.targetVanId != null) {
      final target = _vans.firstWhere((v) => v['van_id'] == widget.targetVanId || v['id'] == widget.targetVanId, orElse: () => null);
      if (target != null && target['geo_lat'] != null) {
        final pt = LatLng(double.parse(target['geo_lat'].toString()), double.parse(target['geo_lng'].toString()));
        _mapController.move(pt, 16.0);
        return; 
      }
    }

    if (allPoints.isNotEmpty) {
      try {
        final bounds = LatLngBounds.fromPoints(allPoints);
        _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
      } catch (e) {
        debugPrint("Erreur recentrage map: $e");
      }
    } else {
      try {
        _mapController.move(const LatLng(36.7538, 3.0588), 10.0); // Alger par défaut
      } catch (e) {}
    }
  }

  String _fmtMoney(dynamic amount) {
    final val = double.tryParse(amount?.toString() ?? '0') ?? 0.0;
    return NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2).format(val);
  }

  void _openLayerSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E24).withOpacity(0.9) : Colors.white.withOpacity(0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(10, 20, 10, MediaQuery.of(ctx).padding.bottom + 10), // 🛠️ MODULE 1 : Padding dynamique Android
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Choisir une vue cartographique", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 15),
                ...List.generate(_mapLayers.length, (index) {
                  final layer = _mapLayers[index];
                  final isActive = index == _currentLayerIndex;
                  return ListTile(
                    title: Text(layer['name'], style: TextStyle(fontWeight: isActive ? FontWeight.w900 : FontWeight.w600, color: isActive ? AppColors.primary : null)),
                    trailing: isActive ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                    onTap: () {
                      setState(() => _currentLayerIndex = index);
                      _savePreferences();
                      Navigator.pop(ctx);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      }
    );
  }

  void _showClientDetails(dynamic client) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        double balance = double.tryParse(client['balance']?.toString() ?? '0') ?? 0.0;
        bool hasDebt = balance > 0;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2C).withOpacity(0.95) : Colors.white.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50, height: 5, 
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(10))
                  )
                ),
                const SizedBox(height: 20),
                Text(client['name'] ?? 'Client Inconnu', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                if (client['phone'] != null && client['phone'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.phone, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(client['phone'], style: const TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: hasDebt ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(hasDebt ? "Dette" : "Solde", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: hasDebt ? Colors.red : Colors.green)),
                      Text("${balance.toStringAsFixed(2)} DZD", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: hasDebt ? Colors.red : Colors.green)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final lat = client['geo_lat'];
                          final lng = client['geo_lng'];
                          final uri = Uri.parse("google.navigation:q=$lat,$lng");
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          } else {
                            final webUri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng");
                            if (await canLaunchUrl(webUri)) {
                              await launchUrl(webUri, mode: LaunchMode.externalApplication);
                            }
                          }
                        },
                        icon: const Icon(Icons.navigation_rounded),
                        label: const Text("Naviguer"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => SalesPage(
                            onBack: () => Navigator.pop(context),
                            initialClientId: int.tryParse(client['id']?.toString() ?? ''),
                            initialClientName: client['name'],
                          )));
                        },
                        icon: const Icon(Icons.shopping_cart_rounded),
                        label: const Text("Vente"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(height: MediaQuery.of(context).padding.bottom), // 🛠️ MODULE 1 : Padding dynamique Android
              ],
            ),
          ),
        );
      },
    );
  }

  void _showVanDetails(dynamic van) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => VanDetailsSheet(van: van, mapController: _mapController),
    );
  }

  void _showDepotDetails(dynamic wh) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => WarehouseDetailsSheet(warehouse: wh, mapController: _mapController),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredVans = _statusFilter == 'all' ? _vans : _vans.where((v) => v['status'] == _statusFilter).toList();

    List<Marker> markers = [];
    List<Polyline> polylines = [];

    // Marqueurs Dépôts
    for (var wh in _warehouses) {
      if (wh['latitude'] != null && wh['longitude'] != null) {
        markers.add(
          Marker(
            point: LatLng(double.parse(wh['latitude'].toString()), double.parse(wh['longitude'].toString())),
            width: 80, height: 60,
            child: GestureDetector(
              onTap: () => _showDepotDetails(wh),
              child: Column(
                children: [
                  Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.purple, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)]), child: Icon(wh['type'] == 'warehouse' ? FontAwesomeIcons.industry : FontAwesomeIcons.store, color: Colors.white, size: 14)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.purple)), child: Text(wh['name']?.toString() ?? '', style: const TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        );
      }
    }

    // Marqueurs Fourgons & Tracés
    for (var van in filteredVans) {
      if (van['geo_lat'] != null && van['geo_lng'] != null) {
        markers.add(
          Marker(
            point: LatLng(double.parse(van['geo_lat'].toString()), double.parse(van['geo_lng'].toString())),
            width: 100, height: 70,
            child: GestureDetector(
              onTap: () => _showVanDetails(van),
              child: Column(
                children: [
                  Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.orange, Colors.amber]), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6)]), padding: const EdgeInsets.all(6), child: const Icon(FontAwesomeIcons.truckFast, color: Colors.white, size: 16)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange)), child: Text(van['van_name']?.toString() ?? '', style: const TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        );
      }

      // TRACÉ DE L'HISTORIQUE (Breadcrumbs) ou OSRM
      final vanId = van['van_id'] ?? van['id'] ?? 0;
      if (_osrmRoutes.containsKey(vanId) && _osrmRoutes[vanId]!.isNotEmpty) {
          polylines.add(
            Polyline(
              points: _osrmRoutes[vanId]!,
              strokeWidth: 5.0,
              color: Colors.orange.withOpacity(0.9),
            ),
          );
      } else if (van['route_history'] != null) {
        List<dynamic> history = van['route_history'];
        if (history.isNotEmpty) {
          List<LatLng> points = history
              .where((p) => p['geo_lat'] != null && p['geo_lng'] != null)
              .map((p) => LatLng(double.parse(p['geo_lat'].toString()), double.parse(p['geo_lng'].toString())))
              .toList();
          
          if (van['geo_lat'] != null) {
             points.add(LatLng(double.parse(van['geo_lat'].toString()), double.parse(van['geo_lng'].toString())));
          }

          if (points.isNotEmpty) {
            polylines.add(
              Polyline(
                points: points,
                strokeWidth: 4.0,
                color: Colors.orange.withOpacity(0.8),
              ),
            );
          }
        }
      }
    }

    // Marqueurs Clients
    if (_showClients) {
      for (var client in _clients) {
        final lat = double.tryParse(client['geo_lat'].toString()) ?? 0.0;
        final lng = double.tryParse(client['geo_lng'].toString()) ?? 0.0;
        double balance = double.tryParse(client['balance']?.toString() ?? '0') ?? 0.0;
        bool hasDebt = balance > 0;

        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 40, height: 40,
            child: GestureDetector(
              onTap: () => _showClientDetails(client),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasDebt ? Colors.red : Colors.blue,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ),
          ),
        );
      }
    }

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Live Tracking", style: TextStyle(fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        actions: [
          IconButton(icon: Icon(Icons.refresh, color: isDark ? Colors.white : Colors.black87), onPressed: () => _loadMapData(silent: false)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: LatLng(36.7525, 3.04197),
                    initialZoom: 10.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _getDynamicTileUrl(),
                      subdomains: _mapLayers[_currentLayerIndex]['subdomains'],
                      userAgentPackageName: 'com.infinitypos.mobile',
                    ),
                    PolylineLayer(polylines: polylines),
                    MarkerLayer(markers: markers),
                  ],
                ),
                
                // 🟢 FILTRE EN HAUT
                Positioned(
                  top: MediaQuery.of(context).padding.top + 56, left: 20, right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black87 : Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterBtn('Tous', 'all', isDark),
                          _buildFilterBtn('En Route', 'in_route', isDark),
                          _buildFilterBtn('Au Dépôt', 'loading', isDark),
                          _buildFilterBtn('En Attente', 'pending', isDark),
                          const SizedBox(width: 12),
                          Container(width: 1, height: 20, color: Colors.grey.withOpacity(0.5)),
                          const SizedBox(width: 12),
                          FilterChip(
                            label: const Text('Clients', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            selected: _showClients,
                            onSelected: (val) => setState(() => _showClients = val),
                            backgroundColor: Colors.transparent,
                            selectedColor: AppColors.primary.withOpacity(0.2),
                            checkmarkColor: AppColors.primary,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 🟢 LE SUPER DOCK (Contrôles Map)
                Positioned(
                  bottom: 120 + MediaQuery.of(context).padding.bottom, left: 0, right: 0, // 🛠️ MODULE 1 : Remonté au-dessus de la barre système Android
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: isDark ? Colors.white24 : Colors.white),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: _openLayerSelector,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
                                  child: Row(children: [const Icon(Icons.layers, size: 16), const SizedBox(width: 4), Text(_mapLayers[_currentLayerIndex]['short'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  setState(() => _isHD = !_isHD);
                                  _savePreferences();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: _isHD ? AppColors.primary.withOpacity(0.2) : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)), borderRadius: BorderRadius.circular(20)),
                                  child: Text(_isHD ? '📺 HD' : '📺 SD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _isHD ? AppColors.primary : null)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(width: 1, height: 20, color: Colors.grey.withOpacity(0.5)),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: _recenterMap,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(20)),
                                  child: const Row(children: [Icon(Icons.my_location, size: 16, color: Colors.white), SizedBox(width: 4), Text('Centrer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white))]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 🟢 DOCK HORIZONTAL (Fourgons & Dépôts)
                Positioned(
                  bottom: 20 + MediaQuery.of(context).padding.bottom, left: 0, right: 0, // 🛠️ MODULE 1 : Padding dynamique Android
                  child: SafeArea(
                    child: SizedBox(
                      height: 85,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredVans.length + _warehouses.length,
                        itemBuilder: (context, index) {
                          if (index < filteredVans.length) {
                            return _buildDockVanItem(filteredVans[index], isDark);
                          } else {
                            return _buildDockWarehouseItem(_warehouses[index - filteredVans.length], isDark);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDockVanItem(dynamic van, bool isDark) {
    final isPending = van['status'] == 'pending';
    final vanColor = isPending ? const Color(0xFF64748B) : Colors.orange;

    return GestureDetector(
      onTap: () {
        if (van['geo_lat'] != null) {
          _mapController.move(LatLng(double.parse(van['geo_lat'].toString()), double.parse(van['geo_lng'].toString())), 16.0);
        }
        _showVanDetails(van);
      },
      child: Container(
        width: isPending ? 185 : 160, // Plus large si pending pour afficher le bouton
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: isPending ? Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.6), width: 1.5) : null,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? (isPending ? Colors.blue.withOpacity(0.08) : Colors.white.withOpacity(0.1))
                    : (isPending ? Colors.blue.withOpacity(0.04) : Colors.white.withOpacity(0.6)),
                border: Border.all(color: isDark ? Colors.white24 : Colors.white.withOpacity(0.8), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: vanColor, shape: BoxShape.circle),
                    child: Icon(
                      isPending ? FontAwesomeIcons.clock : FontAwesomeIcons.truckFast,
                      color: Colors.white, size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          van['van_name'] ?? 'Fourgon',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        if (isPending)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                            child: const Text('⏳ En Attente', style: TextStyle(fontSize: 9, color: Color(0xFF0EA5E9), fontWeight: FontWeight.w700)),
                          )
                        else
                          Text(_fmtMoney(van['today_ca']), style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  // 🟢 FIX CHANTIER 4 : Bouton ▶ démarrer si pending
                  if (isPending)
                    GestureDetector(
                      onTap: () async {
                        final tourId = van['tour_id'] ?? van['id'];
                        if (tourId == null) return;
                        final res = await _api.startPendingTour(tourId is int ? tourId : int.tryParse(tourId.toString()) ?? 0);
                        if (mounted) {
                          if (res['success'] == true) {
                            _loadMapData(silent: false);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('✅ Tournée démarrée !'),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                            ));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('❌ ${res['message']}'),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ));
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(FontAwesomeIcons.play, color: Colors.white, size: 10),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockWarehouseItem(dynamic wh, bool isDark) {
    return GestureDetector(
      onTap: () {
        if (wh['latitude'] != null) {
          _mapController.move(LatLng(double.parse(wh['latitude'].toString()), double.parse(wh['longitude'].toString())), 16.0);
        }
        _showDepotDetails(wh);
      },
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.6),
                border: Border.all(color: isDark ? Colors.white24 : Colors.white.withOpacity(0.8), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Colors.purple, shape: BoxShape.circle),
                    child: Icon(wh['type'] == 'warehouse' ? FontAwesomeIcons.industry : FontAwesomeIcons.store, color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(wh['name'] ?? 'Dépôt', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: isDark ? Colors.white : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(wh['type'] == 'warehouse' ? 'Principal' : 'Point Vente', style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBtn(String label, String value, bool isDark) {
    bool isActive = _statusFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _statusFilter = value);
        _recenterMap();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? Colors.white : (isDark ? Colors.white54 : Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}

String _fmtMoney(dynamic val) {
  if (val == null) return "0.00 DZD";
  double v = double.tryParse(val.toString()) ?? 0;
  return "${NumberFormat('#,##0.00', 'fr_FR').format(v)} DZD";
}

// ==========================================
// 🏢 MODALE DÉTAILS DÉPÔT (FROSTED GLASS)
// ==========================================
class WarehouseDetailsSheet extends StatefulWidget {
  final dynamic warehouse;
  final MapController mapController;
  const WarehouseDetailsSheet({super.key, required this.warehouse, required this.mapController});

  @override
  State<WarehouseDetailsSheet> createState() => _WarehouseDetailsSheetState();
}

class _WarehouseDetailsSheetState extends State<WarehouseDetailsSheet> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _details;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final data = await _api.getWarehouseDetails(widget.warehouse['id']);
    if (mounted) {
      setState(() {
        _details = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stockItems = _details?['stock_items'] as List<dynamic>? ?? [];
    final filteredStock = stockItems.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final ref = (item['base_reference'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || ref.contains(q);
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24).withOpacity(0.95) : Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(widget.warehouse['type'] == 'warehouse' ? FontAwesomeIcons.industry : FontAwesomeIcons.store, color: Colors.purple, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.warehouse['name'] ?? 'Dépôt', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                            Text(widget.warehouse['type'] == 'warehouse' ? 'Dépôt Principal' : 'Point de Vente', style: TextStyle(fontSize: 14, color: isDark ? Colors.white54 : Colors.black54)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                          if (widget.warehouse['latitude'] != null) {
                            widget.mapController.move(LatLng(double.parse(widget.warehouse['latitude'].toString()), double.parse(widget.warehouse['longitude'].toString())), 16.0);
                          }
                        },
                        icon: const Icon(Icons.my_location, color: Colors.purple),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isLoading)
                    const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.purple))
                  else ...[
                    Row(
                      children: [
                        Expanded(child: GlassCard(isDark: isDark, padding: const EdgeInsets.all(16), child: Column(children: [const Icon(FontAwesomeIcons.boxesStacked, color: Colors.purple, size: 24), const SizedBox(height: 8), const Text("Quantité Totale", style: TextStyle(fontSize: 12, color: Colors.grey)), FittedBox(child: Text("${_details?['total_qty'] ?? 0} Unités", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))],))),
                        const SizedBox(width: 12),
                        Expanded(child: GlassCard(isDark: isDark, padding: const EdgeInsets.all(16), child: Column(children: [const Icon(FontAwesomeIcons.moneyBillTrendUp, color: AppColors.success, size: 24), const SizedBox(height: 8), const Text("Valeur Estimée", style: TextStyle(fontSize: 12, color: Colors.grey)), FittedBox(child: Text(_fmtMoney(_details?['total_value']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))],))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        hintText: "Rechercher un article...",
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 250,
                      child: filteredStock.isEmpty
                          ? const Center(child: Text("Aucun article trouvé", style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              itemCount: filteredStock.length,
                              itemBuilder: (ctx, i) {
                                final item = filteredStock[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200)),
                                  child: ListTile(
                                    title: Text(item['name'] ?? 'Article', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text(item['base_reference'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text("${item['stock']}", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.purple, fontSize: 14)),
                                        const Text("unités", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                    dense: true,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 🚐 MODALE DÉTAILS FOURGON (FROSTED GLASS)
// ==========================================
class VanDetailsSheet extends StatelessWidget {
  final dynamic van;
  final MapController mapController;
  const VanDetailsSheet({super.key, required this.van, required this.mapController});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stockItems = van['stock_items'] as List<dynamic>? ?? [];
    final salesDetails = van['sales_details'] as List<dynamic>? ?? [];
    final routeHistory = van['route_history'] as List<dynamic>? ?? [];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24).withOpacity(0.95) : Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: SafeArea(
              child: DefaultTabController(
                length: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
                          child: const Icon(FontAwesomeIcons.truckFast, color: Colors.orange, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(van['van_name'] ?? 'Fourgon', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                              Text(van['driver_name'] ?? 'Chauffeur inconnu', style: TextStyle(fontSize: 14, color: isDark ? Colors.white54 : Colors.black54)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.pop(context);
                            if (van['geo_lat'] != null) {
                              mapController.move(LatLng(double.parse(van['geo_lat'].toString()), double.parse(van['geo_lng'].toString())), 16.0);
                            }
                          },
                          icon: const Icon(Icons.my_location, color: Colors.orange),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TabBar(
                      labelColor: Colors.orange,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.orange,
                      isScrollable: true,
                      tabs: [
                        const Tab(text: "Résumé"),
                        Tab(text: "Stock (${stockItems.length})"),
                        Tab(text: "Ventes (${salesDetails.length})"),
                        Tab(text: "Trajets (${routeHistory.length})"),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 280,
                      child: TabBarView(
                        children: [
                          // 1. Résumé
                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: GlassCard(isDark: isDark, padding: const EdgeInsets.all(16), child: Column(children: [const Icon(FontAwesomeIcons.moneyBillTrendUp, color: AppColors.success, size: 24), const SizedBox(height: 8), const Text("CA du Jour", style: TextStyle(fontSize: 12, color: Colors.grey)), FittedBox(child: Text(_fmtMoney(van['today_ca']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))],))),
                                  const SizedBox(width: 12),
                                  Expanded(child: GlassCard(isDark: isDark, padding: const EdgeInsets.all(16), child: Column(children: [const Icon(FontAwesomeIcons.boxOpen, color: Colors.orange, size: 24), const SizedBox(height: 8), const Text("Stock à Bord", style: TextStyle(fontSize: 12, color: Colors.grey)), FittedBox(child: Text("${van['stock_qty'] ?? 0} articles", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))],))),
                                ],
                              ),
                            ],
                          ),
                          // 2. Stock
                          stockItems.isEmpty
                              ? const Center(child: Text("Aucun stock", style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  itemCount: stockItems.length,
                                  itemBuilder: (c, i) {
                                    final item = stockItems[i];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200)),
                                      child: ListTile(
                                        title: Text(item['name'] ?? 'Article', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        subtitle: Text(item['base_reference'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        trailing: Text("${item['stock']} unités", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.orange, fontSize: 14)),
                                        dense: true,
                                      ),
                                    );
                                  },
                                ),
                          // 3. Ventes
                          salesDetails.isEmpty
                              ? const Center(child: Text("Aucune vente", style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  itemCount: salesDetails.length,
                                  itemBuilder: (c, i) {
                                    final sale = salesDetails[i];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200)),
                                      child: ListTile(
                                        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.receipt_long, color: AppColors.success, size: 16)),
                                        title: Text(sale['client_name'] ?? 'Client Anonyme', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        subtitle: Text(sale['reference'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        trailing: Text(_fmtMoney(sale['total_amount']), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success, fontSize: 14)),
                                        dense: true,
                                      ),
                                    );
                                  },
                                ),
                          // 4. Trajets (Historique)
                          routeHistory.isEmpty
                              ? const Center(child: Text("Aucun historique", style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  itemCount: routeHistory.length,
                                  itemBuilder: (c, i) {
                                    final rh = routeHistory[i];
                                    return ListTile(
                                      leading: const Icon(Icons.timeline, color: Colors.orange),
                                      title: Text("Point GPS #${i + 1}", style: const TextStyle(fontSize: 13)),
                                      subtitle: Text("${rh['recorded_at']}", style: const TextStyle(fontSize: 11)),
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}