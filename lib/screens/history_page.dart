import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class HistoryPage extends StatefulWidget {
  final VoidCallback? onBack;
  final int initialTab; // 0 = Ventes, 1 = Achats

  const HistoryPage({super.key, this.onBack, this.initialTab = 0});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final ApiService _api = ApiService();
  StreamSubscription? _syncSubscription;
  
  bool _isLoading = true;
  List<dynamic> _items = []; // 🟢 Une seule liste (ventes OU achats)

  // 🟢 Mode figé dès la construction
  bool get isSale => widget.initialTab == 0;

  // 🛠️ FILTRES
  int _displayLimit = 0; // 0 = tout
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _loadHistory();

    _api.startAutoSync();
    _syncSubscription = _api.onDataUpdated.listen((_) {
      if (mounted) {
        print("📥 Historique : Refresh auto...");
        _loadHistory(isSilent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);
    try {
      // 🟢 ISOLATION : Ne charger QUE ce qui est nécessaire
      final result = isSale
          ? await _api.getSalesList(limit: 50)
          : await _api.getPurchasesList(limit: 50);

      if (mounted) {
        setState(() {
          _items = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (!isSilent) setState(() => _isLoading = false);
        if (!isSilent) {
          final apiError = _api.lastError;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("⚠️ ${apiError ?? 'Erreur chargement historique: $e'}"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ));
        }
      }
    }
  }

  void _showDetailSheet(Map<String, dynamic> data, bool isSale) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => HistoryDetailSheet(api: _api, data: data, isSale: isSale, onUpdated: () => _loadHistory()),
    );
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageTitle = isSale ? "Historique Ventes" : "Historique Achats";
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      body: Column(
        children: [
          // --- HEADER (SANS TABS) ---
          Container(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 10, 20, 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C23) : Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black),
                  onPressed: widget.onBack ?? () => Navigator.pop(context),
                ),
                Text(pageTitle, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                const SizedBox(width: 40, child: Icon(Icons.cloud_sync, size: 18, color: Colors.grey)), 
              ],
            ),
          ),

          // 🛠️ BARRE DE FILTRES
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                // Chips quantité
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Tout', 0, isDark),
                      _buildFilterChip('10', 10, isDark),
                      _buildFilterChip('50', 50, isDark),
                      _buildFilterChip('100', 100, isDark),
                      const SizedBox(width: 8),
                      // Bouton date "De"
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dateFrom ?? DateTime.now().subtract(const Duration(days: 30)),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _dateFrom = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _dateFrom != null ? AppColors.primary.withOpacity(0.15) : (isDark ? Colors.white10 : Colors.grey[200]),
                            borderRadius: BorderRadius.circular(20),
                            border: _dateFrom != null ? Border.all(color: AppColors.primary, width: 1.5) : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 13, color: _dateFrom != null ? AppColors.primary : Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                _dateFrom != null ? DateFormat('dd/MM').format(_dateFrom!) : 'Du',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _dateFrom != null ? AppColors.primary : Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Bouton date "Au"
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dateTo ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _dateTo = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _dateTo != null ? AppColors.primary.withOpacity(0.15) : (isDark ? Colors.white10 : Colors.grey[200]),
                            borderRadius: BorderRadius.circular(20),
                            border: _dateTo != null ? Border.all(color: AppColors.primary, width: 1.5) : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 13, color: _dateTo != null ? AppColors.primary : Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                _dateTo != null ? DateFormat('dd/MM').format(_dateTo!) : 'Au',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _dateTo != null ? AppColors.primary : Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Bouton reset
                      if (_dateFrom != null || _dateTo != null)
                        GestureDetector(
                          onTap: () => setState(() { _dateFrom = null; _dateTo = null; }),
                          child: Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 14, color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- LISTE UNIQUE (pas de TabBarView) ---
          Expanded(
            child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _buildList(_items, isDark, isSale),
          ),
        ],
      ),
    );
  }

Widget _buildFilterChip(String label, int value, bool isDark) {
    final isSelected = _displayLimit == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _displayLimit = value),
        selectedColor: AppColors.primary,
        backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
        labelStyle: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black87), fontWeight: FontWeight.bold, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  List<dynamic> _applyFilters(List<dynamic> items) {
    var result = items;
    // Filtre date
    if (_dateFrom != null || _dateTo != null) {
      result = result.where((item) {
        try {
          if (item['date'] == null) return false;
          final d = DateTime.parse(item['date'].toString());
          if (_dateFrom != null && d.isBefore(_dateFrom!)) return false;
          if (_dateTo != null && d.isAfter(_dateTo!.add(const Duration(days: 1)))) return false;
          return true;
        } catch (_) { return true; }
      }).toList();
    }
    // Filtre quantité
    if (_displayLimit > 0) {
      result = result.take(_displayLimit).toList();
    }
    return result;
  }

 Widget _buildList(List<dynamic> items, bool isDark, bool isSale) {
    final filtered = _applyFilters(items);
    if (filtered.isEmpty) return const Center(child: Text("Historique vide"));

    return RefreshIndicator(
      onRefresh: () => _loadHistory(isSilent: false),
      color: AppColors.primary,
      child: ListView.builder(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 100),
        itemCount: filtered.length,
        itemBuilder: (ctx, i) {
          final item = filtered[i];
          final amount = double.tryParse(item['total_amount']?.toString() ?? '0') ?? 0;
          
          // 👉 SÉCURISATION DE LA DATE
          DateTime? parsedDate;
          try {
            if (item['date'] != null && item['date'].toString().isNotEmpty) {
              parsedDate = DateTime.parse(item['date'].toString());
            }
          } catch(e) {
            parsedDate = null;
          }
          
          final dateStr = parsedDate != null 
              ? DateFormat('dd/MM/yyyy HH:mm').format(parsedDate) 
              : '---';
              
          final name = item['client_name'] ?? item['supplier_name'] ?? (isSale ? 'Client Divers' : 'Fournisseur');
          final ref = item['invoice_number'] ?? item['number'] ?? item['id'];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => _showDetailSheet(item, isSale),
              child: GlassCard(
                isDark: isDark,
                padding: const EdgeInsets.all(15),
                borderRadius: 20,
                child: Row(
                  children: [
                    Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(
                        color: (isSale ? Colors.green : Colors.orange).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(isSale ? FontAwesomeIcons.basketShopping : FontAwesomeIcons.truck, color: isSale ? Colors.green : Colors.orange, size: 20),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text("$dateStr • #$ref", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        NumberFormat.compactCurrency(locale: 'fr', symbol: 'DA', decimalDigits: 2).format(amount), 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSale ? AppColors.primary : Colors.orange),
                      ),
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
}

class HistoryDetailSheet extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> data;
  final bool isSale;
  final VoidCallback? onUpdated;

  const HistoryDetailSheet({super.key, required this.api, required this.data, required this.isSale, this.onUpdated});

  @override
  State<HistoryDetailSheet> createState() => _HistoryDetailSheetState();
}

class _HistoryDetailSheetState extends State<HistoryDetailSheet> {
  ApiService get api => widget.api;
  Map<String, dynamic> get data => widget.data;
  bool get isSale => widget.isSale;

  Future<List<dynamic>> _loadItems() async {
    if (data['items'] != null) {
        if (data['items'] is String) {
            try { return json.decode(data['items']); } catch(e) { return []; }
        }
        if (data['items'] is List) return data['items'];
    }
    return isSale ? api.getSaleItems(data['id']) : api.getPurchaseItems(data['id']);
  }

  /// 🟢 MODIFICATION DE TICKET : Charge les items et ouvre un dialogue d'édition
  Future<void> _editSale(BuildContext context) async {
    // Charger les items de la vente
    final items = await _loadItems();
    if (items.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible de charger les détails de cette vente."), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // Préparer les items pour l'édition (format compatible avec updateSale)
    final editableItems = items.map<Map<String, dynamic>>((item) {
      return {
        'product_id': item['product_id'] ?? item['id'],
        'variant_id': item['variant_id'],
        'name': item['name'] ?? item['product_name'] ?? 'Article',
        'qty': double.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1.0,
        'price': double.tryParse(item['price']?.toString() ?? item['unit_price']?.toString() ?? item['price_at_sale']?.toString() ?? '0') ?? 0.0,
        'cost': double.tryParse(item['cost']?.toString() ?? item['purchase_price_at_sale']?.toString() ?? '0') ?? 0.0,
        'vat_percent': double.tryParse(item['vat_percent']?.toString() ?? '0') ?? 0.0,
      };
    }).toList();

    if (!context.mounted) return;

    // Ouvrir le dialog d'édition simplifié
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditSaleSheet(
        saleId: data['id'],
        items: editableItems,
        originalTotal: double.tryParse(data['total_amount']?.toString() ?? '0') ?? 0,
        clientName: data['client_name'],
        clientId: data['client_id'],
        originalTva: double.tryParse(data['total_vat']?.toString() ?? '0') ?? 0,
        originalTimbre: double.tryParse(data['timbre']?.toString() ?? '0') ?? 0,
        originalDiscount: double.tryParse(data['discount_value']?.toString() ?? '0') ?? 0,
        originalPaid: double.tryParse(data['amount_paid']?.toString() ?? '0') ?? 0,
      ),
    );

    if (result != null && context.mounted) {
      // Envoyer la modification via l'API
      try {
        await api.updateSale(
          saleId: result['sale_id'],
          total: result['total'],
          items: result['items'],
          clientId: result['client_id'],
          amountPaid: result['amount_paid'] ?? result['total'],
          paymentType: result['payment_type'] ?? 'cash',
          note: result['note'] ?? 'Modifié depuis Mobile',
          tva: result['tva'] ?? 0,
          timbre: result['timbre'] ?? 0,
          discount: result['discount'] ?? 0,
          ht: result['ht'] ?? 0,
        );
        if (context.mounted) {
          Navigator.pop(context); // Ferme le detail sheet
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Ticket modifié avec succès !"), backgroundColor: Colors.green),
          );
          
          // 🟢 PATIENTER 2 SECONDES LE TEMPS QUE LE PC FASSE LE CALCUL AVANT DE RAFRAÎCHIR L'ÉCRAN MOBILE
          Future.delayed(const Duration(seconds: 2), () {
             if (mounted) widget.onUpdated?.call();
          });
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Erreur: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// 🟢 MODIFICATION D'ACHAT : Charge les items et ouvre un dialogue d'édition
  Future<void> _editPurchase(BuildContext context) async {
    // Charger les items de l'achat
    final items = await _loadItems();
    if (items.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible de charger les détails de cet achat."), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // Préparer les items pour l'édition
    final editableItems = items.map<Map<String, dynamic>>((item) {
      return {
        'product_id': item['product_id'] ?? item['id'],
        'variant_id': item['variant_id'],
        'name': item['name'] ?? item['product_name'] ?? 'Article',
        'qty': double.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1.0,
        'price': double.tryParse(item['cost']?.toString() ?? item['purchase_price_at_sale']?.toString() ?? item['unit_price']?.toString() ?? item['price']?.toString() ?? '0') ?? 0.0,
        'cost': double.tryParse(item['cost']?.toString() ?? item['purchase_price_at_sale']?.toString() ?? item['unit_price']?.toString() ?? '0') ?? 0.0,
        'vat_percent': double.tryParse(item['vat_percent']?.toString() ?? '0') ?? 0.0,
      };
    }).toList();

    if (!context.mounted) return;

    // Ouvrir le dialog d'édition
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditPurchaseSheet(
        poId: data['id'],
        items: editableItems,
        originalTotal: double.tryParse(data['total_amount']?.toString() ?? '0') ?? 0,
        supplierName: data['supplier_name'],
        supplierId: data['supplier_id'],
        originalTva: double.tryParse(data['total_vat']?.toString() ?? '0') ?? 0,
        originalTimbre: double.tryParse(data['timbre']?.toString() ?? '0') ?? 0,
        originalDiscount: double.tryParse(data['discount_value']?.toString() ?? data['discount']?.toString() ?? '0') ?? 0,
        originalPaid: double.tryParse(data['amount_paid']?.toString() ?? '0') ?? 0,
      ),
    );

    if (result != null && context.mounted) {
      // Envoyer la modification via l'API
      try {
        await api.updatePurchase(
          poId: result['po_id'],
          total: result['total'],
          items: result['items'],
          supplierId: result['supplier_id'],
          amountPaid: result['amount_paid'] ?? result['total'],
          paymentType: result['payment_type'] ?? 'cash',
          note: result['note'] ?? 'Modifié depuis Mobile',
          tva: result['tva'] ?? 0,
          timbre: result['timbre'] ?? 0,
          discount: result['discount'] ?? 0,
          ht: result['ht'] ?? 0,
        );
        if (context.mounted) {
          Navigator.pop(context); // Ferme le detail sheet
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Achat modifié avec succès !"), backgroundColor: Colors.green),
          );
          
          Future.delayed(const Duration(seconds: 2), () {
             if (mounted) widget.onUpdated?.call();
          });
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Erreur: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isSale ? "Ticket #${data['invoice_number'] ?? data['id']}" : "Bon Achat #${data['number'] ?? data['id']}";
    final name = isSale ? (data['client_name'] ?? 'Client') : (data['supplier_name'] ?? 'Fournisseur');
    final color = isSale ? AppColors.primary : Colors.orange;

    final fmt = NumberFormat.currency(locale: 'fr_DZ', symbol: '', decimalDigits: 2);
    final totalAmount = double.tryParse(data['total_amount']?.toString() ?? '0') ?? 0;
    final totalHT = double.tryParse(data['total_ht']?.toString() ?? '0') ?? 0;
    final totalVat = double.tryParse(data['total_vat']?.toString() ?? '0') ?? 0;
    final timbre = double.tryParse(data['timbre']?.toString() ?? '0') ?? 0;
    final discountVal = double.tryParse(data['discount_value']?.toString() ?? data['global_discount']?.toString() ?? '0') ?? 0;
    final amountPaid = double.tryParse(data['amount_paid']?.toString() ?? '0') ?? 0;
    final remaining = totalAmount - amountPaid;
    final paymentType = data['payment_type']?.toString();
    final isReturn = data['is_return'] == 1 || data['is_return'] == true;
    final userName = data['user_name']?.toString() ?? data['source']?.toString();
    final registerName = data['register_name']?.toString();
    final warehouseName = data['warehouse_name']?.toString();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, 
      padding: EdgeInsets.fromLTRB(25, 25, 25, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black), overflow: TextOverflow.ellipsis)),
                        if (isReturn) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.withOpacity(0.4))),
                            child: const Text("RETOUR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.red)),
                          ),
                        ],
                      ],
                    ),
                    Text(name, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.orange, size: 22),
                    tooltip: isSale ? "Modifier ce ticket" : "Modifier cet achat",
                    onPressed: () => isSale ? _editSale(context) : _editPurchase(context),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ],
          ),
          const Divider(),
          
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _loadItems(),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Détails indisponibles."));
                
                final items = snapshot.data!;
                
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (c,i) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final item = items[i];
                    final itemName = item['name'] ?? item['product_name'] ?? 'Article';
                    final qty = double.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '0') ?? 0;
                    
                    double price = double.tryParse(item['price']?.toString() ?? item['unit_price']?.toString() ?? item['sale_price']?.toString() ?? item['cost']?.toString() ?? '0') ?? 0;
                    double total = double.tryParse(item['total']?.toString() ?? item['total_line']?.toString() ?? item['sub_total']?.toString() ?? '0') ?? 0;

                    if (price == 0 && total > 0 && qty > 0) price = total / qty;
                    if (total == 0 && qty > 0 && price > 0) total = qty * price;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 35, height: 35, alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text("${qty.toInt()}x", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(itemName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black)),
                                Text("${price.toStringAsFixed(0)} DA", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                          Text("${total.toStringAsFixed(0)} DA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // ── BLOC RÉCAPITULATIF (style ticket de caisse) ──
          Divider(color: Colors.grey.withOpacity(0.2)),
          
          // Vendeur / Caisse / Dépôt
          if (userName != null || registerName != null || warehouseName != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                spacing: 16, runSpacing: 4,
                children: [
                  if (userName != null) _infoChip(Icons.person_outline, userName, isDark),
                  if (registerName != null) _infoChip(Icons.point_of_sale, registerName, isDark),
                  if (warehouseName != null) _infoChip(Icons.warehouse_outlined, warehouseName, isDark),
                ],
              ),
            ),
            Divider(color: Colors.grey.withOpacity(0.1)),
          ],

          // Lignes financières conditionnelles
          if (totalHT > 0) _summaryRow("Total HT", "${fmt.format(totalHT)} DA", isDark),
          if (totalVat > 0) _summaryRow("TVA", "${fmt.format(totalVat)} DA", isDark),
          if (timbre > 0) _summaryRow("Timbre fiscal", "${fmt.format(timbre)} DA", isDark),
          if (discountVal > 0) _summaryRow("Remise", "-${fmt.format(discountVal)} DA", isDark, valueColor: Colors.red),
          
          Divider(color: Colors.grey.withOpacity(0.2)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("TOTAL TTC", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Text("${fmt.format(totalAmount)} DA", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          Divider(color: Colors.grey.withOpacity(0.2)),

          if (amountPaid > 0) _summaryRow("Versé", "${fmt.format(amountPaid)} DA", isDark, valueColor: Colors.green),
          if (remaining > 0.5) _summaryRow("Reste à payer", "${fmt.format(remaining)} DA", isDark, valueColor: Colors.red, bold: true),
          if (paymentType != null && paymentType.isNotEmpty)
            _summaryRow("Paiement", paymentType == 'credit' ? 'Crédit' : paymentType == 'cash' ? 'Espèces' : paymentType, isDark),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, bool isDark, {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey[600], fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: valueColor ?? (isDark ? Colors.white : Colors.black), fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
      ],
    );
  }
}
// =============================================================================
// ✏️ EDIT SALE SHEET - Modification d'un ticket existant
// =============================================================================
class _EditSaleSheet extends StatefulWidget {
  final dynamic saleId;
  final List<Map<String, dynamic>> items;
  final double originalTotal;
  final String? clientName;
  final dynamic clientId;
  final double originalTva;
  final double originalTimbre;
  final double originalDiscount;
  final double originalPaid;

  const _EditSaleSheet({
    required this.saleId,
    required this.items,
    required this.originalTotal,
    this.clientName,
    this.clientId,
    this.originalTva = 0,
    this.originalTimbre = 0,
    this.originalDiscount = 0,
    required this.originalPaid,
  });

  @override
  State<_EditSaleSheet> createState() => _EditSaleSheetState();
}

class _EditSaleSheetState extends State<_EditSaleSheet> {
  late List<Map<String, dynamic>> _items;
  late TextEditingController _paidCtrl;
  
  @override
  void initState() {
    super.initState();
    _items = widget.items.map((e) => Map<String, dynamic>.from(e)).toList();
    _paidCtrl = TextEditingController(text: widget.originalPaid.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    super.dispose();
  }

  double get _total => _items.fold(0.0, (sum, i) => sum + ((i['price'] ?? 0.0) * (i['qty'] ?? 1.0)));

  void _updateQty(int index, double newQty) {
    if (newQty <= 0) return;
    setState(() => _items[index]['qty'] = newQty);
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  // 🛠️ MODULE 6 : Édition du prix unitaire d'un article
  void _editItemPrice(int index) {
    final ctrl = TextEditingController(text: (_items[index]['price'] ?? 0.0).toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.edit, color: Colors.blue[400], size: 22),
          const SizedBox(width: 10),
          const Flexible(child: Text('Modifier le Prix', style: TextStyle(fontWeight: FontWeight.w900))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_items[index]['name'] ?? 'Article', style: TextStyle(fontSize: 13, color: Colors.grey[500]), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              decoration: InputDecoration(
                suffixText: 'DA',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blue, width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Annuler', style: TextStyle(color: Colors.grey[500]))),
          ElevatedButton(
            onPressed: () {
              final newPrice = double.tryParse(ctrl.text) ?? _items[index]['price'];
              setState(() => _items[index]['price'] = newPrice);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Valider', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _confirm() {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Le panier ne peut pas être vide."), backgroundColor: Colors.red));
      return;
    }
    
     // 🟢 RECALCUL EXACT (Évite de doubler la TVA ou le Timbre)
     double newHt = 0;
     double newTva = 0;
     for (var i in _items) {
       double pTtc = (i['price'] ?? 0.0).toDouble();
       double qty = (i['qty'] ?? 1.0).toDouble();
       double vatRate = (i['vat_percent'] ?? 0.0).toDouble();
       
       double pHt = pTtc;
       if (vatRate > 0 && widget.originalTva > 0) { // Si TVA activée
         pHt = pTtc / (1 + (vatRate / 100));
         newTva += (pTtc - pHt) * qty;
       }
       newHt += pHt * qty;
     }

     double newTotalTTC = _total; // _total est déjà le TTC calculé en live
     double newTimbre = 0;
     
     if (widget.originalTimbre > 0) {
        double baseForTimbre = newTotalTTC - widget.originalDiscount;
        if (baseForTimbre > 0) {
            double tranches = (baseForTimbre / 100).ceilToDouble();
            if (baseForTimbre <= 30000) newTimbre = tranches * 1.0;
            else if (baseForTimbre <= 100000) newTimbre = tranches * 1.5;
            else newTimbre = tranches * 2.0;
            newTimbre = newTimbre.clamp(5.0, 10000.0);
        }
     }

     double newNetTotal = newTotalTTC + newTimbre - widget.originalDiscount;
     double paid = double.tryParse(_paidCtrl.text) ?? 0;
     String pType = (newNetTotal - paid > 0.1) ? 'credit' : 'cash';

     Navigator.pop(context, {
       'sale_id': widget.saleId, 'total': newNetTotal, 'items': _items,
       'client_id': widget.clientId, 'amount_paid': paid, 'payment_type': pType,
       'note': 'Modifié depuis Mobile', 'tva': newTva, 'timbre': newTimbre,
       'discount': widget.originalDiscount, 'ht': newHt,
     });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20), // 🛠️ MODULE 1 : Padding dynamique Android
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 15),
          
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("✏️ Modifier Ticket #${widget.saleId}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                  if (widget.clientName != null)
                    Text(widget.clientName!, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
              Text("${_total.toStringAsFixed(0)} DA", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange)),
            ],
          ),
          const Divider(),

          // Items list
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final item = _items[i];
                final qty = (item['qty'] ?? 1.0).toDouble();
                final price = (item['price'] ?? 0.0).toDouble();
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      // Qty controls
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                            onPressed: () => qty > 1 ? _updateQty(i, qty - 1) : _removeItem(i),
                          ),
                          Text("${qty.toInt()}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.green),
                            onPressed: () => _updateQty(i, qty + 1),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      // Product info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'] ?? 'Article', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                            GestureDetector(
                              onTap: () => _editItemPrice(i),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text("${price.toStringAsFixed(0)} DA/u", style: TextStyle(color: Colors.blue[400], fontSize: 12, decoration: TextDecoration.underline, decorationColor: Colors.blue[400])),
                                const SizedBox(width: 4),
                                Icon(Icons.edit, size: 11, color: Colors.blue[400]),
                              ]),
                            ),
                          ],
                        ),
                      ),
                      // Line total
                      Text("${(qty * price).toStringAsFixed(0)} DA", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                      // Delete
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        onPressed: () => _removeItem(i),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const Divider(),
          
          // Original vs new total
          if ((_total - widget.originalTotal).abs() > 0.5) 
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Ancien total HT :", style: TextStyle(color: Colors.grey)),
                  Text("${widget.originalTotal.toStringAsFixed(0)} DA", style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough)),
                ],
              ),
            ),

          // 🛠️ MODULE 6 : Récapitulatif Comptable Complet
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildSummaryRow("Total HT", "${_total.toStringAsFixed(0)} DA", isDark),
                if (widget.originalTva > 0) _buildSummaryRow("TVA", "${widget.originalTva.toStringAsFixed(0)} DA", isDark),
                if (widget.originalTimbre > 0) _buildSummaryRow("Timbre", "${widget.originalTimbre.toStringAsFixed(0)} DA", isDark),
                if (widget.originalDiscount > 0) _buildSummaryRow("Remise", "-${widget.originalDiscount.toStringAsFixed(0)} DA", isDark, valueColor: Colors.red),
                Divider(color: Colors.grey.withOpacity(0.2)),
                _buildSummaryRow("Total TTC", "${(_total + widget.originalTva + widget.originalTimbre - widget.originalDiscount).toStringAsFixed(0)} DA", isDark, bold: true, valueColor: Colors.orange),
              ],
            ),
          ),
          const SizedBox(height: 8),

           const Divider(),
           Padding(
             padding: const EdgeInsets.symmetric(vertical: 10),
             child: Row(
               children: [
                 const Expanded(child: Text("Montant Versé :", style: TextStyle(fontWeight: FontWeight.bold))),
                 SizedBox(
                   width: 150,
                   child: TextField(
                     controller: _paidCtrl,
                     keyboardType: TextInputType.number,
                     textAlign: TextAlign.right,
                     style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
                     decoration: const InputDecoration(suffixText: " DA", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                   ),
                 ),
               ],
             ),
           ),
           const SizedBox(height: 10),

          // Confirm button
          SizedBox(
            width: double.infinity, height: 55,
            child: ElevatedButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.save),
              label: Text("SAUVEGARDER (${(_total + widget.originalTva + widget.originalTimbre - widget.originalDiscount).toStringAsFixed(0)} DA)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🛠️ MODULE 6 : Helper ligne de récapitulatif
  Widget _buildSummaryRow(String label, String value, bool isDark, {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey[600], fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: valueColor ?? (isDark ? Colors.white : Colors.black))),
        ],
      ),
    );
  }
}

// =============================================================================
// ✏️ EDIT PURCHASE SHEET - Modification d'un achat existant
// =============================================================================
class _EditPurchaseSheet extends StatefulWidget {
  final dynamic poId;
  final List<Map<String, dynamic>> items;
  final double originalTotal;
  final String? supplierName;
  final dynamic supplierId;
  final double originalTva;
  final double originalTimbre;
  final double originalDiscount;
  final double originalPaid;

  const _EditPurchaseSheet({
    required this.poId,
    required this.items,
    required this.originalTotal,
    this.supplierName,
    this.supplierId,
    this.originalTva = 0,
    this.originalTimbre = 0,
    this.originalDiscount = 0,
    required this.originalPaid,
  });

  @override
  State<_EditPurchaseSheet> createState() => _EditPurchaseSheetState();
}

class _EditPurchaseSheetState extends State<_EditPurchaseSheet> {
  late List<Map<String, dynamic>> _items;
  late TextEditingController _paidCtrl;
  
  @override
  void initState() {
    super.initState();
    _items = widget.items.map((e) => Map<String, dynamic>.from(e)).toList();
    _paidCtrl = TextEditingController(text: widget.originalPaid.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    super.dispose();
  }

  double get _total => _items.fold(0.0, (sum, i) => sum + ((i['price'] ?? 0.0) * (i['qty'] ?? 1.0)));

  void _updateQty(int index, double newQty) {
    if (newQty <= 0) return;
    setState(() => _items[index]['qty'] = newQty);
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  // 🛠️ MODULE 6 : Édition du prix unitaire d'un article
  void _editItemPrice(int index) {
    final ctrl = TextEditingController(text: (_items[index]['price'] ?? 0.0).toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.edit, color: Colors.blue[400], size: 22),
          const SizedBox(width: 10),
          const Flexible(child: Text('Modifier le Prix', style: TextStyle(fontWeight: FontWeight.w900))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_items[index]['name'] ?? 'Article', style: TextStyle(fontSize: 13, color: Colors.grey[500]), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              decoration: InputDecoration(
                suffixText: 'DA',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blue, width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Annuler', style: TextStyle(color: Colors.grey[500]))),
          ElevatedButton(
            onPressed: () {
              final newPrice = double.tryParse(ctrl.text) ?? _items[index]['price'];
              setState(() => _items[index]['price'] = newPrice);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Valider', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _confirm() {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La liste ne peut pas être vide."), backgroundColor: Colors.red));
      return;
    }
    
     // 🟢 RECALCUL EXACT ACHATS (Prix de base est HT)
     double newHt = _total;
     double newTva = 0;
     for (var i in _items) {
       double pCost = (i['price'] ?? 0.0).toDouble(); // Pour les achats, 'price' dans le state contient le PMP/Cout HT
       double qty = (i['qty'] ?? 1.0).toDouble();
       double vatRate = (i['vat_percent'] ?? 0.0).toDouble();
       if (vatRate > 0 && widget.originalTva > 0) {
           newTva += (pCost * qty) * (vatRate / 100);
       }
     }

     double newTimbre = 0;
     if (widget.originalTimbre > 0) {
        double baseTtc = newHt + newTva - widget.originalDiscount;
        if (baseTtc > 0) {
            double tranches = (baseTtc / 100).ceilToDouble();
            if (baseTtc <= 30000) newTimbre = tranches * 1.0;
            else if (baseTtc <= 100000) newTimbre = tranches * 1.5;
            else newTimbre = tranches * 2.0;
            newTimbre = newTimbre.clamp(5.0, 10000.0);
        }
     }

     double newNetTotal = newHt + newTva + newTimbre - widget.originalDiscount;
     double paid = double.tryParse(_paidCtrl.text) ?? 0;
     String pType = (newNetTotal - paid > 0.1) ? 'credit' : 'cash';

     Navigator.pop(context, {
       'po_id': widget.poId, 'total': newNetTotal, 'items': _items,
       'supplier_id': widget.supplierId, 'amount_paid': paid, 'payment_type': pType,
       'note': 'Modifié depuis Mobile', 'tva': newTva, 'timbre': newTimbre,
       'discount': widget.originalDiscount, 'ht': newHt,
     });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20), // 🛠️ MODULE 1 : Padding dynamique Android
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 15),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("✏️ Modifier Achat #${widget.poId}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                  if (widget.supplierName != null)
                    Text(widget.supplierName!, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
              Text("${_total.toStringAsFixed(0)} DA", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange)),
            ],
          ),
          const Divider(),

          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final item = _items[i];
                final qty = (item['qty'] ?? 1.0).toDouble();
                final price = (item['price'] ?? 0.0).toDouble();
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                            onPressed: () => qty > 1 ? _updateQty(i, qty - 1) : _removeItem(i),
                          ),
                          Text("${qty.toInt()}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.green),
                            onPressed: () => _updateQty(i, qty + 1),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'] ?? 'Article', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                            GestureDetector(
                              onTap: () => _editItemPrice(i),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text("${price.toStringAsFixed(0)} DA/u", style: TextStyle(color: Colors.blue[400], fontSize: 12, decoration: TextDecoration.underline, decorationColor: Colors.blue[400])),
                                const SizedBox(width: 4),
                                Icon(Icons.edit, size: 11, color: Colors.blue[400]),
                              ]),
                            ),
                          ],
                        ),
                      ),
                      Text("${(qty * price).toStringAsFixed(0)} DA", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        onPressed: () => _removeItem(i),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const Divider(),
          
          if ((_total - widget.originalTotal).abs() > 0.5) 
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Ancien total HT :", style: TextStyle(color: Colors.grey)),
                  Text("${widget.originalTotal.toStringAsFixed(0)} DA", style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough)),
                ],
              ),
            ),

          // 🛠️ MODULE 6 : Récapitulatif Comptable Complet
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildSummaryRow("Total HT", "${_total.toStringAsFixed(0)} DA", isDark),
                if (widget.originalTva > 0) _buildSummaryRow("TVA", "${widget.originalTva.toStringAsFixed(0)} DA", isDark),
                if (widget.originalTimbre > 0) _buildSummaryRow("Timbre", "${widget.originalTimbre.toStringAsFixed(0)} DA", isDark),
                if (widget.originalDiscount > 0) _buildSummaryRow("Remise", "-${widget.originalDiscount.toStringAsFixed(0)} DA", isDark, valueColor: Colors.red),
                Divider(color: Colors.grey.withOpacity(0.2)),
                _buildSummaryRow("Total TTC", "${(_total + widget.originalTva + widget.originalTimbre - widget.originalDiscount).toStringAsFixed(0)} DA", isDark, bold: true, valueColor: Colors.orange),
              ],
            ),
          ),
          const SizedBox(height: 8),

           const Divider(),
           Padding(
             padding: const EdgeInsets.symmetric(vertical: 10),
             child: Row(
               children: [
                 const Expanded(child: Text("Montant Versé :", style: TextStyle(fontWeight: FontWeight.bold))),
                 SizedBox(
                   width: 150,
                   child: TextField(
                     controller: _paidCtrl,
                     keyboardType: TextInputType.number,
                     textAlign: TextAlign.right,
                     style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
                     decoration: const InputDecoration(suffixText: " DA", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                   ),
                 ),
               ],
             ),
           ),
           const SizedBox(height: 10),

          SizedBox(
            width: double.infinity, height: 55,
            child: ElevatedButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.save),
              label: Text("SAUVEGARDER (${(_total + widget.originalTva + widget.originalTimbre - widget.originalDiscount).toStringAsFixed(0)} DA)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🛠️ MODULE 6 : Helper ligne de récapitulatif
  Widget _buildSummaryRow(String label, String value, bool isDark, {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey[600], fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: valueColor ?? (isDark ? Colors.white : Colors.black))),
        ],
      ),
    );
  }
}
