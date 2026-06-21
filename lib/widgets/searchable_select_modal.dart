// =============================================================================
// 🔍 SEARCHABLE SELECT MODAL - Widget Réutilisable de Sélection Rapide
// =============================================================================
// BottomSheet avec recherche en temps réel pour Clients/Fournisseurs.
// Filtre par nom ou téléphone. Clic sur un item => ferme + renvoie l'objet.
// =============================================================================

import 'package:flutter/material.dart';

class SearchableSelectModal extends StatefulWidget {
  /// Titre affiché en haut du BottomSheet (ex: "Sélectionner un client")
  final String title;

  /// Icône à côté du titre
  final IconData icon;

  /// Couleur thème (bleu pour clients, orange pour fournisseurs)
  final Color themeColor;

  /// Liste d'items [{ 'id': ..., 'name': ..., 'phone': ..., ... }]
  final List<dynamic> items;

  /// Texte affiché quand l'option "Aucun" est sélectionnée
  final String? noneLabel;

  /// Callback quand un item est sélectionné (null = aucune sélection)
  final Function(Map<String, dynamic>? selectedItem) onSelected;

  const SearchableSelectModal({
    super.key,
    required this.title,
    required this.icon,
    required this.themeColor,
    required this.items,
    required this.onSelected,
    this.noneLabel,
  });

  @override
  State<SearchableSelectModal> createState() => _SearchableSelectModalState();
}

class _SearchableSelectModalState extends State<SearchableSelectModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<dynamic> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
    // Auto-focus le champ de recherche après l'animation du sheet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.items;
      } else {
        _filtered = widget.items.where((item) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          final phone = (item['phone'] ?? '').toString().toLowerCase();
          final ref = (item['ref'] ?? '').toString().toLowerCase();
          return name.contains(q) || phone.contains(q) || ref.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 🟢 DRAG HANDLE
          const SizedBox(height: 10),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),

          // 🟢 TITRE
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(widget.icon, color: widget.themeColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 🔍 CHAMP DE RECHERCHE
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _focusNode,
              onChanged: _onSearch,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: "Rechercher par nom ou téléphone...",
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                prefixIcon: Icon(Icons.search, color: widget.themeColor),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 🟢 OPTION "AUCUN CLIENT" (Client Comptoir / Aucun Fournisseur)
          if (widget.noneLabel != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    widget.onSelected(null);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: widget.themeColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.themeColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.storefront, color: widget.themeColor, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          widget.noneLabel!,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: widget.themeColor,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_forward_ios, size: 14, color: widget.themeColor),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 4),

          // 📋 LISTE DES ITEMS
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
                        const SizedBox(height: 8),
                        const Text("Aucun résultat", style: TextStyle(color: Colors.grey, fontSize: 15)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final item = _filtered[i];
                      final name = item['name']?.toString() ?? 'Sans nom';
                      final phone = item['phone']?.toString() ?? '';
                      final balance = double.tryParse(item['balance']?.toString() ?? '0') ?? 0;
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              widget.onSelected(Map<String, dynamic>.from(item));
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.grey.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  // Avatar avec initiale
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: widget.themeColor.withValues(alpha: 0.15),
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        color: widget.themeColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Nom + Téléphone
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: isDark ? Colors.white : Colors.black,
                                          ),
                                        ),
                                        if (phone.isNotEmpty)
                                          Text(
                                            phone,
                                            style: TextStyle(
                                              color: Colors.grey[500],
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Solde / Balance
                                  if (balance != 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: balance > 0
                                            ? Colors.red.withValues(alpha: 0.1)
                                            : Colors.green.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        "${balance.toStringAsFixed(0)} DA",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: balance > 0 ? Colors.red : Colors.green,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
