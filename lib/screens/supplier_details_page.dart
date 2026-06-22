
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import 'client_details_page.dart';


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

  // 🛡️ RECALCUL LOCAL DU SOLDE (Zéro attente)
  double _calculateLocalBalance(Map<String, dynamic> data) {
    double totalAchats = 0;
    double totalPaiements = 0;

    List purchases = data['last_purchases'] ?? data['history_purchases'] ?? data['purchases'] ?? data['last_sales'] ?? [];
    List payments = data['last_payments'] ?? data['history_payments'] ?? data['payments'] ?? [];

    for (var po in purchases) {
      if (po != null && po is Map && (po['status'] == 'confirmed' || po['status'] == 'received')) {
        totalAchats += double.tryParse(po['total_amount']?.toString() ?? '0') ?? 0;
        totalPaiements += double.tryParse(po['amount_paid']?.toString() ?? '0') ?? 0;
      }
    }
    for (var p in payments) {
      if (p != null && p is Map) {
        if (p['is_local'] != true) {
            totalPaiements += double.tryParse(p['amount']?.toString() ?? '0') ?? 0;
        }
      }
    }
    return totalAchats - totalPaiements;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fullData = widget.summary;
    
    double rawBalance = double.tryParse(widget.summary['balance']?.toString() ?? '0') ?? 0;
    double calculatedBalance = _calculateLocalBalance(widget.summary);
    _currentBalance = calculatedBalance > 0.01 ? calculatedBalance : rawBalance;
    
    _loadDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

 Future<void> _loadDetails() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final freshData = await _api.getTierDetails('supplier', widget.summary['id']);
      if (mounted) {
        setState(() {
          if (freshData != null && freshData.isNotEmpty) {
             _fullData = { ...widget.summary, ...freshData };
             double serverBalance = double.tryParse(_fullData['balance']?.toString() ?? '0') ?? 0;
             if (serverBalance == 0) serverBalance = _calculateLocalBalance(_fullData);
             _currentBalance = serverBalance;
          }
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
          Navigator.pop(context);
          _api.sendPartnerPaymentOptimistic(
            partnerId: widget.summary['id'],
            amount: amount,
            type: 'SUPPLIER',
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
  final purchases = (_fullData['last_purchases'] as List?) ?? (_fullData['last_sales'] as List?) ?? (_fullData['history_purchases'] as List?) ?? (_fullData['purchases'] as List?) ?? [];
  final payments = (_fullData['last_payments'] as List?) ?? (_fullData['history_payments'] as List?) ?? (_fullData['payments'] as List?) ?? [];
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
                    ListView.builder(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 100),
                      itemCount: purchases.length,
                      itemBuilder: (ctx, i) {
                        final p = purchases[i];
                        
                        DateTime? parsedDate;
                        try {
                          if (p['date'] != null && p['date'].toString().isNotEmpty) {
                            parsedDate = DateTime.parse(p['date'].toString());
                          }
                        } catch(e) { parsedDate = null; }
                        final dateStr = parsedDate != null ? DateFormat('dd/MM/yyyy HH:mm').format(parsedDate) : '---';

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
                            title: Text("Achat #${p['number'] ?? p['id']}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dateStr),
                                if (p['global_discount'] != null && double.tryParse(p['global_discount'].toString()) != null && double.tryParse(p['global_discount'].toString())! > 0)
                                  Text("Remise : -${p['global_discount']} DA", style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            trailing: Text("${p['total_amount'] ?? 0} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14)),
                          ),
                        );
                      },
                    ),
                    ListView.builder(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 100),
                      itemCount: payments.length,
                      itemBuilder: (ctx, i) {
                        final pay = payments[i];
                        final isLocal = pay['is_local'] == true;

                        DateTime? parsedPayDate;
                        try {
                          if (pay['date'] != null && pay['date'].toString().isNotEmpty) {
                            parsedPayDate = DateTime.parse(pay['date'].toString());
                          }
                        } catch(e) { parsedPayDate = null; }
                        final payDateStr = parsedPayDate != null ? DateFormat('dd/MM/yyyy').format(parsedPayDate) : '---';

                        return ListTile(
                            leading: isLocal 
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                              : const Icon(Icons.remove_circle, color: Colors.red),
                            title: Text(
                              isLocal ? "Paiement (En cours...)" : "Paiement Sortant", 
                              style: TextStyle(fontWeight: FontWeight.bold, fontStyle: isLocal ? FontStyle.italic : FontStyle.normal)
                            ),
                            subtitle: Text(payDateStr),
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