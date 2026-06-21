import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/glass_card.dart';
import 'cash_session_page.dart';

class CashManagerPage extends StatefulWidget {
  const CashManagerPage({super.key});

  @override
  State<CashManagerPage> createState() => _CashManagerPageState();
}

class _CashManagerPageState extends State<CashManagerPage> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _registers = [];
  List<dynamic> _cashSessions = [];
  List<dynamic> _operations = [];
  int _selectedTabIndex = 0; 
  bool _isAdmin = false;
  
  // 🟢 FILTRES HISTORIQUE
  String _searchQuery = '';
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? '';
      
      final regs = await _api.getRegisters();
      final sessions = await _api.getCashSessions();
      final ops = await _api.getRegisterOperations();
      
      if (mounted) {
        setState(() {
          _isAdmin = role == 'admin' || role == 'proprietaire' || role == 'manager';
          _registers = regs;
          _cashSessions = sessions;
          _operations = ops;
        });
      }
    } catch (e) {
      debugPrint("Erreur Cash Manager: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _fmtMoney(dynamic val) {
    double amt = double.tryParse(val?.toString() ?? '0') ?? 0.0;
    return NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2).format(amt);
  }

  Color _hexToColor(String code) {
    if (code.startsWith('#')) code = code.substring(1);
    if (code.length == 6) code = 'FF$code';
    try { return Color(int.parse(code, radix: 16)); } catch (_) { return AppColors.primary; }
  }

  void _openRegisterDetails(Map<String, dynamic> register) async {
     await Navigator.push(context, MaterialPageRoute(builder: (_) => CashSessionPage(register: register, sessions: _cashSessions, allRegisters: _registers)));
     _loadData(); 
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F4F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text("Multi-Caisse", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                _buildTabs(isDark),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: _selectedTabIndex == 0
                        ? _buildRegistersList(isDark)
                        : _selectedTabIndex == 1
                            ? _buildSessionsList(isDark)
                            : _buildOperationsList(isDark),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTabs(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        height: 45,
        decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            _buildTab("Caisses", 0, isDark),
            _buildTab("Sessions", 1, isDark),
            _buildTab("Historique", 2, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String title, int index, bool isDark) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected ? [BoxShadow(color: AppColors.accent.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
          ),
          alignment: Alignment.center,
          child: Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black54))),
        ),
      ),
    );
  }

  Widget _buildRegistersList(bool isDark) {
    List<Widget> cards = [];

    // 🟢 CARTE GLOBALE : Uniquement visible par les administrateurs
    if (_isAdmin) {
      double globalBalance = _registers.fold(0.0, (sum, r) {
        if (r['exclude_from_global'] == 1 || r['exclude_from_global'] == true || r['exclude_from_global'] == '1') return sum;
        return sum + (double.tryParse(r['current_balance']?.toString() ?? '0') ?? 0.0);
      });

      cards.add(GestureDetector(
        onTap: () => _openRegisterDetails({'id': 'all', 'name': 'Toutes les caisses', 'type': 'global', 'current_balance': globalBalance}),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            isDark: isDark,
            padding: const EdgeInsets.all(16),
            borderRadius: 16,
            borderColor: Colors.purple.withOpacity(0.3),
            child: Row(
              children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple.withOpacity(0.5))),
                  child: const Icon(FontAwesomeIcons.globe, color: Colors.purple, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text('Toutes les caisses', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: const Text('Global', style: TextStyle(fontSize: 9, color: Colors.purple, fontWeight: FontWeight.bold))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text("Vue d'ensemble consolidée", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                FittedBox(fit: BoxFit.scaleDown, child: Text(_fmtMoney(globalBalance), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isDark ? Colors.white : Colors.black))),
              ],
            ),
          ),
        ),
      ));
    }

    if (_registers.isEmpty || (_registers.where((r) => r['transfer_only'] != true).isEmpty && !_isAdmin)) {
      cards.add(const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Aucune caisse disponible."))));
    }

    for (var reg in _registers) {
      // 🟢 MASQUER LES AUTRES CAISSES POUR LE VENDEUR : Il ne voit que SA caisse dans la grille
      if (reg['transfer_only'] == true && !_isAdmin) continue; 

      final color = _hexToColor(reg['color']?.toString() ?? '#6366F1');
      final currentBalance = double.tryParse(reg['current_balance']?.toString() ?? '0') ?? 0.0;
      final isActive = reg['active_session_id'] != null;
      
      IconData typeIcon = FontAwesomeIcons.cashRegister;
      String typeLabel = 'Caisse';
      if (reg['type'] == 'bank') { typeIcon = FontAwesomeIcons.buildingColumns; typeLabel = 'Banque'; }
      else if (reg['type'] == 'ccp') { typeIcon = FontAwesomeIcons.envelopeOpenText; typeLabel = 'CCP'; }
      else if (reg['type'] == 'cib') { typeIcon = FontAwesomeIcons.creditCard; typeLabel = 'TPE / CIB'; }

      cards.add(GestureDetector(
        onTap: () => _openRegisterDetails(reg),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            isDark: isDark,
            padding: const EdgeInsets.all(16),
            borderRadius: 16,
            child: Row(
              children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.5))),
                  child: Icon(typeIcon, color: color, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(reg['name'] ?? 'Caisse', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis)), // 🛠️ MODULE 2 : Flexible anti-overflow
                          const SizedBox(width: 6),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(typeLabel, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: isActive ? Colors.green : Colors.red, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(isActive ? "Session Ouverte" : "Session Fermée", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.green : Colors.red)),
                        ],
                      ),
                    ],
                  ),
                ),
                FittedBox(fit: BoxFit.scaleDown, child: Text(_fmtMoney(currentBalance), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isDark ? Colors.white : Colors.black))), // 🛠️ MODULE 2 : FittedBox anti-overflow
              ],
            ),
          ),
        ),
      ));
    }

    return ListView(padding: const EdgeInsets.all(16), children: cards);
  }

  Widget _buildSessionsList(bool isDark) {
    if (_cashSessions.isEmpty) return const Center(child: Text("Aucune session."));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _cashSessions.length,
      itemBuilder: (context, index) {
        final sess = _cashSessions[index];
        final isOpen = sess['close_time'] == null;
        final date = DateTime.tryParse(sess['open_time']?.toString() ?? '');
        final dateStr = date != null ? DateFormat('dd/MM HH:mm').format(date) : '...';
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            isDark: isDark,
            padding: const EdgeInsets.all(16),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(isOpen ? Icons.lock_open : Icons.lock, color: isOpen ? Colors.green : Colors.grey),
              title: Text("${sess['register_name'] ?? 'Caisse'} - Session #${sess['id']}"),
              subtitle: Text("Ouverte le $dateStr par ${sess['opened_by_name'] ?? '?'}"),
              trailing: Text(_fmtMoney(sess['initial_float']), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        );
      },
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

  // 🟢 NOUVELLE FONCTION: Ouvre le détail d'une opération avec ses articles (Vente/Achat)
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
        padding: const EdgeInsets.all(20),
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

  Widget _buildOperationsList(bool isDark) {
    // 1. Filtrer les opérations
    List<dynamic> filtered = _operations.where((op) {
        final type = op['entity_type'] ?? op['type'];
        if (_filterType != 'all') {
            if (_filterType == 'transfer' && !type.toString().contains('transfer')) return false;
            if (_filterType != 'transfer' && type != _filterType) return false;
        }
        if (_searchQuery.isNotEmpty) {
            final s = "${op['note']} ${op['counterpart']} ${op['register_name']} ${op['user_name']}".toLowerCase();
            if (!s.contains(_searchQuery.toLowerCase())) return false;
        }
        return true;
    }).toList();

    return Column(
      children: [
        // 🔍 BARRE DE RECHERCHE
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: "Rechercher une opération, client...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: isDark ? Colors.white10 : Colors.grey[200],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        // 🏷️ CHIPS DE FILTRAGE
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
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
        const SizedBox(height: 5),
        // 📋 LISTE DES OPÉRATIONS
        Expanded(
          child: filtered.isEmpty 
          ? const Center(child: Text("Aucune opération trouvée."))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
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
                      padding: const EdgeInsets.all(16),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
                        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
                        subtitle: Text("$dateStr • ${item['note'] ?? ''}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
                        trailing: Text((isPositive ? "+" : "-") + _fmtMoney(amount), style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16)),
                      ),
                    ),
                  ),
                );
              },
            ),
        ),
      ],
    );
  }
}