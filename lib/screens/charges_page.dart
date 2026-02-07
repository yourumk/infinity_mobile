import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/quick_action_sheet.dart'; 

class ChargesPage extends StatefulWidget {
  const ChargesPage({super.key});

  @override
  State<ChargesPage> createState() => _ChargesPageState();
}

class _ChargesPageState extends State<ChargesPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  
  // Abonnement pour écouter les mises à jour (Serveur ou Locales)
  StreamSubscription? _syncSubscription;

  List<dynamic> _allCharges = []; 
  List<dynamic> _filteredCharges = []; 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCharges();

    // 1. Démarrer le moteur de synchro (sécurité si pas démarré ailleurs)
    _api.startAutoSync(); 
    
    // 2. Écouter les changements (Dès qu'on ajoute un truc en local ou qu'on reçoit du serveur)
    _syncSubscription = _api.onDataUpdated.listen((_) {
      if (mounted) {
        // On recharge la liste sans afficher le rond de chargement (pour que ce soit fluide)
        _loadCharges(isSilent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Charge les données (Serveur + File d'attente locale)
  Future<void> _loadCharges({bool isSilent = false}) async {
    // Si ce n'est pas un rafraîchissement silencieux, on montre le loader
    if (!isSilent && _allCharges.isEmpty) {
        setState(() => _isLoading = true);
    }
    
    // IMPORTANT : On utilise la version "WithQueue" pour voir les items en attente
    final data = await _api.getChargesWithQueue();
    
    if (mounted) {
      setState(() { 
        _allCharges = data; 
        
        // Appliquer le filtre de recherche si nécessaire
        if (_searchController.text.isNotEmpty) {
           _filterCharges(_searchController.text);
        } else {
           _filteredCharges = data;
        }
        
        _isLoading = false; 
      });
    }
  }

  void _filterCharges(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCharges = _allCharges;
      } else {
        _filteredCharges = _allCharges.where((item) {
          final cat = (item['category'] ?? '').toString().toLowerCase();
          final label = (item['label'] ?? item['note'] ?? '').toString().toLowerCase();
          final amount = (item['amount'] ?? '').toString();
          final search = query.toLowerCase();
          return cat.contains(search) || label.contains(search) || amount.contains(search);
        }).toList();
      }
    });
  }

// Dans charges_page.dart

  void _openAddCharge() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const QuickActionSheet(type: 'CHARGE'),
    );

    if (result != null && result is Map) {
      // 1. Appel Optimiste (Instantané)
      _api.addChargeOptimistic(
        result['label'] ?? 'Dépense', 
        double.tryParse(result['amount'].toString()) ?? 0.0, 
        result['category'] ?? 'Divers'
      );
      
      // 2. Feedback immédiat
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Dépense ajoutée !"), backgroundColor: Colors.green, duration: Duration(milliseconds: 800))
      );

      // Pas besoin de _loadCharges() car addChargeOptimistic déclenche le stream onDataUpdated
      // qui va appeler _loadCharges automatiquement grâce au listener dans initState.
    } 
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false, 
        child: Column(
          children: [
            // --- HEADER ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("FINANCES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent, letterSpacing: 1.5)),
                          Text(
                            "Dépenses", 
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)
                          ),
                        ],
                      ),
                      // BOUTON D'AJOUT
                      GestureDetector(
                        onTap: _openAddCharge,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Colors.redAccent, Colors.red]), 
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))
                            ]
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),

                  // BARRE DE RECHERCHE
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!)
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _filterCharges,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        hintText: "Rechercher une dépense...",
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // LISTE DES CHARGES
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Colors.red))
                : _filteredCharges.isEmpty 
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(FontAwesomeIcons.fileInvoiceDollar, size: 50, color: Colors.grey.withOpacity(0.3)),
                          const SizedBox(height: 10),
                          const Text("Aucune dépense trouvée", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), 
                      itemCount: _filteredCharges.length,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (ctx, i) {
                        final item = _filteredCharges[i];
                        
                        // --- DÉTECTION DU STATUS "EN ATTENTE" ---
                        // L'ApiService ajoute 'is_pending': true pour les items locaux
                        final bool isPending = item['is_pending'] == true;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            isDark: isDark,
                            padding: const EdgeInsets.all(15),
                            borderRadius: 15,
                            child: Row(
                              children: [
                                // 1. ICÔNE (Change si en attente)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    // Orange si en attente, Rouge si validé
                                    color: isPending ? Colors.orange.withOpacity(0.1) : Colors.red.withOpacity(0.1), 
                                    borderRadius: BorderRadius.circular(12)
                                  ),
                                  child: Icon(
                                    isPending ? FontAwesomeIcons.clock : FontAwesomeIcons.moneyBillTransfer, 
                                    color: isPending ? Colors.orange : Colors.red, 
                                    size: 18
                                  ),
                                ),
                                const SizedBox(width: 15),
                                
                                // 2. TEXTES
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['category'] ?? 'Divers', 
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black),
                                        maxLines: 1, overflow: TextOverflow.ellipsis 
                                      ),
                                      // Petit texte d'info si en attente
                                      isPending 
                                      ? const Text("En attente de connexion...", style: TextStyle(color: Colors.orange, fontSize: 11, fontStyle: FontStyle.italic))
                                      : Text(
                                          item['label'] ?? item['note'] ?? '-', 
                                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                                          maxLines: 1, overflow: TextOverflow.ellipsis 
                                        ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 10), 

                                // 3. MONTANT + DATE
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "-${item['amount']} DA", 
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900, 
                                        color: isPending ? Colors.grey : Colors.red, // Gris si pas confirmé
                                        fontSize: 16
                                      )
                                    ),
                                    Text(
                                      DateFormat('dd/MM HH:mm').format(DateTime.parse(item['date'] ?? DateTime.now().toIso8601String())), 
                                      style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}