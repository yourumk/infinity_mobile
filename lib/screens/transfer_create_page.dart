import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/api_service.dart';
import '../core/constants.dart';

import 'package:shared_preferences/shared_preferences.dart';

class TransferCreatePage extends StatefulWidget {
  final int? pendingVanLoadId; // 🛠️ FIX CHANTIER 3 : Charger un fourgon spécifique
  const TransferCreatePage({super.key, this.pendingVanLoadId});

  @override
  State<TransferCreatePage> createState() => _TransferCreatePageState();
}

class _TransferCreatePageState extends State<TransferCreatePage> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _warehouses = [];
  List<dynamic> _vans = []; // 🛠️ FIX CHANTIER 3 : Fourgons de transit
  List<dynamic> _products = [];
  int? _selectedToWh;
  int? _selectedTransitVan;

  final List<Map<String, dynamic>> _selectedItems = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.getLogisticsResources();
      final pRes = await _api.getProducts();
      final prefs = await SharedPreferences.getInstance();
      final currentWhId = prefs.getInt('assigned_warehouse_id') ?? prefs.getInt('selected_warehouse_id');
      
      if (mounted) {
        // 🛠️ FIX CHANTIER 3 : Exclure les fourgons du menu destination ET le dépôt actuel
        final rawWarehouses = res['warehouses'] ?? [];
        final filteredWarehouses = (rawWarehouses as List).where((w) {
          if (w['type'] == 'van' && w['id'] != widget.pendingVanLoadId) return false;
          if (w['id'] == currentWhId) return false;
          return true;
        }).toList();

        final vans = (rawWarehouses as List).where((w) => w['type'] == 'van').toList();

        setState(() {
          _warehouses = filteredWarehouses;
          _vans = vans;
          _products = pRes;
          if (widget.pendingVanLoadId != null) {
            _selectedToWh = widget.pendingVanLoadId; // Bloque la destination
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur chargement: $e')));
      }
    }
  }

  void _showAddProductDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          builder: (ctx, scrollController) {
            return Container(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              child: ListView.builder(
                controller: scrollController,
                itemCount: _products.length,
                itemBuilder: (ctx, i) {
                  final p = _products[i];
                  return ListTile(
                    title: Text(p['name'] ?? 'Inconnu'),
                    subtitle: Text(p['base_reference'] ?? ''),
                    trailing: const Icon(Icons.add_circle, color: AppColors.primary),
                    onTap: () {
                      Navigator.pop(ctx);
                      _addItem(p);
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  void _addItem(dynamic product) {
    setState(() {
      final existing = _selectedItems.indexWhere((item) => item['product_id'] == product['id']);
      if (existing >= 0) {
        _selectedItems[existing]['qty'] += 1;
      } else {
        _selectedItems.add({
          'product_id': product['id'],
          'name': product['name'],
          'qty': 1,
        });
      }
    });
  }

  void _submit() async {
    if (_selectedToWh == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez choisir un dépôt de destination.')));
      return;
    }
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez ajouter des articles.')));
      return;
    }

    setState(() => _isLoading = true);
    
   // 🛠️ FIX CHANTIER 3 : Injection du transit van
    List<Map<String, dynamic>> finalItems = List.from(_selectedItems);
    
    // 🟢 Le van_id de transit est maintenant transmis à l'API
    final res = await _api.createTransfer(_selectedToWh!, finalItems, vanId: _selectedTransitVan);
    
    if (res['success'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transfert créé avec succès')));
        Navigator.pop(context, true);
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: ${res['message']}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Nouveau Transfert'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // 🛠️ FIX CHANTIER 3 : Si mode "Chargement Fourgon", afficher un champ
                  // verrouillé (pas un Dropdown) pour éviter 'value must be in items'
                  if (widget.pendingVanLoadId != null) ...[
                    TextFormField(
                      enabled: false,
                      initialValue: _vans.firstWhere(
                        (v) => v['id'] == widget.pendingVanLoadId,
                        orElse: () => {'name': 'Fourgon #${widget.pendingVanLoadId}'},
                      )['name']?.toString() ?? 'Fourgon #${widget.pendingVanLoadId}',
                      decoration: InputDecoration(
                        labelText: '🚛 Chargement Fourgon (bloqué)',
                        prefixIcon: const Icon(Icons.local_shipping, color: Colors.orange),
                        filled: true,
                        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.orange.withOpacity(0.06),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.orange.withOpacity(0.4)),
                        ),
                      ),
                    ),
                  ] else ...[
                    DropdownButtonFormField<int>(
                      value: _selectedToWh,
                      decoration: InputDecoration(
                        labelText: 'Dépôt de destination',
                        filled: true,
                        fillColor: isDark ? Colors.white10 : Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _warehouses.map((w) => DropdownMenuItem<int>(
                        value: w['id'],
                        child: Text(w['name']?.toString() ?? ''),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedToWh = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 🛠️ FIX CHANTIER 3 : Menu Fourgon de Transit masqué si chargement direct
                  if (widget.pendingVanLoadId == null)
                    DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: 'Fourgon de transit (Optionnel)',
                        filled: true,
                        fillColor: isDark ? Colors.white10 : Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      value: _selectedTransitVan,
                      items: [
                        const DropdownMenuItem<int>(value: null, child: Text('— Aucun (livraison directe) —')),
                        ..._vans.map((v) => DropdownMenuItem<int>(
                          value: v['id'],
                          child: Text('🚛 ${v['name']}'),
                        )),
                      ],
                      onChanged: (v) => setState(() => _selectedTransitVan = v),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Articles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        onPressed: _showAddProductDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _selectedItems.isEmpty
                        ? const Center(child: Text('Aucun article sélectionné'))
                        : ListView.builder(
                            itemCount: _selectedItems.length,
                            itemBuilder: (ctx, i) {
                              final item = _selectedItems[i];
                              return Card(
                                child: ListTile(
                                  title: Text(item['name']),
                                  subtitle: Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline),
                                        onPressed: () {
                                          setState(() {
                                            if (item['qty'] > 1) {
                                              item['qty']--;
                                            } else {
                                              _selectedItems.removeAt(i);
                                            }
                                          });
                                        },
                                      ),
                                      Text('${item['qty']} unités', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline),
                                        onPressed: () {
                                          setState(() => item['qty']++);
                                        },
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => setState(() => _selectedItems.removeAt(i)),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _submit,
                      icon: const Icon(FontAwesomeIcons.check),
                      label: const Text('Valider l\'expédition', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
