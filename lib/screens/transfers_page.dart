import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import 'transfer_reception_page.dart';
import 'fleet_map_page.dart';
import 'transfer_create_page.dart';

class TransfersPage extends StatefulWidget {
  final VoidCallback? onBack;
  const TransfersPage({super.key, this.onBack});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<dynamic> _transfers = [];
  List<dynamic> _filteredTransfers = [];
  bool _isLoading = true;
  String _selectedStatus = 'all'; // all, in_transit, completed, cancelled

  final List<Map<String, dynamic>> _statusFilters = [
    {'key': 'all', 'label': 'Tous', 'icon': FontAwesomeIcons.layerGroup, 'color': AppColors.primary},
    {'key': 'in_transit', 'label': 'En Transit', 'icon': FontAwesomeIcons.truckMoving, 'color': Colors.orange},
    {'key': 'completed', 'label': 'Terminé', 'icon': FontAwesomeIcons.circleCheck, 'color': AppColors.success},
    {'key': 'cancelled', 'label': 'Annulé', 'icon': FontAwesomeIcons.ban, 'color': AppColors.error},
  ];

  @override
  void initState() {
    super.initState();
    _loadTransfers();
    _searchCtrl.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTransfers() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.getPendingTransfers();
      if (mounted) {
        setState(() {
          _transfers = data;
          _isLoading = false;
          _applyFilters();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur chargement transferts: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _applyFilters() {
    List<dynamic> result = List.from(_transfers);

    // Filter by status
    if (_selectedStatus != 'all') {
      result = result.where((t) => _getStatus(t) == _selectedStatus).toList();
    }

    // Filter by search
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((t) {
        final ref = (t['reference'] ?? t['id'] ?? '').toString().toLowerCase();
        final from = (t['from_warehouse_name'] ?? t['from_name'] ?? '').toString().toLowerCase();
        final to = (t['to_warehouse_name'] ?? t['to_name'] ?? '').toString().toLowerCase();
        return ref.contains(query) || from.contains(query) || to.contains(query);
      }).toList();
    }

    if (mounted) setState(() => _filteredTransfers = result);
  }

  String _getStatus(dynamic t) {
    final s = (t['status'] ?? '').toString().toLowerCase();
    if (s == 'in_transit' || s == 'pending' || s == 'sent') return 'in_transit';
    if (s == 'completed' || s == 'received') return 'completed';
    if (s == 'cancelled') return 'cancelled';
    return s;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'in_transit': return Colors.orange;
      case 'completed': return AppColors.success;
      case 'cancelled': return AppColors.error;
      default: return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'in_transit': return 'EN TRANSIT';
      case 'completed': return 'TERMINÉ';
      case 'cancelled': return 'ANNULÉ';
      default: return status.toUpperCase();
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'in_transit': return FontAwesomeIcons.truckMoving;
      case 'completed': return FontAwesomeIcons.circleCheck;
      case 'cancelled': return FontAwesomeIcons.ban;
      default: return FontAwesomeIcons.question;
    }
  }

  String _fmtDate(dynamic dateStr) {
    if (dateStr == null) return '---';
    try {
      return DateFormat('dd/MM/yy', 'fr').format(DateTime.parse(dateStr.toString()));
    } catch (_) {
      return dateStr.toString().split('T').first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const TransferCreatePage()));
          if (result == true) _loadTransfers();
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Nouveau Transfert", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildHeader(context, isDark),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : Column(
                    children: [
                      // Search + Filters
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Column(
                          children: [
                            _buildSearchBar(isDark),
                            const SizedBox(height: 12),
                            _buildStatusChips(isDark),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Counter
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Text('${_filteredTransfers.length} transfert(s)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white54 : Colors.grey)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // List
                      Expanded(
                        child: _filteredTransfers.isEmpty
                            ? _buildEmptyList(isDark)
                            : RefreshIndicator(
                                onRefresh: _loadTransfers,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                  itemCount: _filteredTransfers.length,
                                  itemBuilder: (ctx, i) => _buildTransferCard(_filteredTransfers[i], isDark),
                                ),
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════
  Widget _buildHeader(BuildContext context, bool isDark) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade700, Colors.blueGrey.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.blueGrey.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
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
                Text("INTER-DÉPÔTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 2)),
                SizedBox(height: 2),
                Text("Transferts", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _loadTransfers,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.refresh, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // SEARCH BAR
  // ═══════════════════════════════════════
  Widget _buildSearchBar(bool isDark) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: 'Rechercher par référence, dépôt...',
          hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey),
          prefixIcon: Icon(Icons.search, size: 20, color: isDark ? Colors.white38 : Colors.grey),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? GestureDetector(onTap: () { _searchCtrl.clear(); _applyFilters(); }, child: Icon(Icons.close, size: 18, color: isDark ? Colors.white38 : Colors.grey))
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // STATUS CHIPS
  // ═══════════════════════════════════════
  Widget _buildStatusChips(bool isDark) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _statusFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final f = _statusFilters[i];
          final isActive = _selectedStatus == f['key'];
          final color = f['color'] as Color;

          return GestureDetector(
            onTap: () {
              setState(() => _selectedStatus = f['key']);
              _applyFilters();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? color.withValues(alpha: 0.15) : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isActive ? color : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300), width: isActive ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Icon(f['icon'], size: 12, color: isActive ? color : (isDark ? Colors.white54 : Colors.grey)),
                  const SizedBox(width: 6),
                  Text(f['label'], style: TextStyle(fontSize: 11, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? color : (isDark ? Colors.white54 : Colors.grey.shade600))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════
  // TRANSFER CARD
  // ═══════════════════════════════════════
  Widget _buildTransferCard(dynamic t, bool isDark) {
    final status = _getStatus(t);
    final statusColor = _getStatusColor(status);
    final isActionable = status == 'in_transit';
    final itemCount = (t['item_count'] ?? t['items_count'] ?? 0).toString();
    final ref = t['reference'] ?? 'TRF-${t['id']}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: isActionable
            ? () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => TransferReceptionPage(transferId: t['id'])));
                if (result == true) _loadTransfers(); // Refresh on return
              }
            : null,
        child: GlassCard(
          isDark: isDark,
          borderRadius: 16,
          padding: const EdgeInsets.all(16),
          borderColor: isActionable ? statusColor.withValues(alpha: 0.4) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Status icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_getStatusIcon(status), color: statusColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(alignment: Alignment.centerLeft, child: Text(ref.toString(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black))),
                        const SizedBox(height: 2),
                        FittedBox(alignment: Alignment.centerLeft, child: Text('$itemCount articles', style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey))),
                        if (t['van_name'] != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(FontAwesomeIcons.truckFast, size: 10, color: statusColor),
                              const SizedBox(width: 4),
                              Expanded(child: Text('${t['van_name']} (${t['driver_name'] ?? 'Chauffeur inconnu'})', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FittedBox(child: Text(_getStatusLabel(status), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: statusColor, letterSpacing: 0.5))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // From → To
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DÉPART', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: isDark ? Colors.white38 : Colors.grey, letterSpacing: 1)),
                          const SizedBox(height: 2),
                          FittedBox(alignment: Alignment.centerLeft, child: Text(t['from_warehouse_name'] ?? t['from_name'] ?? 'Dépôt source', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black))),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(FontAwesomeIcons.arrowRight, size: 14, color: statusColor),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('ARRIVÉE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: isDark ? Colors.white38 : Colors.grey, letterSpacing: 1)),
                          const SizedBox(height: 2),
                          FittedBox(alignment: Alignment.centerRight, child: Text(t['to_warehouse_name'] ?? t['to_name'] ?? 'Dépôt destination', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Footer: Date + Action
              Row(
                children: [
                  Icon(FontAwesomeIcons.calendar, size: 11, color: isDark ? Colors.white38 : Colors.grey),
                  const SizedBox(width: 6),
                  Text(_fmtDate(t['created_at'] ?? t['date']), style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey)),
                  const Spacer(),
                  if (status == 'in_transit' && t['van_id'] != null)
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FleetMapPage(targetVanId: t['van_id']))),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(FontAwesomeIcons.locationDot, size: 10, color: Colors.orange),
                            SizedBox(width: 6),
                            Text('Live Tracking', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.orange)),
                          ],
                        ),
                      ),
                    ),
                  if (isActionable)
                    GestureDetector(
                      onTap: () async {
                        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => TransferReceptionPage(transferId: t['id'])));
                        if (result == true) _loadTransfers(); // Refresh on return
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Colors.blueGrey.shade600, Colors.blueGrey.shade400]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(FontAwesomeIcons.barcode, size: 10, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Réceptionner', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // EMPTY LIST
  // ═══════════════════════════════════════
  Widget _buildEmptyList(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.blueGrey.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(FontAwesomeIcons.boxesStacked, color: Colors.blueGrey, size: 40),
          ),
          const SizedBox(height: 16),
          Text('Aucun transfert trouvé', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 6),
          Text(
            _selectedStatus != 'all'
                ? 'Aucun transfert avec le statut "${_getStatusLabel(_selectedStatus)}"'
                : 'Aucun transfert inter-dépôts en cours.',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
