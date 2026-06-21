import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class CashSessionPage extends StatefulWidget {
  final Map<String, dynamic> register;
  final List<dynamic> sessions;
  final List<dynamic> allRegisters;

  const CashSessionPage({super.key, required this.register, required this.sessions, required this.allRegisters});

  @override
  State<CashSessionPage> createState() => _CashSessionPageState();
}

class _CashSessionPageState extends State<CashSessionPage> {
  final ApiService _api = ApiService();
  bool _isLoading = false;
  late List<dynamic> _history;
  late Map<String, dynamic> _currentRegister;
  // 🟢 CHANTIER 3 — RBAC Multi-Caisses
  bool _isAdmin = false;
  bool _isOwnRegister = false; // 🛠️ FIX : L'utilisateur peut fermer SA caisse

  // 🟢 FILTRES HISTORIQUE
  String _searchQuery = '';
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _currentRegister = Map<String, dynamic>.from(widget.register);
    _history = [];
    _loadRole();
    _loadRichHistory();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';
    final assignedRegId = prefs.getInt('assigned_register_id');
    if (mounted) {
      setState(() {
        _isAdmin = role == 'admin' || role == 'proprietaire' || role == 'manager';
        // L'utilisateur peut fermer la caisse qui lui est attribuée
        _isOwnRegister = assignedRegId != null && _currentRegister['id'] == assignedRegId;
      });
    }
  }

  // 🟢 Chargement intelligent (Globale ou Spécifique)
  Future<void> _loadRichHistory() async {
    setState(() => _isLoading = true);
    try {
      if (_currentRegister['id'] == 'all') {
         final history = await _api.getRegisterOperations(); // Tout l'historique
         if (mounted) setState(() => _history = history);
      } else {
         final history = await _api.getRegisterFullHistory(_currentRegister['id']);
         if (mounted) setState(() => _history = history);
      }
    } catch(e) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshData() async {
    if (_currentRegister['id'] == 'all') return _loadRichHistory(); // Just reload history

    setState(() => _isLoading = true);
    try {
      await _api.syncQueueNow(); 
      await Future.delayed(const Duration(seconds: 2)); 
      
      final regs = await _api.getRegisters();
      final history = await _api.getRegisterFullHistory(_currentRegister['id']);
      if (mounted) {
        setState(() {
          _currentRegister = regs.firstWhere((r) => r['id'] == _currentRegister['id'], orElse: () => _currentRegister);
          _history = history;
        });
      }
    } catch(e) {}
    if (mounted) setState(() => _isLoading = false);
  }

  String _fmtMoney(dynamic val) {
    double amt = double.tryParse(val?.toString() ?? '0') ?? 0.0;
    return NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2).format(amt);
  }

  void _showOperationDialog(String type) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == 'deposit' ? "Nouveau Dépôt" : "Nouveau Retrait"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Montant (DA)")),
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: "Note (Optionnelle)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amountCtrl.text) ?? 0;
              if (amt <= 0) return;
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              await _api.addRegisterOperationOptimistic(_currentRegister['id'], type, amt, noteCtrl.text);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Opération envoyée !"), backgroundColor: Colors.green));
              await _refreshData(); 
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    );
  }

  void _showTransferDialog() {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    int? selectedTargetId;

    final otherRegisters = widget.allRegisters.where((r) => r['id'] != _currentRegister['id']).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) {
          return AlertDialog(
            title: const Text("Transfert vers une caisse"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: "Caisse de destination"),
                  items: otherRegisters.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['name']))).toList(),
                  onChanged: (v) => setStateSB(() => selectedTargetId = v),
                ),
                const SizedBox(height: 10),
                TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Montant (DA)")),
                const SizedBox(height: 10),
                TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: "Note (Optionnelle)")),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
              ElevatedButton(
                onPressed: () async {
                  final amt = double.tryParse(amountCtrl.text) ?? 0;
                  if (amt <= 0 || selectedTargetId == null) return;
                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  await _api.addRegisterTransferOptimistic(_currentRegister['id'], selectedTargetId!, amt, noteCtrl.text);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transfert envoyé !"), backgroundColor: Colors.green));
                  await _refreshData(); 
                },
                child: const Text("Valider"),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showOpenSessionDialog() {
    final floatCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ouvrir la session"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: floatCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Fond de caisse (DA)")),
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: "Note d'ouverture")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(floatCtrl.text) ?? 0;
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              await _api.openCashSessionOptimistic(_currentRegister['id'], amt, noteCtrl.text);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ouverture envoyée !"), backgroundColor: Colors.green));
              await _refreshData(); 
            },
            child: const Text("Ouvrir"),
          ),
        ],
      ),
    );
  }

  void _showCloseSessionDialog() {
    final closingCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clôturer la session"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: closingCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Montant réel en caisse (DA)")),
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: "Note de clôture (Optionnel)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final closingAmt = double.tryParse(closingCtrl.text) ?? 0;
              Navigator.pop(ctx);
              setState(() => _isLoading = true);

              final currentBalance = double.tryParse(_currentRegister['current_balance']?.toString() ?? '0') ?? 0.0;
              final difference = closingAmt - currentBalance;

              await _api.closeCashSessionOptimistic(
                _currentRegister['active_session_id'],
                _currentRegister['id'], 
                closingAmt,
                difference,
                noteCtrl.text,
              );

              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Clôture envoyée avec succès !"), backgroundColor: Colors.green));
              await _refreshData(); 
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text("Clôturer", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String type, String label, IconData icon, bool isDark) {
    final isSelected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Row(children: [Icon(icon, size: 14, color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black87)), const SizedBox(width: 5), Text(label)]),
        selected: isSelected,
        onSelected: (val) => setState(() => _filterType = type),
        selectedColor: AppColors.primary,
        backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
        labelStyle: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black87), fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
      ),
    );
  }

  void _showTransactionDetails(dynamic item, bool isDark) {
    final type = item['entity_type'] ?? item['type'];
    final id = item['entity_id'];
    
    if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Détails d'articles non disponibles pour ce mouvement.")));
        return;
    }

    String title = "Détail Opération";
    IconData icon = Icons.info;
    Color color = Colors.blue;

    if (type == 'sale') { title = "Détail Vente"; icon = Icons.shopping_cart_checkout; color = Colors.green; }
    else if (type == 'purchase') { title = "Détail Achat"; icon = Icons.local_shipping; color = Colors.orange; }
    else if (type == 'charge') { title = "Détail Charge"; icon = Icons.receipt_long; color = Colors.red; }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20), // 🛠️ MODULE 1 : Padding dynamique Android
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                      Text("${item['counterpart'] ?? 'Système'} • ${item['note'] ?? ''}", style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Text(_fmtMoney(item['amount']), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
            const Divider(height: 30),
            Expanded(
              child: (type == 'sale' || type == 'purchase')
                ? FutureBuilder<List<dynamic>>(
                    future: type == 'sale' ? _api.getSaleItems(id) : _api.getPurchaseItems(id),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Aucun article trouvé."));
                      
                      final items = snapshot.data!;
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (c, i) => const Divider(),
                        itemBuilder: (c, i) {
                          final line = items[i];
                          final name = line['name'] ?? line['product_real_name'] ?? 'Article';
                          final qty = double.tryParse(line['quantity']?.toString() ?? line['qty']?.toString() ?? '0') ?? 0;
                          final price = double.tryParse(line['price']?.toString() ?? line['price_at_sale']?.toString() ?? line['unit_price']?.toString() ?? '0') ?? 0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text("${qty.toInt()}x", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                            trailing: Text(_fmtMoney(qty * price), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                          );
                        }
                      );
                    }
                  )
                : const Center(child: Text("Opération financière (Pas de panier).")),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text("Fermer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGlobal = _currentRegister['id'] == 'all';
    final currentBalance = double.tryParse(_currentRegister['current_balance']?.toString() ?? '0') ?? 0.0;
    final isActive = _currentRegister['active_session_id'] != null;

    // 1. Appliquer les Filtres à l'historique
    List<dynamic> filteredHistory = _history.where((item) {
        final type = item['entity_type'] ?? item['type'];
        if (_filterType != 'all') {
            if (_filterType == 'transfer' && !type.toString().contains('transfer')) return false;
            if (_filterType != 'transfer' && type != _filterType) return false;
        }
        if (_searchQuery.isNotEmpty) {
            final s = "${item['note']} ${item['counterpart']} ${item['user_name']}".toLowerCase();
            if (!s.contains(_searchQuery.toLowerCase())) return false;
        }
        return true;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: Text(_currentRegister['name'] ?? 'Détail Caisse'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isGlobal) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GlassCard(
                    isDark: isDark,
                    padding: const EdgeInsets.all(24),
                    borderRadius: 20,
                    child: Column(
                      children: [
                        const Text("SOLDE ACTUEL", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text(_fmtMoney(currentBalance), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.accent)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (isActive ? Colors.green : Colors.grey).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(isActive ? "Session Active" : "Session Fermée", style: TextStyle(color: isActive ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _showOperationDialog('deposit'),
                          icon: const Icon(Icons.add, color: Colors.white, size: 16),
                          label: const FittedBox(child: Text("Dépôt", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _showOperationDialog('withdraw'),
                          icon: const Icon(Icons.remove, color: Colors.white, size: 16),
                          label: const FittedBox(child: Text("Retrait", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: _showTransferDialog,
                          icon: const Icon(Icons.swap_horiz, color: Colors.white, size: 16),
                          label: const FittedBox(child: Text("Transf.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: !isActive
                      ? ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          onPressed: _showOpenSessionDialog,
                          child: const Text("Ouvrir la session", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        )
                      // 🛠️ FIX : L'utilisateur mobile peut fermer SA caisse attribuée, pas seulement l'admin
                      : (_isAdmin || _isOwnRegister)
                          ? ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                              onPressed: _showCloseSessionDialog,
                              child: const Text("Fermer la session", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.orange.withOpacity(0.3)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.lock_outline, color: Colors.orange, size: 18),
                                  SizedBox(width: 8),
                                  Text("Cette caisse ne vous est pas attribuée", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                ),
                const SizedBox(height: 15),
              ],
              
              // 🔍 FILTRES 
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: "Rechercher...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.grey[200],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildFilterChip('all', 'Tout', Icons.all_inclusive, isDark),
                    _buildFilterChip('sale', 'Ventes', Icons.shopping_cart, isDark),
                    _buildFilterChip('client_payment', 'Versements', Icons.arrow_downward, isDark),
                    _buildFilterChip('purchase', 'Achats', Icons.local_shipping, isDark),
                    _buildFilterChip('charge', 'Charges', Icons.receipt_long, isDark),
                    _buildFilterChip('transfer', 'Transferts', Icons.swap_horiz, isDark),
                  ],
                ),
              ),

              // 📋 LISTE HISTORIQUE
              Expanded(
                child: filteredHistory.isEmpty
                  ? const Center(child: Text("Aucun historique."))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredHistory.length,
                      itemBuilder: (context, index) {
                        final item = filteredHistory[index];
                        final type = item['entity_type'] ?? item['type'];
                        final isPositive = (item['signed_amount'] != null) ? (item['signed_amount'] > 0) : (type == 'deposit' || type == 'transfer_in');
                        final amount = (double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0).abs();
                        final date = DateTime.tryParse(item['date']?.toString() ?? '');
                        final dateStr = date != null ? DateFormat('dd/MM HH:mm').format(date) : '...';

                        IconData icon = Icons.circle;
                        Color color = isPositive ? Colors.green : Colors.red;
                        String title = "Opération";

                        if (type == 'operation' || type == 'deposit' || type == 'withdrawal') { icon = isPositive ? Icons.add_circle_outline : Icons.remove_circle_outline; title = isPositive ? 'Dépôt Manuel' : 'Retrait Manuel'; } 
                        else if (type == 'transfer' || type == 'transfer_in' || type == 'transfer_out') { icon = Icons.swap_horiz; color = Colors.blue; title = isPositive ? 'Reçu de: ${item['counterpart'] ?? '?'}' : 'Envoyé à: ${item['counterpart'] ?? '?'}'; } 
                        else if (type == 'session') { icon = Icons.lock_outline; title = 'Clôture Session (Écart)'; } 
                        else if (type == 'charge') { icon = Icons.receipt_long; title = 'Charge: ${item['counterpart'] ?? 'Divers'}'; } 
                        else if (type == 'sale') { icon = Icons.shopping_cart_checkout; title = item['note'] ?? 'Vente'; } 
                        else if (type == 'purchase') { icon = Icons.local_shipping_outlined; title = item['note'] ?? 'Achat'; } 
                        else if (type == 'client_payment') { icon = Icons.arrow_downward; title = 'Versement: ${item['counterpart'] ?? 'Client'}'; } 
                        else if (type == 'supplier_payment') { icon = Icons.arrow_upward; title = 'Paiement: ${item['counterpart'] ?? 'Fournisseur'}'; }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            onTap: () => _showTransactionDetails(item, isDark),
                            child: GlassCard(
                              isDark: isDark,
                              padding: const EdgeInsets.all(12),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
                                title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                                subtitle: Text("$dateStr • ${item['note'] ?? ''}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
                                trailing: FittedBox(fit: BoxFit.scaleDown, child: Text((isPositive ? "+" : "-") + _fmtMoney(amount), style: TextStyle(fontWeight: FontWeight.bold, color: color))), // 🛠️ MODULE 2 : FittedBox anti-overflow
                              ),
                            ),
                          ),
                        );
                      }
                  ),
              ),
            ],
          ),
          if (_isLoading)
            Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}