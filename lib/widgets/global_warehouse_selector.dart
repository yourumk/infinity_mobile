// 🛠️ FIX MULTI-DEPOT MOBILE : Sélecteur de dépôt global omniprésent
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../providers/data_provider.dart';
import '../core/constants.dart';

/// Widget Global qui affiche un bouton de sélection de dépôt.
/// Visible UNIQUEMENT si l'utilisateur a un accès global (assigned_warehouse_id == null).
/// Se place dans le header de l'application pour être accessible depuis toutes les pages.
class GlobalWarehouseSelector extends StatefulWidget {
  const GlobalWarehouseSelector({super.key});

  @override
  State<GlobalWarehouseSelector> createState() => _GlobalWarehouseSelectorState();
}

class _GlobalWarehouseSelectorState extends State<GlobalWarehouseSelector> {
  bool _isGlobal = false;
  String _currentLabel = 'Tous les Dépôts';
  int? _currentId;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final isGlobal = prefs.getBool('global_warehouse') ?? false;
    final selectedId = prefs.getInt('selected_warehouse_id');

    if (!mounted) return;
    setState(() {
      _isGlobal = isGlobal;
      _currentId = selectedId;
    });

    // Charger le nom du dépôt sélectionné s'il existe
    if (isGlobal && selectedId != null) {
      _loadWarehouseName(selectedId);
    }
  }

  Future<void> _loadWarehouseName(int id) async {
    try {
      final res = await ApiService().getLogisticsResources();
      if (res['success'] == true) {
        final warehouses = res['warehouses'] as List? ?? [];
        for (final wh in warehouses) {
          if (wh['id'] == id) {
            if (!mounted) return;
            setState(() => _currentLabel = wh['name'] ?? 'Dépôt #$id');
            return;
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Ne rien afficher si l'utilisateur a un accès restreint
    if (!_isGlobal) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _showWarehousePicker(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _currentId != null
                ? [const Color(0xFF059669), const Color(0xFF10B981)]
                : [
                    isDark ? const Color(0xFF2D2D3F) : const Color(0xFFF1F5F9),
                    isDark ? const Color(0xFF3D3D4F) : const Color(0xFFE2E8F0),
                  ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _currentId != null
                ? const Color(0xFF059669).withOpacity(0.5)
                : isDark ? Colors.white12 : Colors.black12,
          ),
          boxShadow: [
            BoxShadow(
              color: _currentId != null
                  ? const Color(0xFF059669).withOpacity(0.25)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _currentId != null ? Icons.store : Icons.warehouse_rounded,
              size: 16,
              color: _currentId != null
                  ? Colors.white
                  : isDark ? Colors.white70 : Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                _currentId != null ? _currentLabel : '🌍 Vue Globale',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _currentId != null
                      ? Colors.white
                      : isDark ? Colors.white70 : Colors.grey.shade800,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: _currentId != null
                  ? Colors.white70
                  : isDark ? Colors.white38 : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  void _showWarehousePicker(BuildContext outerContext) {
    showModalBottomSheet(
      context: outerContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WarehousePickerSheet(
        currentId: _currentId,
        onSelected: (int? id, String name) async {
          Navigator.of(ctx).pop();

          // 1. Sauvegarder et purger le cache
          await ApiService().switchWarehouse(id);

          // 2. Mettre à jour l'UI locale
          if (!mounted) return;
          setState(() {
            _currentId = id;
            _currentLabel = name;
          });

          // 3. Forcer le rechargement du DataProvider (dashboard)
          if (outerContext.mounted) {
            Provider.of<DataProvider>(outerContext, listen: false)
                .loadData(forceRefresh: true);
          }

          // 4. Feedback visuel
          if (outerContext.mounted) {
            ScaffoldMessenger.of(outerContext).showSnackBar(
              SnackBar(
                content: Text(
                  id != null ? '🏢 Dépôt: $name' : '🌍 Vue Globale activée',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: id != null ? const Color(0xFF059669) : AppColors.primary,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }
}

// ===========================================================================
// 🏢 BOTTOM SHEET : Liste des dépôts disponibles
// ===========================================================================
class _WarehousePickerSheet extends StatefulWidget {
  final int? currentId;
  final void Function(int? id, String name) onSelected;

  const _WarehousePickerSheet({
    required this.currentId,
    required this.onSelected,
  });

  @override
  State<_WarehousePickerSheet> createState() => _WarehousePickerSheetState();
}

class _WarehousePickerSheetState extends State<_WarehousePickerSheet> {
  List<Map<String, dynamic>> _warehouses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    try {
      final res = await ApiService().getLogisticsResources();
      if (res['success'] == true) {
        final list = (res['warehouses'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (!mounted) return;
        setState(() {
          _warehouses = list;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement dépôts: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.warehouse_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Changer de Dépôt',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Les données seront rechargées instantanément',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Loading or List
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  // Option "Vue Globale"
                  _buildWarehouseTile(
                    id: null,
                    name: '🌍 Vue Globale (Tous)',
                    subtitle: 'Voir les données de tous les dépôts',
                    icon: Icons.public_rounded,
                    color: AppColors.primary,
                    isSelected: widget.currentId == null,
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      'DÉPÔTS & MAGASINS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),

                  // Warehouse list
                  ..._warehouses.map((wh) {
                    final id = wh['id'] as int;
                    final name = wh['name']?.toString() ?? 'Dépôt #$id';
                    final type = wh['type']?.toString() ?? 'store';
                    final icon = type == 'van'
                        ? Icons.local_shipping_rounded
                        : type == 'master'
                            ? Icons.home_work_rounded
                            : Icons.store_rounded;
                    final color = type == 'van'
                        ? const Color(0xFFF59E0B)
                        : type == 'master'
                            ? const Color(0xFF059669)
                            : const Color(0xFF6366F1);

                    return _buildWarehouseTile(
                      id: id,
                      name: name,
                      subtitle: type == 'van' ? 'Fourgon' : type == 'master' ? 'Dépôt Principal' : 'Magasin',
                      icon: icon,
                      color: color,
                      isSelected: widget.currentId == id,
                    );
                  }),

                  const SizedBox(height: 20),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWarehouseTile({
    required int? id,
    required String name,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isSelected
            ? color.withOpacity(isDark ? 0.2 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onSelected(id, id == null ? 'Vue Globale' : name),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected ? Border.all(color: color, width: 2) : null,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? color : null,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
