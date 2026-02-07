import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../providers/data_provider.dart';
import 'package:provider/provider.dart';

class QuickActionSheet extends StatefulWidget {
  final String type; // 'CHARGE', 'PRODUCT', 'PURCHASE'
  const QuickActionSheet({super.key, required this.type});

  @override
  State<QuickActionSheet> createState() => _QuickActionSheetState();
}

class _QuickActionSheetState extends State<QuickActionSheet> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _api = ApiService();
  bool _isLoading = false;

  String _name = '';
  double _amount = 0;
  double _cost = 0;
  double _stock = 0;
  String _barcode = '';
  String _category = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardSpace = MediaQuery.of(context).viewInsets.bottom;

    String title = "";
    Color themeColor = AppColors.primary;
    List<Widget> formFields = [];

    switch (widget.type) {
      case 'CHARGE':
        title = "Nouvelle Dépense";
        themeColor = Colors.red;
        formFields = [
          _input("Libellé (ex: Loyer, STEG)", (v) => _name = v),
          _input("Montant (DA)", (v) => _amount = double.tryParse(v) ?? 0, isNumber: true),
          _input("Catégorie (ex: Fixe, Divers)", (v) => _category = v, isRequired: false),
        ];
        break;

      case 'PURCHASE':
        title = "Réception Achat";
        themeColor = Colors.orange;
        formFields = [
          _input("Fournisseur", (v) => _category = v, isRequired: false), // On utilise _category pour stocker le nom fournisseur temporairement
          _input("Montant Total (DA)", (v) => _amount = double.tryParse(v) ?? 0, isNumber: true),
          _input("Ref Bon / Note", (v) => _name = v, isRequired: false),
        ];
        break;

      case 'PRODUCT':
        title = "Création Produit";
        themeColor = Colors.blue;
        formFields = [
          _input("Nom du produit", (v) => _name = v),
          Row(children: [
            Expanded(child: _input("Prix Vente", (v) => _amount = double.tryParse(v) ?? 0, isNumber: true)),
            const SizedBox(width: 10),
            Expanded(child: _input("Prix Achat", (v) => _cost = double.tryParse(v) ?? 0, isNumber: true)),
          ]),
          Row(children: [
            Expanded(child: _input("Stock", (v) => _stock = double.tryParse(v) ?? 0, isNumber: true)),
            const SizedBox(width: 10),
            Expanded(child: _input("Code-barres", (v) => _barcode = v, isRequired: false)),
          ]),
          _input("Famille (Catégorie)", (v) => _category = v, isRequired: false),
        ];
        break;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboardSpace),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: themeColor)),
              const SizedBox(height: 20),
              ...formFields,
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : const Text("VALIDER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input(String label, Function(String) onSave, {bool isNumber = false, bool isRequired = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        onSaved: (v) => onSave(v ?? ''),
        validator: (v) => (isRequired && (v == null || v.isEmpty)) ? 'Requis' : null,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    
    // Pas de loader visible longtemps car c'est instantané (Optimistic UI)
    setState(() => _isLoading = true);

    try {
      if (widget.type == 'PRODUCT') {
        // ✅ CORRECTION : Appel avec un seul objet Map pour respecter la nouvelle signature
        await _api.addProductOptimistic({
          "name": _name,
          "price": _amount, // _amount contient le prix de vente ici
          "cost": _cost,
          "stock": _stock,
          "barcode": _barcode,
          "category": _category.isEmpty ? "Divers" : _category
        });

      } else if (widget.type == 'PURCHASE') {
        // ✅ CORRECTION : Utilisation de la méthode optimiste pour achat
        await _api.sendComplexPurchase(
          _amount, // Total
          [], // Pas d'items pour un achat rapide global
          note: _name.isEmpty ? "Achat Rapide Mobile" : _name,
          supplierName: _category.isEmpty ? "Divers" : _category // _category stocke le fournisseur ici
        );

      } else if (widget.type == 'CHARGE') {
        // ✅ Appel Optimiste Charge
        await _api.addChargeOptimistic(
           _name, 
           _amount, 
           _category.isEmpty ? "Divers" : _category
        );
      }

      if (mounted) {
        Navigator.pop(context, true); // Fermer la modale
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Action enregistrée !"), backgroundColor: Colors.green));
        
        // Rafraîchir les données globales si nécessaire via Provider
        try {
           Provider.of<DataProvider>(context, listen: false).loadData(forceRefresh: true);
        } catch(e) {}
      }
    } catch (e) {
      if (mounted) {
         setState(() => _isLoading = false);
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur lors de l'enregistrement"), backgroundColor: Colors.red));
      }
    }
  }
}