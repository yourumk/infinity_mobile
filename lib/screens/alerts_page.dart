// DANS alerts_page.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class AlertsPage extends StatefulWidget {
  final String type; // rupture, stock, expiry, suggestion
  final String title;
  final VoidCallback? onBack;

  const AlertsPage({
    super.key, 
    required this.type, 
    required this.title,
    this.onBack,
  });

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;
  
  // Listes locales calculées
  List<dynamic> _ruptures = []; 
  List<dynamic> _lowStock = []; 
  List<dynamic> _expiry = [];   
  List<dynamic> _suggestions = []; 
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    if (widget.type == 'expiry') _tabController.index = 2;
    else if (widget.type == 'stock') _tabController.index = 1;
    else if (widget.type == 'rupture') _tabController.index = 0;
    
    _calculateLocalAlerts();
  }

  // C'EST ICI QUE TOUT CHANGE : Calcul local
  Future<void> _calculateLocalAlerts() async {
    setState(() => _isLoading = true);
    try {
   final catalog = await _api.getMobileProductCatalog();
final List<dynamic> allProducts = catalog['products'] ?? [];

      List<dynamic> ruptures = [];
      List<dynamic> lowStock = [];
      List<dynamic> expiry = [];
      List<dynamic> suggestions = [];

      final now = DateTime.now();

      for (var p in allProducts) {
        final stock = double.tryParse(p['stock'].toString()) ?? 0.0;
        final minStock = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5.0;
        
        // A. Rupture
        if (stock <= 0) {
          ruptures.add(p);
        }
        // B. Stock Faible (mais positif)
        else if (stock <= minStock) {
          lowStock.add(p);
        }

        // C. Péremption
        if (p['expiration_date'] != null && p['expiration_date'] != '') {
          try {
            final expDate = DateTime.parse(p['expiration_date']);
            final diff = expDate.difference(now).inDays;
            
            // Si périme dans moins de 180 jours (6 mois)
            if (diff <= 180) {
              // On crée une copie pour ajouter 'days_left' sans toucher l'original
              Map<String, dynamic> expItem = Map.from(p);
              expItem['days_left'] = diff;
              expiry.add(expItem);
            }
          } catch (e) {}
        }
      }

      // Tri des listes
      expiry.sort((a, b) => (a['days_left'] as int).compareTo(b['days_left'] as int));
      lowStock.sort((a, b) => (double.parse(a['stock'].toString())).compareTo(double.parse(b['stock'].toString())));

      if (mounted) {
        setState(() {
          _ruptures = ruptures;
          _lowStock = lowStock;
          _expiry = expiry;
          _suggestions = []; // Suggestion nécessite des calculs de vente complexes, on peut le laisser vide ou le garder via API si besoin
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erreur Calcul Local: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      body: Stack(
        children: [
          // Effet de fond
          Positioned(
            top: -100, right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(width: 300, height: 300, decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.15), shape: BoxShape.circle)),
            ),
          ),

          Column(
            children: [
              // HEADER
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(15, 50, 15, 15),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C23).withOpacity(0.8) : Colors.white.withOpacity(0.8),
                      border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black),
                              onPressed: widget.onBack ?? () => Navigator.pop(context),
                            ),
                            const Expanded(child: Text("Centre d'Alertes (Local)", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
                            const SizedBox(width: 40),
                          ],
                        ),
                        const SizedBox(height: 15),
                        
                        Container(
                          height: 45,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : Colors.grey[200],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            indicator: BoxDecoration(
                              color: isDark ? const Color(0xFF2C2C35) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]
                            ),
                            labelColor: isDark ? Colors.white : Colors.black,
                            unselectedLabelColor: Colors.grey,
                            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            dividerColor: Colors.transparent,
                            tabs: [
                              Tab(text: "⛔ Ruptures (${_ruptures.length})"),
                              Tab(text: "⚠️ Faibles (${_lowStock.length})"),
                              Tab(text: "📅 Péremption (${_expiry.length})"),
                              const Tab(text: "🧠 Suggestions"),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // CONTENU
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildList(_ruptures, 'rupture', isDark),
                          _buildList(_lowStock, 'stock', isDark),
                          _buildList(_expiry, 'expiry', isDark),
                          const Center(child: Text("Suggestions IA (Bientôt)")),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<dynamic> items, String type, bool isDark) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(type == 'rupture' ? FontAwesomeIcons.faceSmile : FontAwesomeIcons.circleCheck, size: 60, color: Colors.grey.withOpacity(0.3)),
            const SizedBox(height: 15),
            const Text("Rien à signaler !", style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        Color color = Colors.blueAccent;
        IconData icon = FontAwesomeIcons.circleInfo;
        String subtitle = "";
        String badgeText = "";

        if (type == 'rupture') {
          color = Colors.red;
          icon = FontAwesomeIcons.ban;
          subtitle = "Stock Actuel : ${item['stock']}";
          badgeText = "ÉPUISÉ";
        } else if (type == 'stock') {
          color = Colors.orange;
          icon = FontAwesomeIcons.triangleExclamation;
          subtitle = "Stock : ${item['stock']}";
          badgeText = "Min: ${item['min_stock']}";
        } else if (type == 'expiry') {
          color = Colors.purple;
          icon = FontAwesomeIcons.clock;
          final days = item['days_left'] ?? 0;
          subtitle = "Date: ${item['expiration_date']}";
          badgeText = days < 0 ? "Expiré !" : "${days}j restants";
          if (days < 0) color = Colors.redAccent;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            isDark: isDark,
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            border: Border.all(color: color.withOpacity(0.3)),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: Text(badgeText, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}