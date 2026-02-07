import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import 'client_details_page.dart'; // Pour utiliser TransactionDetailSheet et PaymentModal

class SupplierDetailsPage extends StatefulWidget {
  final Map<String, dynamic> summary;
  const SupplierDetailsPage({super.key, required this.summary});

  @override
  State<SupplierDetailsPage> createState() => _SupplierDetailsPageState();
}

class _SupplierDetailsPageState extends State<SupplierDetailsPage> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;
  
  Map<String, dynamic> _fullData = {};
  bool _isLoading = true;
  double _currentBalance = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fullData = widget.summary;
    _currentBalance = double.tryParse(widget.summary['balance'].toString()) ?? 0;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final freshData = await _api.getTierDetails('supplier', widget.summary['id']);
      if (mounted) {
        setState(() {
          // On garde les paiements ajoutés localement s'ils existent (astuce avancée)
          // Pour faire simple ici, on remplace tout par le serveur
          _fullData = { ...widget.summary, ...freshData };
          _currentBalance = double.tryParse(_fullData['balance'].toString()) ?? _currentBalance;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showTransactionDetails(Map<String, dynamic> po) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TransactionDetailSheet(api: _api, data: po, isSale: false),
    );
  }

  // --- MODIFICATION ICI : PAIEMENT OPTIMISTE ---
  void _showPaymentModal() {
    final name = _fullData['name'] ?? 'Fournisseur';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PaymentModal(
        tierName: name,
        color: Colors.orange,
        onConfirm: (amount, note) {
          // 1. Fermer la fenêtre tout de suite
          Navigator.pop(context);

          // 2. Lancer l'envoi en arrière-plan (Optimiste)
          _api.sendPartnerPaymentOptimistic(
            partnerId: widget.summary['id'],
            amount: amount,
            type: 'SUPPLIER',
            note: note
          );

          // 3. Mettre à jour l'interface INSTANTANÉMENT
          setState(() {
            // A. Mettre à jour le solde (Dette diminue quand on paie)
            _currentBalance -= amount; 

            // B. Créer un faux objet paiement pour l'affichage
            final newPayment = {
              'id': 'TEMP', // ID temporaire
              'date': DateTime.now().toIso8601String(),
              'amount': amount,
              'method': 'Espèce',
              'note': note,
              'is_local': true // Marqueur pour l'affichage
            };

            // C. L'ajouter en haut de la liste des paiements
            List currentPayments = List.from(_fullData['last_payments'] ?? []);
            currentPayments.insert(0, newPayment);
            _fullData['last_payments'] = currentPayments;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Paiement enregistré !"), backgroundColor: Colors.green, duration: Duration(seconds: 1))
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final purchases = (_fullData['last_sales'] as List?) ?? [];
    final payments = (_fullData['last_payments'] as List?) ?? [];
    final safeName = _fullData['name'] ?? 'Fournisseur';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text("Fiche Fournisseur", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Header Card Orange
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Text(safeName.isNotEmpty ? safeName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(safeName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(_fullData['phone'] ?? 'Sans numéro', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("Dette", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(_currentBalance),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                  ],
                )
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            dividerColor: Colors.transparent,
            tabs: const [ Tab(text: "Historique Achats"), Tab(text: "Paiements") ],
          ),

          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.orange))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // ACHATS
                    ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: purchases.length,
                      itemBuilder: (ctx, i) {
                        final p = purchases[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            onTap: () => _showTransactionDetails(p),
                            leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
                                child: const Icon(FontAwesomeIcons.truck, color: Colors.orange, size: 18),
                            ),
                            title: Text("Bon #${p['number'] ?? p['id']}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                            subtitle: Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(p['date']))),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                          ),
                        );
                      },
                    ),
                    // PAIEMENTS SORTANTS
                    ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: payments.length,
                      itemBuilder: (ctx, i) {
                        final pay = payments[i];
                        final isLocal = pay['is_local'] == true; // Vérifie si c'est un ajout récent

                        return ListTile(
                            leading: isLocal 
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                              : const Icon(Icons.remove_circle, color: Colors.red),
                            title: Text(
                              isLocal ? "Paiement (En cours...)" : "Paiement Sortant", 
                              style: TextStyle(fontWeight: FontWeight.bold, fontStyle: isLocal ? FontStyle.italic : FontStyle.normal)
                            ),
                            subtitle: Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(pay['date']))),
                            trailing: Text("-${pay['amount']} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        );
                      },
                    ),
                  ],
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showPaymentModal,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.remove, color: Colors.white),
        label: const Text("Paiement", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}