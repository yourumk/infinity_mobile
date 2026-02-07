import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart'; // Assurez-vous que ce fichier existe (couleurs, etc.)
import '../services/api_service.dart';

// --- PAGE DÉTAIL CLIENT ---
class ClientDetailsPage extends StatefulWidget {
  final Map<String, dynamic> summary;
  const ClientDetailsPage({super.key, required this.summary});

  @override
  State<ClientDetailsPage> createState() => _ClientDetailsPageState();
}

class _ClientDetailsPageState extends State<ClientDetailsPage> with SingleTickerProviderStateMixin {
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
    setState(() => _isLoading = true);
    try {
      final freshData = await _api.getTierDetails('client', widget.summary['id']);
      if (mounted) {
        setState(() {
          _fullData = { ...widget.summary, ...freshData };
          _currentBalance = double.tryParse(_fullData['balance'].toString()) ?? _currentBalance;
          _isLoading = false;
        });
      }
    } catch (e) {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  // Ouvre le détail de la facture avec les options d'impression
  void _showTransactionDetails(Map<String, dynamic> sale) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TransactionDetailSheet(api: _api, data: sale, isSale: true),
    );
  }

// Dans ClientDetailsPage

  void _showPaymentModal() {
    final name = _fullData['name'] ?? 'Client';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PaymentModal(
        tierName: name,
        onConfirm: (amount, note) {
          // 1. Fermer tout de suite
          Navigator.pop(context);

          // 2. Envoi Optimiste (instantané)
          _api.sendPartnerPaymentOptimistic(
            partnerId: widget.summary['id'],
            amount: amount,
            type: 'CLIENT', // C'est la seule différence avec SupplierDetailsPage
            note: note
          );

          // 3. Mise à jour Interface Locale
          setState(() {
            _currentBalance -= amount; // La dette diminue

            // Ajout visuel du paiement
            final newPayment = {
               'id': 'TEMP',
               'date': DateTime.now().toIso8601String(),
               'amount': amount,
               'method': 'Espèce',
               'note': note,
               'is_local': true
            };
            
            List currentPayments = List.from(_fullData['last_payments'] ?? []);
            currentPayments.insert(0, newPayment);
            _fullData['last_payments'] = currentPayments;
          });

          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Paiement enregistré !"), backgroundColor: Colors.green));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sales = (_fullData['last_sales'] as List?) ?? [];
    final payments = (_fullData['last_payments'] as List?) ?? [];
    final safeName = _fullData['name'] ?? 'Client Inconnu';
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text("Fiche Client", style: TextStyle(fontWeight: FontWeight.bold)),
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
          // --- CARTE HEADER (INFO & SOLDE) ---
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient, // Définir dans constants.dart ou utiliser Colors.blue
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Text(safeName.isNotEmpty ? safeName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
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
                    const Text("Solde", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(_currentBalance),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                  ],
                )
              ],
            ),
          ),

          // --- ONGLETS ---
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.blue,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            dividerColor: Colors.transparent,
            tabs: const [ Tab(text: "Historique Ventes"), Tab(text: "Paiements") ],
          ),

          // --- CONTENU ---
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // LISTE DES VENTES
 ListView.builder(
  padding: const EdgeInsets.all(20),
  itemCount: sales.length,
  itemBuilder: (ctx, i) {
    final s = sales[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        onTap: () => _showTransactionDetails(s),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(FontAwesomeIcons.bagShopping, color: Colors.blue, size: 18),
        ),
        title: Text("Vente #${s['invoice_number'] ?? s['id']}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
        subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(s['date']))),
        
        // --- BOUTON PDF AVEC CHARGEMENT ---
        trailing: IconButton(
          icon: const Icon(FontAwesomeIcons.filePdf, size: 18, color: Colors.redAccent),
          onPressed: () async {
            // 1. Afficher fenêtre de chargement
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => const Dialog(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 20),
                      Text("Génération PDF..."),
                    ],
                  ),
                ),
              ),
            );

            try {
              // 2. Lancer l'impression A4
              await _api.printLocalTransaction(s['id'], true, 'A4');
            } catch (e) {
              debugPrint("Erreur PDF: $e");
            } finally {
              // 3. Fermer la fenêtre
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
      ),
    );
  },
),
                    ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: payments.length,
                      itemBuilder: (ctx, i) {
                        final p = payments[i];
                        return ListTile(
                            leading: const Icon(Icons.check_circle, color: Colors.green),
                            title: const Text("Versement reçu", style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(p['date']))),
                            trailing: Text("+${p['amount']} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
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
        backgroundColor: Colors.blue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Versement", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ==============================================================================
// WIDGETS PARTAGÉS (A utiliser aussi dans supplier_details_page.dart)
// ==============================================================================

// 1. MODALE DÉTAIL TRANSACTION (AVEC LES 3 BOUTONS D'IMPRESSION)
class TransactionDetailSheet extends StatelessWidget {
  final ApiService api;
  final Map<String, dynamic> data;
  final bool isSale; // true = Vente, false = Achat

  const TransactionDetailSheet({super.key, required this.api, required this.data, required this.isSale});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isSale ? "Facture #${data['invoice_number'] ?? data['id']}" : "Bon #${data['number'] ?? data['id']}";
    final color = isSale ? Colors.blue : Colors.orange;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, 
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(),
          const Text("Détail des articles", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          
          // Liste Articles
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: isSale ? api.getSaleItems(data['id']) : api.getPurchaseItems(data['id']),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Détails non disponibles."));
                
                final items = snapshot.data!;
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (c,i) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final item = items[i];
                    final qty = double.tryParse(item['qty'].toString()) ?? 0;
                    final price = double.tryParse(isSale ? item['price'].toString() : item['cost'].toString()) ?? 0;
                    final total = qty * price;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text("${qty % 1 == 0 ? qty.toInt() : qty}x", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                      ),
                      title: Text(item['name'] ?? 'Article', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                      trailing: Text("${NumberFormat.currency(locale: 'fr_DZ', symbol: '', decimalDigits: 0).format(total)} DA", 
                        style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    );
                  },
                );
              },
            ),
          ),
          
          const Divider(),
          
          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL TTC", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("${data['total_amount']} DA", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            ],
          ),
          
          const SizedBox(height: 20),
          const Text("Générer Document (PDF) :", style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),

          // --- BOUTONS D'IMPRESSION (NOUVEAU) ---
          Row(
            children: [
              Expanded(child: _buildPrintBtn(context, "A4", FontAwesomeIcons.filePdf, Colors.redAccent)),
              const SizedBox(width: 10),
              Expanded(child: _buildPrintBtn(context, "A5", FontAwesomeIcons.fileLines, Colors.blueAccent)),
              const SizedBox(width: 10),
              Expanded(child: _buildPrintBtn(context, "Ticket", FontAwesomeIcons.receipt, Colors.grey[800]!)),
            ],
          )
        ],
      ),
    );
  }

  // Widget Bouton Print
  Widget _buildPrintBtn(BuildContext context, String format, IconData icon, Color bg) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        onPressed: () async {
          Navigator.pop(context); // Fermer la fenetre
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Téléchargement $format..."), duration: const Duration(seconds: 1)));
          
          // APPEL DE L'API POUR TÉLÉCHARGER
          await api.printLocalTransaction(data['id'], true, format);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 4),
            Text(format, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// 2. MODALE PAIEMENT (Simple)
class PaymentModal extends StatefulWidget {
  final String tierName;
  final Function(double, String) onConfirm;
  final Color color;
  const PaymentModal({super.key, required this.tierName, required this.onConfirm, this.color = Colors.blueAccent});
  @override
  State<PaymentModal> createState() => _PaymentModalState();
}
class _PaymentModalState extends State<PaymentModal> {
  final TextEditingController _amountCtrl = TextEditingController();
  String _note = "";
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.fromLTRB(25, 25, 25, MediaQuery.of(context).viewInsets.bottom + 25),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Nouveau Versement", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 20),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(color: widget.color, fontSize: 30, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(hintText: "0", suffixText: "DA", border: InputBorder.none),
          ),
          const Divider(),
          TextField(
            onChanged: (v) => _note = v,
            decoration: const InputDecoration(hintText: "Note (Optionnel)...", border: InputBorder.none),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(_amountCtrl.text);
                if (amount != null && amount > 0) widget.onConfirm(amount, _note);
              },
              style: ElevatedButton.styleFrom(backgroundColor: widget.color),
              child: const Text("CONFIRMER", style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}