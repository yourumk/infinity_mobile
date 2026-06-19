import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/print_config_modal.dart';

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
  // 🟢 RBAC : Droit d'encaisser les versements clients
  bool _canAddPayment = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fullData = widget.summary;
    _currentBalance = double.tryParse(widget.summary['balance']?.toString() ?? '0') ?? 0;
    _loadDetails();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';
    final permsString = prefs.getString('user_permissions') ?? '[]';
    List<String> perms = [];
    try {
      perms = (json.decode(permsString) as List).map((e) => e.toString()).toList();
    } catch (_) {}
    if (mounted) {
      setState(() {
        // Admin a toujours accès ; sinon vérifier la permission spécifique
        _canAddPayment = role == 'admin' || role == 'manager' || perms.contains('mobile_client_payment');
      });
    }
  }

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
          if (freshData != null && freshData is Map) {
            _fullData = { ...widget.summary, ...freshData };
            _currentBalance = double.tryParse(_fullData['balance']?.toString() ?? '0') ?? _currentBalance;
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

  Future<void> _quickPrint(BuildContext context, String format, String docType, dynamic id) async {
    final config = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PrintConfigModal(initialFormat: format),
    );

    if (config != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Demande au PC...", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );

      final success = await _api.printViaPC(config['format'], docType, id, options: config);

      if (context.mounted) Navigator.pop(context);

      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Échec : Le PC de la boutique est-il allumé et connecté ?")),
        );
      }
    }
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
                      NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(_currentBalance),
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
                      padding: const EdgeInsets.all(20),
                      itemCount: sales.length,
                      itemBuilder: (ctx, i) {
                        final s = sales[i];
                        if (s == null || s is! Map) return const SizedBox.shrink(); // Ignore les lignes corrompues

                        // Protection des dates
                        DateTime? parsedDate;
                        if (s['date'] != null) parsedDate = DateTime.tryParse(s['date'].toString());
                        final dateStr = parsedDate != null ? DateFormat('dd/MM/yyyy HH:mm').format(parsedDate) : '-';
                        
                        // Protection des remises
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
                           title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Vente #${s['invoice_number'] ?? s['id'] ?? '?'}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                                Text("${s['total_amount'] ?? 0} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dateStr),
                                if (discount > 0)
                                  Text("Remise : -${discount.toStringAsFixed(0)} DA", style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(FontAwesomeIcons.truckFast, size: 18, color: Colors.green),
                                  onPressed: () => _quickPrint(context, 'A5', 'bl', s['id']),
                                ),
                                IconButton(
                                  icon: const Icon(FontAwesomeIcons.filePdf, size: 18, color: Colors.redAccent),
                                  onPressed: () => _quickPrint(context, 'A4', 'sale', s['id']),
                                ),
                              ],
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
                        if (p == null || p is! Map) return const SizedBox.shrink(); // Ignore les lignes corrompues
                        
                        // Protection des dates
                        DateTime? parsedDate;
                        if (p['date'] != null) parsedDate = DateTime.tryParse(p['date'].toString());
                        final dateStr = parsedDate != null ? DateFormat('dd/MM/yyyy').format(parsedDate) : '-';

                        return ListTile(
                          leading: const Icon(Icons.check_circle, color: Colors.green),
                          title: const Text("Versement reçu", style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(dateStr),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("+${p['amount'] ?? 0} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                              const SizedBox(width: 10),
                              IconButton(
                                icon: const Icon(FontAwesomeIcons.receipt, size: 18, color: Colors.blue),
                                onPressed: () => _quickPrint(context, 'Ticket', 'pay_client', p['id']),
                              ),
                            ],
                          ),
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, 
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 🟢 DRAG HANDLE standardisé
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                  Text(name, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
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
                    if (item == null || item is! Map) return const SizedBox.shrink(); // Protection élément nul

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
                      trailing: Text("${NumberFormat.currency(locale: 'fr_DZ', symbol: '', decimalDigits: 0).format(total)} DA", 
                        style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    );
                  },
                );
              },
            ),
          ),
          
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL TTC", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("${data['total_amount'] ?? 0} DA", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            ],
          ),
          
          const SizedBox(height: 20),

          if (isSale) ...[
            const Align(alignment: Alignment.centerLeft, child: Text("📄 Imprimer Facture :", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildPrintBtn(context, "Ticket", FontAwesomeIcons.receipt, Colors.teal, 'Ticket', 'sale', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A5", FontAwesomeIcons.fileLines, Colors.blueAccent, 'A5', 'sale', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A4", FontAwesomeIcons.filePdf, Colors.redAccent, 'A4', 'sale', data['id'])),
              ],
            ),
            const SizedBox(height: 15),
            const Align(alignment: Alignment.centerLeft, child: Text("🚚 Imprimer Bon de Livraison :", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildPrintBtn(context, "Ticket", FontAwesomeIcons.receipt, Colors.teal, 'Ticket', 'bl', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A5", FontAwesomeIcons.fileLines, Colors.blueAccent, 'A5', 'bl', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A4", FontAwesomeIcons.filePdf, Colors.redAccent, 'A4', 'bl', data['id'])),
              ],
            ),
          ] else ...[
            const Align(alignment: Alignment.centerLeft, child: Text("🛒 Imprimer Bon de Commande :", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildPrintBtn(context, "Ticket", FontAwesomeIcons.receipt, Colors.teal, 'Ticket', 'purchase', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A5", FontAwesomeIcons.fileLines, Colors.blueAccent, 'A5', 'purchase', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A4", FontAwesomeIcons.filePdf, Colors.redAccent, 'A4', 'purchase', data['id'])),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrintBtn(BuildContext context, String label, IconData icon, Color color, String format, String docType, dynamic docId) {
    return ElevatedButton(
      onPressed: () async {
        final config = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => PrintConfigModal(initialFormat: format),
        );

        if (config != null && context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Text("Demande au PC...", style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          );

          final success = await api.printViaPC(config['format'], docType, docId, options: config);

          if (context.mounted) Navigator.pop(context);

          if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Échec : Le PC est-il allumé et connecté ?")));
          }
        }
      },
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