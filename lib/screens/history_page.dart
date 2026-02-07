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

  const HistoryPage({super.key, this.onBack});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _api = ApiService();
  StreamSubscription? _syncSubscription;
  
  bool _isLoading = true;
  List<dynamic> _sales = [];
  List<dynamic> _purchases = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // 1. Chargement initial
    _loadHistory();

    // 2. Démarrage Auto-Sync et écoute
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
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _api.getSalesList(limit: 50),
        _api.getPurchasesList(limit: 50)
      ]);

      if (mounted) {
        setState(() {
          _sales = results[0];
          _purchases = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !isSilent) setState(() => _isLoading = false);
    }
  }

  void _showDetailSheet(Map<String, dynamic> data, bool isSale) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => HistoryDetailSheet(api: _api, data: data, isSale: isSale),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      body: Column(
        children: [
          // --- HEADER ---
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C23) : Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black),
                      onPressed: widget.onBack ?? () => Navigator.pop(context),
                    ),
                    Text("Historique", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    const SizedBox(width: 40, child: Icon(Icons.cloud_sync, size: 18, color: Colors.grey)), 
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 50,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C35) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(21),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    tabs: const [Tab(text: "Ventes"), Tab(text: "Achats")],
                  ),
                ),
              ],
            ),
          ),

          // --- LISTES ---
          Expanded(
            child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_sales, isDark, true),
                  _buildList(_purchases, isDark, false),
                ],
              ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<dynamic> items, bool isDark, bool isSale) {
    if (items.isEmpty) return const Center(child: Text("Historique vide"));

    return RefreshIndicator(
      onRefresh: () => _loadHistory(isSilent: false),
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          final amount = double.tryParse(item['total_amount']?.toString() ?? '0') ?? 0;
          final dateStr = item['date'] != null 
              ? DateFormat('dd/MM HH:mm').format(DateTime.parse(item['date'])) 
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${amount.toStringAsFixed(0)} DA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSale ? AppColors.primary : Colors.orange)),
                        const SizedBox(height: 5),
                        // Petit bouton PDF rapide
                        InkWell(
                          onTap: () => _printTransaction(context, item['id'], isSale, 'Ticket'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
                            child: const Icon(FontAwesomeIcons.filePdf, size: 14, color: Colors.redAccent),
                          ),
                        )
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

  Future<void> _printTransaction(BuildContext context, dynamic id, bool isSale, String format) async {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      try {
        await _api.printLocalTransaction(id, isSale, format);
      } finally {
        if (context.mounted) Navigator.pop(context);
      }
  }
}

// ==========================================
// MODAL DÉTAIL COMPLET (CORRIGÉ 0 DA)
// ==========================================
class HistoryDetailSheet extends StatelessWidget {
  final ApiService api;
  final Map<String, dynamic> data;
  final bool isSale;

  const HistoryDetailSheet({super.key, required this.api, required this.data, required this.isSale});

  // Fonction pour charger les items
  Future<List<dynamic>> _loadItems() async {
    // 1. Si les items sont déjà présents dans les données locales (JSON ou Liste)
    if (data['items'] != null) {
        if (data['items'] is String) {
            try { return json.decode(data['items']); } catch(e) { return []; }
        }
        if (data['items'] is List) {
            return data['items'];
        }
    }
    // 2. Sinon, on les charge depuis l'API
    return isSale ? api.getSaleItems(data['id']) : api.getPurchaseItems(data['id']);
  }

  // Fonction d'impression
  Future<void> _handlePrint(BuildContext context, String format) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E2C) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text("Impression $format...", style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );

    try {
      await api.printLocalTransaction(data['id'], isSale, format);
    } catch (e) {
      debugPrint("Erreur impression: $e");
    } finally {
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isSale ? "Ticket #${data['invoice_number'] ?? data['id']}" : "Bon Achat #${data['number'] ?? data['id']}";
    final name = isSale ? (data['client_name'] ?? 'Client') : (data['supplier_name'] ?? 'Fournisseur');

    return Container(
      height: MediaQuery.of(context).size.height * 0.80,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          // --- HEADER ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                  Text(name, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(),
          
          // --- LISTE ARTICLES ---
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
                    
                    // --- LOGIQUE DE CALCUL ROBUSTE (CORRECTION 0 DA) ---
                    final qty = double.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '0') ?? 0;
                    
                    // On cherche le prix partout
                    double price = double.tryParse(
                        item['price']?.toString() ?? 
                        item['unit_price']?.toString() ?? 
                        item['sale_price']?.toString() ?? // Souvent c'est lui qui manque
                        item['cost']?.toString() ?? 
                        '0'
                    ) ?? 0;

                    // On cherche le total partout
                    double total = double.tryParse(
                        item['total']?.toString() ?? 
                        item['total_line']?.toString() ?? 
                        item['sub_total']?.toString() ?? 
                        '0'
                    ) ?? 0;

                    // AUTO-CORRECTION : Si Total est présent mais Prix est 0 -> On déduit le prix
                    if (price == 0 && total > 0 && qty > 0) {
                        price = total / qty;
                    }

                    // AUTO-CORRECTION : Si Prix est présent mais Total est 0 -> On calcule le total
                    if (total == 0 && qty > 0 && price > 0) {
                        total = qty * price;
                    }
                    // ----------------------------------------------------

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 35, height: 35,
                            alignment: Alignment.center,
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
          
          const Divider(),
          const SizedBox(height: 10),

          // --- TOTAL ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text("${data['total_amount']} DA", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isSale ? AppColors.success : Colors.orange)),
            ],
          ),

          const SizedBox(height: 20),

          // --- BOUTONS D'IMPRESSION ---
          Row(
            children: [
              Expanded(
                child: _buildPrintBtn(context, "Ticket", FontAwesomeIcons.receipt, Colors.teal, 
                  () => _handlePrint(context, 'Ticket')),
              ),
              const SizedBox(width: 10),
              
              Expanded(
                child: _buildPrintBtn(context, "A5", FontAwesomeIcons.noteSticky, Colors.blueAccent, 
                  () => _handlePrint(context, 'A5')),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: _buildPrintBtn(context, "A4", FontAwesomeIcons.filePdf, Colors.redAccent, 
                  () => _handlePrint(context, 'A4')),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPrintBtn(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withOpacity(0.3))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}