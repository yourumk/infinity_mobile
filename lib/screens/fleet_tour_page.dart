import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';


import '../core/constants.dart';
import '../services/api_service.dart';
import '../services/gps_service.dart';
import '../widgets/glass_card.dart';
import 'transfer_reception_page.dart'; 

class FleetTourPage extends StatefulWidget {
  final VoidCallback? onBack;
  const FleetTourPage({super.key, this.onBack});

  @override
  State<FleetTourPage> createState() => _FleetTourPageState();
}

class _FleetTourPageState extends State<FleetTourPage> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final GpsTrackingService _gps = GpsTrackingService();
  final MapController _mapController = MapController();

  Map<String, dynamic> _tour = {};
  List<dynamic> _recentSales = [];
  List<Map<String, dynamic>> _allTours = [];
  bool _isLoading = true;
  bool _isSyncingGps = false;
  bool _isAdmin = false;
  int? _selectedTourIndex; // null = vue liste admin, int = drill-down dans une tournée
  String? _error;
  String _stockSearch = '';
  Position? _lastKnownPosition;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 2)
    )..repeat(reverse: true);
    _loadTour();
    _fetchCurrentLocationForMap();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocationForMap() async {
    final pos = await _gps.getCurrentPosition();
    if (mounted && pos != null) {
      setState(() => _lastKnownPosition = pos);
    }
  }

  Future<void> _loadTour() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final role = await _api.getUserRole();
      _isAdmin = role == 'admin';

      if (_isAdmin) {
        // ADMIN : Charger toutes les tournées actives
        final tours = await _api.getAllActiveTours();
        if (mounted) {
          setState(() {
            _allTours = tours;
            _isLoading = false;
          });
        }
      } else {
        // CHAUFFEUR/VENDEUR : Charger uniquement sa propre tournée
        final results = await Future.wait([
          _api.getActiveTour(),
          _api.fetchDashboardData(),
        ]);
        final tour = results[0] as Map<String, dynamic>;
        final dashData = results[1] as Map<String, dynamic>;
        
        List<dynamic> sales = [];
        if (dashData['tables'] is Map) {
          sales = (dashData['tables']['finance'] as List<dynamic>?) ?? [];
        }

        if (mounted) {
          setState(() {
            _tour = tour;
            _recentSales = sales;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; _error = e.toString(); });
      }
    }
  }

  Future<void> _forceGpsSync() async {
    setState(() => _isSyncingGps = true);
    try {
      final pos = await _gps.getCurrentPosition();
      if (pos != null) {
        final ok = await _api.sendGpsPositionDirect(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() => _lastKnownPosition = pos);
          _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0); // Recentre la carte
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ok ? '✅ Position envoyée (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})' : '❌ Échec de l\'envoi GPS'),
            backgroundColor: ok ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ Impossible d\'obtenir la position GPS.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erreur GPS: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    if (mounted) setState(() => _isSyncingGps = false);
  }

  List<dynamic> get pendingTransfers => _tour['pending_transfers'] as List<dynamic>? ?? [];
  List<dynamic> get stockItems => _tour['stock_items'] as List<dynamic>? ?? [];
  double get stockValue => double.tryParse(_tour['stock_value']?.toString() ?? '0') ?? 0;
  double get computedCA => _recentSales.fold(0.0, (sum, s) => sum + (double.tryParse(s['total_amount']?.toString() ?? '0') ?? 0.0));

  String _fmtMoney(dynamic val) {
    final n = double.tryParse(val?.toString() ?? '0') ?? 0;
    return NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2).format(n);
  }

  String _fmtDate(dynamic dateStr) {
    if (dateStr == null) return '---';
    try {
      final d = DateTime.parse(dateStr.toString());
      return DateFormat('dd/MM/yyyy à HH:mm', 'fr').format(d);
    } catch (_) {
      return dateStr.toString().split('T').first;
    }
  }

  void _openTransferReception(dynamic transfer) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => TransferReceptionPage(transferId: transfer['id'])));
    if (result == true) {
      _loadTour(); // Refresh after reception
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : _error != null
                      ? _buildErrorState(isDark)
                      // 🛡️ MODE ADMIN vs CHAUFFEUR
                      : _isAdmin
                          ? (_selectedTourIndex != null
                              ? _buildDriverTourView(isDark) // Drill-down dans une tournée admin
                              : _buildAdminToursList(isDark) // Liste de toutes les tournées
                            )
                          : _tour.isEmpty
                              ? _buildEmptyState(isDark)
                              : _buildDriverTourView(isDark),
            ),
          ],
        ),
      ),
    );
  }

  // 🛡️ ADMIN : Liste de toutes les tournées actives
  Widget _buildAdminToursList(bool isDark) {
    if (_allTours.isEmpty) return _buildEmptyState(isDark);

    return RefreshIndicator(
      onRefresh: _loadTour,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(20),
        itemCount: _allTours.length + 1, // +1 pour le header
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(FontAwesomeIcons.truckFast, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Tournées Actives", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                      Text("${_allTours.length} tournée(s) en cours", style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                    ],
                  ),
                ],
              ),
            );
          }

          final tour = _allTours[i - 1];
          final vanName = tour['van_name'] ?? 'Fourgon';
          final driverName = tour['driver_name'] ?? 'Inconnu';
          final status = tour['status'] ?? '';
          final ca = double.tryParse(tour['total_sales']?.toString() ?? '0') ?? 0;
          final isInRoute = status == 'in_route';
          final isLoading = status == 'loading';

          Color statusColor = isInRoute ? const Color(0xFF10B981) : isLoading ? Colors.orange : Colors.grey;
          String statusText = isInRoute ? 'En Route' : isLoading ? 'Chargement' : status;
          final stockQty = tour['stock_qty'] ?? 0;
          final todayCA = double.tryParse(tour['today_ca']?.toString() ?? '0') ?? ca;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () {
                // 🟢 ADMIN DRILL-DOWN : Exploiter les données enrichies de map-data
                final enrichedTour = Map<String, dynamic>.from(tour);
                // Mapper les clés enrichies vers les clés attendues par _buildDriverTourView
                enrichedTour['stock_items'] = tour['stock_items'] ?? [];
                enrichedTour['stock_value'] = tour['stock_value'] ?? tour['stock_value'] ?? 0;
                enrichedTour['product_count'] = tour['product_count'] ?? (tour['stock_items'] as List?)?.length ?? 0;
                enrichedTour['total_qty'] = tour['total_qty'] ?? tour['stock_qty'] ?? 0;
                enrichedTour['pending_transfers'] = tour['pending_transfers'] ?? [];
                enrichedTour['route_history'] = tour['route_history'] ?? [];
                enrichedTour['tour_id'] = tour['tour_id'] ?? tour['id'];

                // Extraire les ventes détaillées
                final salesDetails = (tour['sales_details'] as List<dynamic>?) ?? [];

                setState(() {
                  _tour = enrichedTour;
                  _recentSales = salesDetails.map((s) {
                    return {
                      'id': s['id'],
                      'invoice_number': s['reference'] ?? s['invoice_number'],
                      'total_amount': s['total_amount'],
                      'client_name': s['client_name'] ?? 'Comptoir',
                      'time': _fmtDate(s['date']),
                    };
                  }).toList();
                  _selectedTourIndex = i - 1;
                });
              },
              child: GlassCard(
                isDark: isDark,
                borderRadius: 20,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Icône fourgon avec pulse de statut
                    Container(
                      width: 55, height: 55,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isInRoute 
                            ? [const Color(0xFF10B981), const Color(0xFF059669)]
                            : [Colors.orange, Colors.deepOrange],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: statusColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: const Center(child: Icon(FontAwesomeIcons.truckFront, color: Colors.white, size: 22)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vanName, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.person, size: 13, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Expanded(child: Text(driverName, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor)),
                              ),
                              if (tour['geo_lat'] != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.gps_fixed, size: 10, color: Colors.blue),
                                      SizedBox(width: 3),
                                      Text('GPS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.blue)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // CA + détails stock
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_fmtMoney(todayCA), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                        Text('CA Jour', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text('$stockQty pcs', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.purple)),
                        ),
                        const SizedBox(height: 4),
                        Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Vue détaillée d'une tournée (chauffeur ou drill-down admin)
  Widget _buildDriverTourView(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadTour,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            // 🛡️ Bouton retour admin
            if (_isAdmin && _selectedTourIndex != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: GestureDetector(
                  onTap: () => setState(() { _selectedTourIndex = null; }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_back_ios_new, size: 14, color: isDark ? Colors.white54 : Colors.black54),
                        const SizedBox(width: 8),
                        Text('Retour à la liste', style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white54 : Colors.black54)),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _buildMapSection(isDark),
            const SizedBox(height: 16),
            _buildVanCard(isDark),
            const SizedBox(height: 16),
            if (_tour['status'] == 'pending') ...[
              _buildStartPendingButton(isDark),
              const SizedBox(height: 16),
            ],
            _buildKpiRow(isDark),
            const SizedBox(height: 16),
            _buildSalesJournal(isDark),
            const SizedBox(height: 16),
            _buildPendingTransfers(isDark),
            const SizedBox(height: 16),
            _buildStockSection(isDark),
            const SizedBox(height: 16),
            _buildGpsSection(isDark),
            const SizedBox(height: 24),
            if (_tour['status'] != 'pending')
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => _showCloseTourDialog(),
                  icon: const Icon(FontAwesomeIcons.flagCheckered),
                  label: const Text('Clôturer la Tournée', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            SizedBox(height: 120 + MediaQuery.of(context).padding.bottom), // 🛠️ MODULE 1 : Padding dynamique Android
          ],
        ),
      ),
    );
  }

 Widget _buildMapSection(bool isDark) {
    List<LatLng> points = [];
    
    // Extraction de l'historique du trajet depuis la DB
    final routeHistory = _tour['route_history'] as List<dynamic>? ?? [];
    if (routeHistory.isNotEmpty) {
      points = routeHistory
          .where((p) => p['geo_lat'] != null && p['geo_lng'] != null)
          .map((p) => LatLng(double.parse(p['geo_lat'].toString()), double.parse(p['geo_lng'].toString())))
          .toList();
    }

    // Marqueurs
    List<Marker> mapMarkers = [];

    // Ajout de la position actuelle la plus récente
    if (_lastKnownPosition != null) {
      final pos = LatLng(_lastKnownPosition!.latitude, _lastKnownPosition!.longitude);
      points.add(pos);
      mapMarkers.add(Marker(
        point: pos,
        width: 40, height: 40,
        child: Container(decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)]), child: const Icon(FontAwesomeIcons.truck, color: Colors.white, size: 14)),
      ));
    }

    for (var t in pendingTransfers) {
      if (t['to_lat'] != null && t['to_lng'] != null) {
        final lat = double.tryParse(t['to_lat'].toString());
        final lng = double.tryParse(t['to_lng'].toString());
        if (lat != null && lng != null) {
          final pt = LatLng(lat, lng);
          mapMarkers.add(Marker(
            point: pt,
            width: 80, height: 60,
            child: Column(
              children: [
                Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.purple, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)]), child: const Icon(FontAwesomeIcons.building, color: Colors.white, size: 14)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.purple)), child: Text(t['to_warehouse_name']?.toString() ?? 'Dest.', style: const TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ));
        }
      }
    }

    // Calcul du centre de la carte
    LatLng centerMap = const LatLng(36.7538, 3.0588); // Alger par defaut
    if (points.isNotEmpty || mapMarkers.isNotEmpty) {
      if (points.isNotEmpty) {
        centerMap = points.last;
      } else {
        centerMap = mapMarkers.first.point;
      }
      
      // Auto-centrage fluide une fois que le widget est dessiné
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          List<LatLng> allBoundsPts = List.from(points);
          for (var m in mapMarkers) { allBoundsPts.add(m.point); }
          if (allBoundsPts.length > 1) {
            final bounds = LatLngBounds.fromPoints(allBoundsPts);
            _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(30)));
          } else if (allBoundsPts.isNotEmpty) {
            _mapController.move(allBoundsPts.first, 15.0);
          }
        } catch(e) {}
      });
    }

    return GlassCard(
      isDark: isDark,
      borderRadius: 20,
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(FontAwesomeIcons.mapLocationDot, color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Text('Mon Itinéraire', style: TextStyle(fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
                const Spacer(),
                Text('${points.length} points GPS', style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          SizedBox(
            height: 450, // 🟢 CARTE AGRANDIE SELON LA DEMANDE
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: centerMap,
                  initialZoom: 14.0,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'http://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', // 🟢 STYLE GOOGLE MAPS COMME LIVE TRACKING
                    subdomains: const ['0', '1', '2', '3'],
                    userAgentPackageName: 'com.infinitypos.mobile',
                  ),
                  if (points.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(points: points, strokeWidth: 5.0, color: Colors.orange.withValues(alpha: 0.8)),
                      ],
                    ),
                  if (mapMarkers.isNotEmpty)
                    MarkerLayer(markers: mapMarkers),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepOrange.shade700, Colors.deepOrange.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.deepOrange.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => widget.onBack != null ? widget.onBack!() : Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("MA TOURNÉE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 2)),
                SizedBox(height: 2),
                FittedBox(child: Text("Flotte & Logistique", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white))),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _gps.isTracking
                      ? Colors.green.withValues(alpha: 0.15 + _pulseController.value * 0.2)
                      : Colors.red.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: _gps.isTracking ? Colors.green : Colors.red, width: 2),
                ),
                child: Icon(
                  _gps.isTracking ? FontAwesomeIcons.satelliteDish : FontAwesomeIcons.locationCrosshairs,
                  color: _gps.isTracking ? Colors.green : Colors.red,
                  size: 16,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVanCard(bool isDark) {
    final status = _tour['status']?.toString() ?? 'unknown';
    final isInRoute = status == 'in_route';
    final isPending = status == 'pending';
    final statusColor = isInRoute ? AppColors.success : (isPending ? const Color(0xFF64748B) : Colors.orange);
    final statusLabel = isPending ? '⏳ En Attente' : (isInRoute ? '🚛 En Route' : '📦 Chargement');

    return GlassCard(
      isDark: isDark,
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
      borderColor: statusColor.withValues(alpha: 0.4),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: isPending ? [Colors.blueGrey.shade500, Colors.blueGrey.shade300] : [Colors.deepOrange.shade600, Colors.deepOrange.shade300]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(isPending ? FontAwesomeIcons.clock : FontAwesomeIcons.truckFast, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_tour['van_name'] ?? 'Fourgon Inconnu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                    if (_tour['van_description'] != null && _tour['van_description'].toString().isNotEmpty)
                      Text(_tour['van_description'], style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Text('Départ : ${_fmtDate(_tour['date_departure'])}', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ⏳ CHANTIER 4 : Gros bouton bleu pour démarrer une tournée en attente
  Widget _buildStartPendingButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : () async {
          setState(() => _isLoading = true);
          final tourId = _tour['tour_id'];
          if (tourId == null) {
            setState(() => _isLoading = false);
            return;
          }
          final res = await _api.startPendingTour(tourId is int ? tourId : int.tryParse(tourId.toString()) ?? 0);
          if (mounted) {
            if (res['success'] == true) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✅ Tournée démarrée avec succès !'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
              ));
              _loadTour();
            } else {
              setState(() => _isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('❌ Erreur: ${res['message']}'),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ));
            }
          }
        },
        icon: const Icon(FontAwesomeIcons.play, size: 18),
        label: const Text('▶ Démarrer la Tournée', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0EA5E9),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          shadowColor: const Color(0xFF0EA5E9).withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildKpiRow(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: GestureDetector(
              onTap: () => _showStockDetailModal(isDark),
              child: _buildKpiCard(isDark, FontAwesomeIcons.boxesStacked, 'Valeur Stock', _fmtMoney(stockValue), Colors.purple),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () => _showSalesListModal(isDark),
              child: _buildKpiCard(isDark, FontAwesomeIcons.cashRegister, 'CA Ventes', _fmtMoney(computedCA > 0 ? computedCA : _tour['total_sales']), AppColors.success),
            )),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: GestureDetector(
              onTap: () => _showStockDetailModal(isDark),
              child: _buildKpiCard(isDark, FontAwesomeIcons.cubes, 'Produits', '${_tour['product_count'] ?? stockItems.length}', const Color(0xFF3B82F6)),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () => _showSalesListModal(isDark),
              child: _buildKpiCard(isDark, FontAwesomeIcons.receipt, 'Nb Ventes', '${_recentSales.length}', const Color(0xFFF97316)),
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard(bool isDark, IconData icon, String label, String value, Color color) {
    return GlassCard(
      isDark: isDark,
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          FittedBox(child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black))),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildPendingTransfers(bool isDark) {
    if (pendingTransfers.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      isDark: isDark,
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FontAwesomeIcons.truckRampBox, color: isDark ? Colors.white70 : AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('Livraisons en cours', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                child: Text('${pendingTransfers.length}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...pendingTransfers.map((t) => _buildTransferItem(t, isDark)),
        ],
      ),
    );
  }

  Widget _buildTransferItem(dynamic t, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(FontAwesomeIcons.boxOpen, color: Colors.orange, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['reference'] ?? 'Transfert', style: TextStyle(fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black, fontSize: 14)),
                const SizedBox(height: 2),
                Text('${t['from_name']} ➔ ${t['to_name']}', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontSize: 11)),
                const SizedBox(height: 2),
                Text('${t['items_count']} article(s)', style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _openTransferReception(t),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Recevoir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // 🛠️ NOUVEAU : Journal des ventes de la tournée
  Widget _buildSalesJournal(bool isDark) {
    return GlassCard(
      isDark: isDark,
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(FontAwesomeIcons.receipt, color: AppColors.success, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('Journal des Ventes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text('${_recentSales.length}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showSalesListModal(isDark),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Voir tout', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.success)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_recentSales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('Aucune vente réalisée pour le moment.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))),
            )
          else
            ..._recentSales.take(20).map((s) => GestureDetector(
              onTap: () => _showSaleDetailModal(s, isDark),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: const Icon(FontAwesomeIcons.cartShopping, size: 14, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ticket #${s['invoice_number'] ?? s['id']}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${s['time'] ?? ''} • ${s['client_name'] ?? 'Comptoir'}', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Text(_fmtMoney(s['total_amount']), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success, fontSize: 14)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 18, color: isDark ? Colors.white24 : Colors.grey.shade400),
                  ],
                ),
              ),
            )),
          if (_recentSales.length > 20)
            Center(child: Text('+ ${_recentSales.length - 20} ventes supplémentaires...', style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic))),
        ],
      ),
    );
  }

  // 🛠️ NOUVEAU : Modale détail vente
  void _showSaleDetailModal(dynamic sale, bool isDark) {
    final saleId = sale['id'];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(FontAwesomeIcons.receipt, color: AppColors.success, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vente #${sale['invoice_number'] ?? sale['id']}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                      Text('${sale['time'] ?? ''} • ${sale['client_name'] ?? 'Client Comptoir'}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                Text(_fmtMoney(sale['total_amount']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.success)),
              ],
            ),
            const Divider(height: 30),
            Expanded(
              child: saleId != null
                ? FutureBuilder<List<dynamic>>(
                    future: _api.getSaleItems(saleId),
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (!snap.hasData || snap.data!.isEmpty) return const Center(child: Text('Aucun article trouvé.'));
                      return ListView.separated(
                        itemCount: snap.data!.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = snap.data![i];
                          final name = item['name'] ?? item['product_real_name'] ?? 'Article';
                          final qty = double.tryParse(item['quantity']?.toString() ?? item['qty']?.toString() ?? '0') ?? 0;
                          final price = double.tryParse(item['price']?.toString() ?? item['price_at_sale']?.toString() ?? '0') ?? 0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                              child: Text('${qty.toInt()}x', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
                            ),
                            title: Text(name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                            trailing: Text(_fmtMoney(qty * price), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                          );
                        },
                      );
                    },
                  )
                : const Center(child: Text('Détails non disponibles')),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Fermer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🟢 MODAL : Tableau détaillé du stock embarqué
  void _showStockDetailModal(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(FontAwesomeIcons.cubes, color: Colors.purple, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stock Embarqué', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                      Text('${stockItems.length} produit(s) • ${_tour['total_qty'] ?? 0} unité(s)', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                Text(_fmtMoney(stockValue), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.purple)),
              ],
            ),
            const SizedBox(height: 12),
            // Barre de recherche
            TextField(
              onChanged: (val) => (ctx as Element).markNeedsBuild(),
              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher un produit...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
            ),
            const Divider(height: 20),
            // En-tête du tableau
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(flex: 4, child: Text('Produit', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700))),
                  Expanded(flex: 2, child: Text('Réf.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text('Qté', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('Valeur', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700), textAlign: TextAlign.right)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: stockItems.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                itemBuilder: (_, i) {
                  final item = stockItems[i];
                  final name = item['name']?.toString() ?? 'Article';
                  final ref = item['base_reference']?.toString() ?? '---';
                  final qty = double.tryParse(item['stock']?.toString() ?? '0') ?? 0;
                  final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
                  final val = qty * price;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(flex: 4, child: Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 2, child: Text(ref, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                          child: Text('${qty.toInt()}', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 12), textAlign: TextAlign.center),
                        )),
                        Expanded(flex: 2, child: Text(_fmtMoney(val), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black), textAlign: TextAlign.right)),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            // Totaux
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Stock', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                  Text(_fmtMoney(stockValue), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.purple)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Fermer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🟢 MODAL : Tableau détaillé de toutes les ventes
  void _showSalesListModal(bool isDark) {
    final totalCA = _recentSales.fold(0.0, (sum, s) => sum + (double.tryParse(s['total_amount']?.toString() ?? '0') ?? 0.0));
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(FontAwesomeIcons.cashRegister, color: AppColors.success, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Journal des Ventes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                      Text('${_recentSales.length} vente(s) du jour', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                Text(_fmtMoney(totalCA), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.success)),
              ],
            ),
            const Divider(height: 20),
            // En-tête du tableau
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text('N° Ticket', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700))),
                  Expanded(flex: 3, child: Text('Client', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700))),
                  Expanded(flex: 2, child: Text('Heure', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text('Montant', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700), textAlign: TextAlign.right)),
                ],
              ),
            ),
            Expanded(
              child: _recentSales.isEmpty
                ? const Center(child: Text('Aucune vente enregistrée.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)))
                : ListView.separated(
                    itemCount: _recentSales.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                    itemBuilder: (_, i) {
                      final s = _recentSales[i];
                      final ref = s['invoice_number']?.toString() ?? '#${s['id']}';
                      final client = s['client_name']?.toString() ?? 'Comptoir';
                      final time = s['time']?.toString() ?? '';
                      final amount = s['total_amount'];
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _showSaleDetailModal(s, isDark);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text(ref, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Expanded(flex: 3, child: Text(client, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Expanded(flex: 2, child: Text(time, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center, maxLines: 1)),
                              Expanded(flex: 2, child: Text(_fmtMoney(amount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.success), textAlign: TextAlign.right)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
            const SizedBox(height: 10),
            // Total
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total CA', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                  Text(_fmtMoney(totalCA), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.success)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Fermer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockSection(bool isDark) {
    if (stockItems.isEmpty) return const SizedBox.shrink();

    // 🛠️ Filtre de recherche stock
    final filteredStock = _stockSearch.isEmpty 
        ? stockItems 
        : stockItems.where((item) {
            final name = item['name']?.toString().toLowerCase() ?? '';
            final ref = item['base_reference']?.toString().toLowerCase() ?? '';
            return name.contains(_stockSearch.toLowerCase()) || ref.contains(_stockSearch.toLowerCase());
          }).toList();

    return GlassCard(
      isDark: isDark,
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FontAwesomeIcons.cubes, color: isDark ? Colors.white70 : AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('Stock à bord', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black))),
              Text('${_tour['total_qty'] ?? 0} unités', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 13)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showStockDetailModal(isDark),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Voir tout', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Barre de recherche
          TextField(
            onChanged: (val) => setState(() => _stockSearch = val),
            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Rechercher un produit...',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          ...filteredStock.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name']?.toString() ?? 'Article',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade800, fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          if (item['base_reference'] != null)
                            Text(item['base_reference'].toString(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${item['stock']}x',
                        style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildGpsSection(bool isDark) {
    final isTracking = _gps.isTracking;
    final hasPosition = _lastKnownPosition != null;
    final statusColor = isTracking ? AppColors.success : Colors.orange;
    final statusText = isTracking 
        ? (hasPosition ? 'GPS actif — Envoi automatique ✅' : 'GPS actif — En attente de signal...')
        : 'GPS inactif — Appuyez pour activer';

    return GlassCard(
      isDark: isDark,
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) => Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isTracking
                        ? Colors.green.withValues(alpha: 0.1 + _pulseController.value * 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Icon(
                    isTracking ? FontAwesomeIcons.satelliteDish : FontAwesomeIcons.locationCrosshairs,
                    color: statusColor,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Suivi GPS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
                    const SizedBox(height: 2),
                    Text(statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                    if (hasPosition) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${_lastKnownPosition!.latitude.toStringAsFixed(4)}, ${_lastKnownPosition!.longitude.toStringAsFixed(4)}',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isDark ? Colors.white38 : Colors.grey, fontFamily: 'monospace'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (!isTracking)
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: () { _gps.startTracking(); setState(() {}); },
                      icon: const Icon(FontAwesomeIcons.play, size: 12),
                      label: const Text('Activer le GPS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              if (isTracking) ...[
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _isSyncingGps ? null : _forceGpsSync,
                      icon: _isSyncingGps
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(FontAwesomeIcons.locationCrosshairs, size: 12),
                      label: Text(_isSyncingGps ? 'Envoi...' : 'Ping Manuel', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepOrange,
                        side: const BorderSide(color: Colors.deepOrange),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(FontAwesomeIcons.truckRampBox, color: Colors.deepOrange, size: 48),
            const SizedBox(height: 20),
            Text('Aucune tournée active', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _showStartTourDialog,
              icon: const Icon(FontAwesomeIcons.play),
              label: const Text('Démarrer une Tournée', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStartTourDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final res = await _api.getLogisticsResources();
    if (!mounted) return;
    Navigator.pop(context); // Close loading

    if (res['vans'] == null || res['vans'].isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun fourgon disponible')));
      return;
    }

    int? selectedVanId;
    final kmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Démarrer une Tournée'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Choisir un fourgon'),
                items: (res['vans'] as List).map((v) => DropdownMenuItem<int>(
                  value: v['id'],
                  child: Text(v['name']),
                )).toList(),
                onChanged: (v) => setDialogState(() => selectedVanId = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: kmCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Kilométrage de départ (Optionnel)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: selectedVanId == null ? null : () async {
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                final startKm = double.tryParse(kmCtrl.text) ?? 0;
                final startRes = await _api.startTour(selectedVanId!, startKm);
                if (startRes['success'] == true) {
                  _gps.startTracking();
                  _loadTour();
                } else {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: ${startRes['message']}')));
                }
              },
              child: const Text('Démarrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCloseTourDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Action Restreinte', style: TextStyle(color: AppColors.error)),
        content: const Text('La clôture de la tournée se fait uniquement sur la caisse principale.', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Compris')),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(child: Text('Erreur: $_error', style: const TextStyle(color: AppColors.error)));
  }
}