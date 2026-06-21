// =============================================================================
// 📉 LOSSES PAGE - Déclaration de Pertes de Stock
// =============================================================================
// Écran permettant de déclarer une perte de stock (casse, péremption, vol).
// Envoie l'action DECLARE_LOSS via la queue vers le backend PC.
// Le backend déduit le stock et crée éventuellement une charge financière.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../core/constants.dart';
import '../services/api_service.dart';

class LossesPage extends StatefulWidget {
  final VoidCallback? onBack;

  const LossesPage({super.key, this.onBack});

  @override
  State<LossesPage> createState() => _LossesPageState();
}

class _LossesPageState extends State<LossesPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');

  List<dynamic> _products = [];
  List<dynamic> _filtered = [];
  Map<String, dynamic>? _selectedProduct;
  Map<String, dynamic>? _selectedVariant;
  String _reason = 'Casse';
  bool _financialImpact = true;
  bool _isLoading = true;
  bool _isSending = false;

  final List<String> _reasons = [
    'Casse',
    'Péremption',
    'Vol / Disparition',
    'Défaut de fabrication',
    'Autre',
  ];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final products = await _api.getProducts();
      if (mounted) {
        setState(() {
          _products = products;
          _filtered = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterProducts(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filtered = _products;
      } else {
        _filtered = _products.where((p) {
          final name = (p['name'] ?? '').toString().toLowerCase();
          final ref = (p['ref'] ?? p['reference'] ?? '').toString().toLowerCase();
          return name.contains(q) || ref.contains(q);
        }).toList();
      }
    });
  }

  void _selectProduct(Map<String, dynamic> product) {
    setState(() {
      _selectedProduct = product;
      _selectedVariant = null;
    });
  }

  Future<void> _submit() async {
    if (_selectedProduct == null) return;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Quantité invalide"), backgroundColor: Colors.red),
      );
      return;
    }

    // Confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("⚠️ Confirmer la perte"),
        content: Text(
          "Déclarer une perte de ${qty.toInt()} x ${_selectedProduct!['name']}\n"
          "Raison : $_reason\n"
          "${_financialImpact ? '💰 Sera comptabilisé en charge.' : '📊 Non-financier.'}",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Confirmer", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSending = true);
    try {
      await _api.declareStockLoss(
        productId: _selectedProduct!['id'],
        variantId: _selectedVariant?['id'],
        qty: qty,
        reason: _reason,
        financialImpact: _financialImpact,
      );

      if (mounted) {
        setState(() {
          _isSending = false;
          _selectedProduct = null;
          _selectedVariant = null;
          _qtyCtrl.text = '1';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Perte déclarée avec succès"), backgroundColor: Colors.green),
        );
        _loadProducts(); // Refresh stock
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Column(
          children: [
            // --- HEADER ---
            Container(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C23) : Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black),
                    onPressed: widget.onBack ?? () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  const Icon(FontAwesomeIcons.boxOpen, color: Colors.red, size: 20),
                  const SizedBox(width: 10),
                  Text("Déclarer une Perte", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                ],
              ),
            ),

            Expanded(
              child: _selectedProduct == null ? _buildProductSelector(isDark) : _buildLossForm(isDark),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // 🔍 SÉLECTION DU PRODUIT
  // ============================================
  Widget _buildProductSelector(bool isDark) {
    return Column(
      children: [
        // Search
        Container(
          margin: const EdgeInsets.all(20),
          height: 50,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!),
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _filterProducts,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: "Rechercher un produit...",
              hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),

        // Product list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _filtered.isEmpty
                  ? const Center(child: Text("Aucun produit trouvé", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final p = _filtered[i];
                        final stock = double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.transparent),
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            leading: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.inventory_2, color: Colors.red, size: 20),
                            ),
                            title: Text(p['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                            subtitle: Text("Stock: ${stock.toInt()} • ${p['ref'] ?? ''}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: () => _selectProduct(Map<String, dynamic>.from(p)),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ============================================
  // 📝 FORMULAIRE DE PERTE
  // ============================================
  Widget _buildLossForm(bool isDark) {
    final variants = _selectedProduct!['variants'];
    final hasVariants = variants is List && variants.isNotEmpty;
    final currentStock = _selectedVariant != null
        ? (double.tryParse(_selectedVariant!['stock']?.toString() ?? '0') ?? 0)
        : (double.tryParse(_selectedProduct!['stock']?.toString() ?? '0') ?? 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product info
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(FontAwesomeIcons.boxOpen, color: Colors.red, size: 20),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedProduct!['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                      Text("Stock actuel: ${currentStock.toInt()}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => setState(() { _selectedProduct = null; _selectedVariant = null; }),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Variant selector (if applicable)
          if (hasVariants) ...[
            Text("Variante", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _buildVariantChip("Produit Principal", null, isDark),
                ...variants.map<Widget>((v) {
                  final label = v['sku'] ?? v['options']?.toString() ?? 'Var #${v['id']}';
                  return _buildVariantChip(label, v, isDark);
                }),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // Quantity
          Text("Quantité perdue", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 8),
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            ),
          ),

          const SizedBox(height: 20),

          // Reason
          Text("Raison de la perte", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _reasons.map((r) {
              final isSelected = _reason == r;
              return ChoiceChip(
                label: Text(r),
                selected: isSelected,
                selectedColor: Colors.red.withOpacity(0.2),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.red : (isDark ? Colors.white : Colors.black),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) => setState(() => _reason = r),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Financial impact toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            decoration: BoxDecoration(
              color: _financialImpact ? Colors.orange.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _financialImpact ? Colors.orange : Colors.grey.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(_financialImpact ? Icons.attach_money : Icons.money_off, color: _financialImpact ? Colors.orange : Colors.grey, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Impact Financier", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                      Text(
                        _financialImpact ? "Comptabilisé comme charge" : "Non comptabilisé",
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _financialImpact,
                  activeColor: Colors.orange,
                  onChanged: (v) => setState(() => _financialImpact = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _isSending ? null : _submit,
              icon: _isSending 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(FontAwesomeIcons.triangleExclamation, size: 18),
              label: Text(_isSending ? "Envoi..." : "DÉCLARER LA PERTE", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantChip(String label, Map<String, dynamic>? variant, bool isDark) {
    final isSelected = _selectedVariant == variant || (_selectedVariant == null && variant == null);
    return GestureDetector(
      onTap: () => setState(() => _selectedVariant = variant),
      child: Chip(
        label: Text(label, style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.red : (isDark ? Colors.white : Colors.black),
        )),
        backgroundColor: isSelected ? Colors.red.withOpacity(0.15) : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]),
        side: BorderSide(color: isSelected ? Colors.red : Colors.transparent),
      ),
    );
  }
}
