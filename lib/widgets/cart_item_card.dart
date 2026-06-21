// =============================================================================
// 🛒 CART ITEM CARD - Widget Réutilisable pour les Articles du Panier
// =============================================================================
// Design Ultra Clean : Card avec ombre douce, nom du produit en gros, 
// variante en petit/gris, boutons +/- intégrés, total à droite.
// Supporte le Dismissible (swipe to delete) en externe.
// =============================================================================

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CartItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int index;
  final bool isDark;
  final Function(int index, double newQty) onUpdateQty;
  final Function(int index) onRemove;
  final Function(int index, double newPrice)? onUpdatePrice; // 🛠️ MODULE 5 : Callback édition prix

  const CartItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.isDark,
    required this.onUpdateQty,
    required this.onRemove,
    this.onUpdatePrice, // 🛠️ MODULE 5 : Optionnel pour rétro-compatibilité
  });

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? 'Article';
    final variantLabel = _getVariantLabel();
    final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
    final qty = double.tryParse(item['qty']?.toString() ?? '1') ?? 1;
    final lineTotal = price * qty;
    final cleanUrl = ApiService.getCleanImageUrl(item['image']);

    return Dismissible(
      key: Key("cart_${item['product_id']}_${item['variant_id']}_$index"),
      direction: DismissDirection.endToStart,
      // 🗑️ Arrière-plan rouge avec icône poubelle
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 24),
            SizedBox(height: 2),
            Text("Supprimer", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      confirmDismiss: (_) async => true,
      onDismissed: (_) => onRemove(index),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: isDark ? const Color(0xFF1E1E28) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 📷 Image du produit
              _buildProductImage(cleanUrl),
              const SizedBox(width: 12),

              // 📝 Nom + Variante + Prix unitaire
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (variantLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        variantLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    // 🛠️ MODULE 5 : Prix unitaire cliquable pour édition
                    GestureDetector(
                      onTap: onUpdatePrice != null ? () => _showPriceEditDialog(context, price) : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "${price.toStringAsFixed(0)} DA / ${item['unit'] ?? 'unité'}",
                            style: TextStyle(
                              fontSize: 12,
                              color: onUpdatePrice != null ? Colors.blue[400] : Colors.grey[400],
                              decoration: onUpdatePrice != null ? TextDecoration.underline : null,
                              decorationColor: Colors.blue[400],
                            ),
                          ),
                          if (onUpdatePrice != null) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.edit, size: 12, color: Colors.blue[400]),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 🔢 Contrôle Quantité (+/-) ET POUBELLE
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      _buildQtyControl(qty),
                      const SizedBox(width: 8),
                      // 🗑️ BOUTON CORBEILLE DIRECT
                      GestureDetector(
                        onTap: () => onRemove(index),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 💰 Total ligne
                  Text(
                    "${lineTotal.toStringAsFixed(0)} DA",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: isDark ? Colors.orange[300] : Colors.orange[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // 📷 IMAGE PRODUIT
  // ============================================
  Widget _buildProductImage(String? url) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        image: url != null
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      child: url == null
          ? Icon(Icons.shopping_bag_outlined, color: Colors.grey[400], size: 22)
          : null,
    );
  }

  // ============================================
  // 🔢 CONTRÔLE QUANTITÉ
  // ============================================
  Widget _buildQtyControl(double qty) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQtyButton(
            icon: Icons.remove,
            color: qty > 1 ? Colors.red[400]! : Colors.grey[400]!,
            onTap: () => onUpdateQty(index, qty - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              "${qty.toInt()}",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          _buildQtyButton(
            icon: Icons.add,
            color: Colors.green[400]!,
            onTap: () => onUpdateQty(index, qty + 1),
          ),
        ],
      ),
    );
  }

  Widget _buildQtyButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  // ============================================
  // 🏷️ LABEL VARIANTE
  // ============================================
  String? _getVariantLabel() {
    final variantId = item['variant_id'];
    if (variantId == null) return null;
    
    final variantName = item['variant_name'] ?? item['sku'] ?? item['variant_label'];
    if (variantName != null && variantName.toString().isNotEmpty) {
      return "Variante : $variantName";
    }
    return "Variante #$variantId";
  }

  // ============================================
  // 💰 MODULE 5 : DIALOGUE ÉDITION PRIX
  // ============================================
  void _showPriceEditDialog(BuildContext context, double currentPrice) {
    final ctrl = TextEditingController(text: currentPrice.toStringAsFixed(0));
    final isDarkTheme = isDark;
    bool isPriceConfirming = false; // 🟢 FIX: Verrou anti-double clic sur le bouton Valider

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDarkTheme ? const Color(0xFF1E1E2C) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.edit, color: Colors.blue[400], size: 22),
            const SizedBox(width: 10),
            Text('Modifier le Prix', style: TextStyle(
              fontWeight: FontWeight.w900,
              color: isDarkTheme ? Colors.white : Colors.black87,
            )),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item['name']?.toString() ?? 'Article',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: isDarkTheme ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                suffixText: 'DA',
                suffixStyle: TextStyle(fontSize: 16, color: Colors.grey[500]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue.withOpacity(0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: TextStyle(color: Colors.grey[500])),
          ),
          ElevatedButton(
            onPressed: () {
              if (isPriceConfirming) return; // 🟢 Coupe le double-clic
              isPriceConfirming = true;
              
              final newPrice = double.tryParse(ctrl.text) ?? currentPrice;
              if (newPrice > 0) {
                onUpdatePrice!(index, newPrice);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Valider', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
