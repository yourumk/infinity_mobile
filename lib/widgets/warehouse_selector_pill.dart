// 🛠️ FIX UI/STATE : Pilule Indestructible (Glassmorphism & Anti-Overflow)
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../providers/data_provider.dart';
import '../core/constants.dart';

class WarehouseSelectorPill extends StatefulWidget {
  const WarehouseSelectorPill({super.key});

  @override
  State<WarehouseSelectorPill> createState() => _WarehouseSelectorPillState();
}

class _WarehouseSelectorPillState extends State<WarehouseSelectorPill> {
  bool _isGlobal = false;
  bool _hasAssignedWarehouse = false;
  String _currentLabel = 'Tous les Dépôts';
  int? _currentId;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 🛠️ FIX UI/STATE & RBAC : Sécurité de l'accès et masquage pour Chauffeur
    final assignedId = prefs.getInt('assigned_warehouse_id');
    final role = prefs.getString('user_role');
    
    if (assignedId != null || role == 'chauffeur') {
      if (!mounted) return;
      setState(() => _hasAssignedWarehouse = true);
      return; // Disparaît si assigné ou si chauffeur
    }

    final isGlobal = prefs.getBool('global_warehouse') ?? false;
    final selectedId = prefs.getInt('selected_warehouse_id');

    if (!mounted) return;
    setState(() {
      _isGlobal = isGlobal;
      _currentId = selectedId;
    });

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
    // 🛠️ FIX UI/STATE : Disparaît pour les utilisateurs non-globaux ou assignés à un dépôt
    if (!_isGlobal || _hasAssignedWarehouse) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showWarehousePicker(context),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _currentId != null ? _currentLabel : 'Tous les Dépôts',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary, // 🛠️ FIX UI/STATE : Couleur primaire pour signifier que c'est cliquable
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),
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

          await ApiService().switchWarehouse(id);

          if (!mounted) return;
          setState(() {
            _currentId = id;
            _currentLabel = name;
          });

          if (outerContext.mounted) {
            Provider.of<DataProvider>(outerContext, listen: false)
                .loadData(forceRefresh: true);
          }

          if (outerContext.mounted) {
            ScaffoldMessenger.of(outerContext).showSnackBar(
              SnackBar(
                content: Text(
                  id != null ? '🏢 Dépôt: $name' : '🌍 Vue Globale activée',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: AppColors.primary,
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
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    try {
      final res = await ApiService().getLogisticsResources();
      if (res['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        final role = prefs.getString('user_role') ?? '';

        final list = (res['warehouses'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((w) {
              // 🛠️ FIX CHANTIER 3 : Un fourgon n'est jamais un contexte global
              if (w['type'] == 'van') return false;
              // 🛠️ FIX CHANTIER 3 : Caissier/Vendeur ne voit que les magasins
              if (role == 'caissier' || role == 'vendeur') {
                return w['type'] == 'store' || w['type'] == 'store_with_depot';
              }
              return true;
            })
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
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E2C) : Colors.white;

    final filteredList = _warehouses.where((wh) {
      final name = (wh['name']?.toString() ?? '').toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.storefront_rounded, size: 28, color: AppColors.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Changer de Dépôt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('Sélectionnez votre environnement de travail', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Rechercher un magasin...",
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const Divider(height: 1),
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
                  if (_searchQuery.isEmpty)
                    _buildWarehouseTile(
                      id: null,
                      name: '🌍 Vue Globale (Tous)',
                      subtitle: 'Voir les données de tous les dépôts',
                      icon: Icons.public_rounded,
                      color: AppColors.primary,
                      isSelected: widget.currentId == null,
                    ),
                  if (_searchQuery.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Text(
                        'DÉPÔTS & MAGASINS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 1.0),
                      ),
                    ),
                  if (filteredList.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text('Aucun résultat trouvé', style: TextStyle(color: Colors.grey))),
                    ),
                  ...filteredList.map((wh) {
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
