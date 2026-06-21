import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../core/constants.dart';

/// 🗺️ VMS — Écran "Ma Tournée" (Programme de Visite)
/// Affiche la liste ordonnée des arrêts clients planifiés pour la tournée active.
/// Le chauffeur peut faire un check-in GPS à chaque visite.
class TourStopsPage extends StatefulWidget {
  final VoidCallback? onBack;
  const TourStopsPage({super.key, this.onBack});

  @override
  State<TourStopsPage> createState() => _TourStopsPageState();
}

class _TourStopsPageState extends State<TourStopsPage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _stops = [];
  bool _loading = true;
  bool _checkingIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStops();
  }

  Future<void> _loadStops() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ApiService();
      final stops = await api.fetchTourStops();
      if (mounted) {
        setState(() {
          _stops = stops;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _checkIn(Map<String, dynamic> stop) async {
    if (_checkingIn) return;
    setState(() => _checkingIn = true);

    try {
      // Obtenir la position GPS actuelle
      double? lat, lng;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 10));
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (e) {
        debugPrint("VMS: GPS non disponible pour check-in: $e");
      }

      final api = ApiService();
      final result = await api.checkInStop(
        stop['id'] is int ? stop['id'] : int.parse(stop['id'].toString()),
        lat: lat,
        lng: lng,
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('✅ Visite enregistrée : ${stop['client_name']}')),
              ]),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          _loadStops(); // Rafraîchir la liste
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${result['message'] ?? 'Erreur'}'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F4F8);
    
    final visitedCount = _stops.where((s) => s['status'] == 'visited').length;
    final totalCount = _stops.length;
    final progress = totalCount > 0 ? visitedCount / totalCount : 0.0;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black87),
          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🗺️ Ma Tournée', style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 20,
              color: isDark ? Colors.white : Colors.black87,
            )),
            if (totalCount > 0)
              Text('$visitedCount / $totalCount arrêts visités',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.black45)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _loadStops,
          ),
        ],
      ),
      body: Column(
        children: [
          // Barre de progression
          if (totalCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progress >= 1.0 ? const Color(0xFF10B981) : AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        progress >= 1.0 ? '🎉 Tournée complète !' : '${(progress * 100).toInt()}% complété',
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: progress >= 1.0 ? const Color(0xFF10B981) : AppColors.primary,
                        ),
                      ),
                      Text(
                        '${totalCount - visitedCount} restant(s)',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Corps
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text('Erreur de chargement', style: TextStyle(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: _loadStops, child: const Text('Réessayer')),
                        ],
                      ))
                    : _stops.isEmpty
                        ? Center(child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.route, size: 80, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text('Aucun arrêt planifié', style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white70 : Colors.black54,
                              )),
                              const SizedBox(height: 8),
                              Text('Votre responsable n\'a pas encore\nprogrammé de visites pour cette tournée.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                            ],
                          ))
                        : RefreshIndicator(
                            onRefresh: _loadStops,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                              itemCount: _stops.length,
                              itemBuilder: (ctx, idx) => _buildStopCard(_stops[idx], idx, isDark),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopCard(Map<String, dynamic> stop, int index, bool isDark) {
    final isVisited = stop['status'] == 'visited';
    final isPending = stop['status'] == 'pending';
    final clientName = stop['client_name'] ?? 'Client Inconnu';
    final clientPhone = stop['client_phone'] ?? '';
    final clientAddress = stop['client_address'] ?? '';
    final visitedAt = stop['visited_at'];

    // Couleurs selon statut
    final cardBg = isVisited
        ? (isDark ? const Color(0xFF0D2818) : const Color(0xFFF0FDF4))
        : (isDark ? const Color(0xFF1A1A2E) : Colors.white);
    final borderColor = isVisited
        ? const Color(0xFF10B981)
        : (isDark ? Colors.white10 : const Color(0xFFE2E8F0));
    final numberBg = isVisited
        ? const Color(0xFF10B981)
        : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isVisited ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Numéro d'ordre
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isVisited
                      ? [const Color(0xFF10B981), const Color(0xFF059669)]
                      : [AppColors.primary, const Color(0xFF7C3AED)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: isVisited
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : Text('${index + 1}', style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
            const SizedBox(width: 14),

            // Infos client
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(clientName, style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    decoration: isVisited ? TextDecoration.lineThrough : null,
                    decorationColor: const Color(0xFF10B981),
                  )),
                  const SizedBox(height: 4),
                  if (clientAddress.isNotEmpty)
                    Row(children: [
                      Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(child: Text(clientAddress, style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500,
                      ), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  if (clientPhone.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(children: [
                        Icon(Icons.phone, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(clientPhone, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ]),
                    ),
                  if (isVisited && visitedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '✅ Visité ${_formatVisitTime(visitedAt)}',
                          style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bouton Check-in
            if (isPending)
              GestureDetector(
                onTap: _checkingIn ? null : () => _showCheckInConfirm(stop),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _checkingIn
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gps_fixed, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text('Visiter', style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showCheckInConfirm(Map<String, dynamic> stop) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.gps_fixed, color: Color(0xFF10B981), size: 24),
          const SizedBox(width: 10),
          Text('Confirmer la Visite', style: TextStyle(
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
          )),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vous êtes sur le point de marquer la visite chez :',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF3B82F6)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text(
                    (stop['client_name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop['client_name'] ?? 'Client', style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    )),
                    if ((stop['client_address'] ?? '').isNotEmpty)
                      Text(stop['client_address'], style: TextStyle(
                        fontSize: 12, color: isDark ? Colors.white38 : Colors.black38,
                      )),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.info_outline, size: 14, color: Colors.amber),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'Votre position GPS sera enregistrée automatiquement.',
                style: TextStyle(fontSize: 11, color: Colors.amber.shade700, fontWeight: FontWeight.w600),
              )),
            ]),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _checkIn(stop);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('📍 Confirmer la Visite', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  String _formatVisitTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return 'à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
