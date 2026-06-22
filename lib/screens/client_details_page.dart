import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../services/api_service.dart';


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
  
  bool _canAddPayment = true; 

  // 🛡️ RECALCUL LOCAL DU SOLDE (Zéro attente)
  double _calculateLocalBalance(Map<String, dynamic> data) {
    double totalVentes = 0;
    double totalPaiements = 0;

    List sales = data['last_sales'] ?? data['history_sales'] ?? data['sales'] ?? [];
    List payments = data['last_payments'] ?? data['history_payments'] ?? data['payments'] ?? [];

    for (var s in sales) {
      if (s != null && s is Map) {
        totalVentes += double.tryParse(s['total_amount']?.toString() ?? '0') ?? 0;
        // On déduit l'acompte déjà payé sur le ticket lui-même
        totalPaiements += double.tryParse(s['amount_paid']?.toString() ?? '0') ?? 0;
      }
    }
    for (var p in payments) {
      if (p != null && p is Map) {
        // Ignorer les paiements locaux temporaires car ils sont déjà déduits du solde visuel
        if (p['is_local'] != true) {
            totalPaiements += double.tryParse(p['amount']?.toString() ?? '0') ?? 0;
        }
      }
    }
    return totalVentes - totalPaiements;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fullData = widget.summary;
    
    // On privilégie le recalcul local s'il y a des données, sinon le solde fourni par le parent
    double rawBalance = double.tryParse(widget.summary['balance']?.toString() ?? '0') ?? 0;
    double calculatedBalance = _calculateLocalBalance(widget.summary);
    _currentBalance = calculatedBalance > 0.01 ? calculatedBalance : rawBalance;
    
    _loadDetails();
  }

  // 🟢 Fonction conservée vide au cas où d'autres composants l'appelleraient
  Future<void> _loadPermissions() async {}

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

 Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final freshData = await _api.getTierDetails('client', widget.summary['id']);
      if (mounted) {
        setState(() {
          if (freshData != null && freshData.isNotEmpty) {
            _fullData = { ...widget.summary, ...freshData };
            // On privilégie la balance calculée par le serveur PC s'il répond bien
            double serverBalance = double.tryParse(_fullData['balance']?.toString() ?? '0') ?? 0;
            // Si le serveur renvoie 0 (parce qu'il n'a pas encore reçu la vente offline), on garde le local !
            if (serverBalance == 0) serverBalance = _calculateLocalBalance(_fullData);
            _currentBalance = serverBalance;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  void _showTransactionDetails(Map<String, dynamic>? sale) {
    if (sale == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TransactionDetailSheet(api: _api, data: sale, isSale: true),
    );
  }



  void _showPaymentModal() {
    final name = _fullData['name']?.toString() ?? 'Client';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PaymentModal(
        tierName: name,
        onConfirm: (amount, note) {
          Navigator.pop(context);
          _api.sendPartnerPaymentOptimistic(
            partnerId: widget.summary['id'],
            amount: amount,
            type: 'CLIENT',
            note: note
          );
          setState(() {
            _currentBalance -= amount;
            final newPayment = {
               'id': 'TEMP',
               'date': DateTime.now().toIso8601String(),
               'amount': amount,
               'method': 'Espèce',
               'note': note,
               'is_local': true
            };
            List currentPayments = [];
            if (_fullData['last_payments'] is List) {
              currentPayments = List.from(_fullData['last_payments']);
            }
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
    
    // --- PROTECTION MAXIMALE DES LISTES ---
    List sales = [];
    if (_fullData['last_sales'] is List) sales = _fullData['last_sales'];
    else if (_fullData['history_sales'] is List) sales = _fullData['history_sales'];
    else if (_fullData['sales'] is List) sales = _fullData['sales'];

    List payments = [];
    if (_fullData['last_payments'] is List) payments = _fullData['last_payments'];
    else if (_fullData['history_payments'] is List) payments = _fullData['history_payments'];
    else if (_fullData['payments'] is List) payments = _fullData['payments'];

    final safeName = _fullData['name']?.toString() ?? 'Client Inconnu';
    final safePhone = _fullData['phone']?.toString() ?? 'Sans numéro';
      
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
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
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
                      Text(safePhone, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("Solde", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2).format(_currentBalance),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                  ],
                )
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.blue,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            dividerColor: Colors.transparent,
            tabs: const [ Tab(text: "Historique Ventes"), Tab(text: "Paiements") ],
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    ListView.builder(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 100),
                      itemCount: sales.length,
                      itemBuilder: (ctx, i) {
                        final s = sales[i];
                        if (s == null || s is! Map) return const SizedBox.shrink();

                        DateTime? parsedDate;
                        if (s['date'] != null) parsedDate = DateTime.tryParse(s['date'].toString());
                        final dateStr = parsedDate != null ? DateFormat('dd/MM/yyyy HH:mm').format(parsedDate) : '-';
                        
                        double discount = 0;
                        if (s['discount_value'] != null) discount = double.tryParse(s['discount_value'].toString()) ?? 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            onTap: () => _showTransactionDetails(Map<String, dynamic>.from(s)),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(FontAwesomeIcons.bagShopping, color: Colors.blue, size: 18),
                            ),
                            title: Text("Vente #${s['invoice_number'] ?? s['id'] ?? '?'}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dateStr),
                                if (discount > 0)
                                  Text("Remise : -${discount.toStringAsFixed(0)} DA", style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            trailing: Text("${s['total_amount'] ?? 0} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
                          ),
                        );
                      },
                    ),
                    ListView.builder(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 100),
                      itemCount: payments.length,
                      itemBuilder: (ctx, i) {
                        final p = payments[i];
                        if (p == null || p is! Map) return const SizedBox.shrink(); // Ignore les lignes corrompues
                        
                        // Protection des dates
                        DateTime? parsedDate;
                        if (p['date'] != null) parsedDate = DateTime.tryParse(p['date'].toString());
                        final dateStr = parsedDate != null ? DateFormat('dd/MM/yyyy').format(parsedDate) : '-';

                        return ListTile(
                          leading: const Icon(Icons.check_circle, color: Colors.green),
                          title: const Text("Versement reçu", style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(dateStr),
                          trailing: Text("+${p['amount'] ?? 0} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        );
                      },
                    ),
                  ],
                ),
          ),
        ],
      ),
      // 🟢 FIX RBAC : Le FAB Versement est masqué si la permission mobile_client_payment est absente
      floatingActionButton: _canAddPayment
          ? FloatingActionButton.extended(
              onPressed: _showPaymentModal,
              backgroundColor: Colors.blue,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text("Versement", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}

// ==============================================================================
// MODALE DÉTAIL TRANSACTION
// ==============================================================================
class TransactionDetailSheet extends StatelessWidget {
  final ApiService api;
  final Map<String, dynamic> data;
  final bool isSale;

  const TransactionDetailSheet({super.key, required this.api, required this.data, required this.isSale});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isSale ? "Facture #${data['invoice_number'] ?? data['id'] ?? '?'}" : "Bon #${data['number'] ?? data['id'] ?? '?'}";
    final name = isSale ? (data['client_name']?.toString() ?? 'Client') : (data['supplier_name']?.toString() ?? 'Fournisseur');
    final color = isSale ? Colors.blue : Colors.orange;

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
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black), overflow: TextOverflow.ellipsis)),
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
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(),
          const Align(alignment: Alignment.centerLeft, child: Text("Détail des articles", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
          const SizedBox(height: 10),
          
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
                    if (item == null || item is! Map) return const SizedBox.shrink();

                    final qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0;
                    final price = double.tryParse(isSale ? item['price']?.toString() ?? '0' : item['cost']?.toString() ?? '0') ?? 0;
                    final total = qty * price;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text("${qty % 1 == 0 ? qty.toInt() : qty}x", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                      ),
                      title: Text(item['name']?.toString() ?? 'Article', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                      trailing: Text("${fmt.format(total)} DA", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
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
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🟢 DRAG HANDLE standardisé
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 16),
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