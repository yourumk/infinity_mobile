import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrintConfigModal extends StatefulWidget {
  final String initialFormat;
  const PrintConfigModal({super.key, this.initialFormat = 'Ticket'});

  @override
  State<PrintConfigModal> createState() => _PrintConfigModalState();
}

class _PrintConfigModalState extends State<PrintConfigModal> {
  late String _format;
  bool _isLoading = true;

  // TOUTES LES OPTIONS DU PC (Par défaut à true, mais écrasées par les préférences sauvegardées)
  final Map<String, bool> _cfg = {
    // EN-TÊTE
    'showHeader': true,
    'showLogo': true,
    'showName': true,
    'showAddress': true,
    'showPhone': true,
    'showEmail': true,
    'showRc': true,
    'showNif': true,
    'showNis': true,
    'showArt': true,
    'showRib': true,

    // CLIENT
    'showClientBox': true,
    'showClientName': true,
    'showClientDetail': true,
    'showClientPhone': true,
    'showClientEmail': true,
    'showClientNif': true,
    'showClientNis': true,
    'showClientRc': true,
    'showClientArt': true,
    'showClientRib': true,

    // TABLEAU
    'colRef': true,
    'colPriceTtc': true,
    'colPriceHt': false,
    'colTotal': true,
    'showProductImages': false,
    'showLineNumber': true,
    'zebraRows': false,

    // TOTAUX & PIED DE PAGE
    'showTotalHt': true,
    'showTva': true,
    'showProductDiscount': true,
    'showGlobalDiscount': true,
    'showFinalTotal': true,
    'showPayments': true,
    'showBalance': true,
    'showOldBalance': true,
    'showLetters': true,
    'showBarcode': true,
    'showSignature': false,
    'showPaymentMode': true,
    'showUser': true,
    'showInternalNote': true,
  };

  @override
  void initState() {
    super.initState();
    _format = widget.initialFormat;
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (String key in _cfg.keys) {
        // On cherche s'il a déjà été sauvegardé, sinon on laisse la valeur par défaut
        if (prefs.containsKey('print_cfg_$key')) {
          _cfg[key] = prefs.getBool('print_cfg_$key')!;
        }
      }
      _isLoading = false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (String key in _cfg.keys) {
      await prefs.setBool('print_cfg_$key', _cfg[key]!);
    }
  }

  Widget _buildSwitch(String title, String key) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      value: _cfg[key] ?? true,
      activeColor: Colors.blueAccent,
      onChanged: (val) {
        setState(() => _cfg[key] = val);
        _savePrefs(); // Sauvegarde instantanée
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, // Prend 85% de l'écran
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // HEADER DU MODAL
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Studio d'Impression", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          
          // CHOIX DU FORMAT
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Ticket', label: Text('Ticket')),
                ButtonSegment(value: 'A5', label: Text('A5')),
                ButtonSegment(value: 'A4', label: Text('A4')),
              ],
              selected: {_format},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() => _format = newSelection.first);
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                selectedForegroundColor: Colors.white,
                selectedBackgroundColor: Colors.blueAccent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(),

          // LISTE DES PARAMÈTRES (Scrollable)
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                ExpansionTile(
                  leading: const Icon(Icons.business),
                  title: const Text("En-tête & Entreprise", style: TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    _buildSwitch("Afficher l'En-tête globale", "showHeader"),
                    _buildSwitch("Afficher le Logo", "showLogo"),
                    _buildSwitch("Nom de l'entreprise", "showName"),
                    _buildSwitch("Adresse", "showAddress"),
                    _buildSwitch("Téléphone", "showPhone"),
                    _buildSwitch("Email", "showEmail"),
                    _buildSwitch("RC", "showRc"),
                    _buildSwitch("NIF", "showNif"),
                    _buildSwitch("NIS", "showNis"),
                    _buildSwitch("ART", "showArt"),
                    _buildSwitch("RIB", "showRib"),
                  ],
                ),
                ExpansionTile(
                  leading: const Icon(Icons.person),
                  title: const Text("Informations Client", style: TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    _buildSwitch("Afficher le bloc Client", "showClientBox"),
                    _buildSwitch("Nom du Client", "showClientName"),
                    _buildSwitch("Adresse Client", "showClientDetail"),
                    _buildSwitch("Téléphone Client", "showClientPhone"),
                    _buildSwitch("NIF Client", "showClientNif"),
                    _buildSwitch("RC Client", "showClientRc"),
                  ],
                ),
                ExpansionTile(
                  leading: const Icon(Icons.table_chart),
                  title: const Text("Tableau des Articles", style: TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    _buildSwitch("Colonne Référence", "colRef"),
                    _buildSwitch("Colonne Prix Unitaire (TTC)", "colPriceTtc"),
                    _buildSwitch("Colonne Prix Unitaire (HT)", "colPriceHt"),
                    _buildSwitch("Colonne Total Ligne", "colTotal"),
                    _buildSwitch("Numérotation des lignes (#)", "showLineNumber"),
                    _buildSwitch("Images des produits", "showProductImages"),
                    _buildSwitch("Lignes Zébrées (A4/A5)", "zebraRows"),
                  ],
                ),
                ExpansionTile(
                  leading: const Icon(Icons.calculate),
                  title: const Text("Totaux & Pied de page", style: TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    _buildSwitch("Afficher Total HT", "showTotalHt"),
                    _buildSwitch("Afficher TVA", "showTva"),
                    _buildSwitch("Afficher Remise Articles", "showProductDiscount"),
                    _buildSwitch("Afficher Remise Globale", "showGlobalDiscount"),
                    _buildSwitch("Afficher Versements", "showPayments"),
                    _buildSwitch("Afficher Reste Dû (Actuel)", "showBalance"),
                    _buildSwitch("Afficher Ancienne Dette", "showOldBalance"),
                    _buildSwitch("Mode de Paiement (Espèce...)", "showPaymentMode"),
                    _buildSwitch("Nom du Vendeur", "showUser"),
                    _buildSwitch("Montant en lettres", "showLetters"),
                    _buildSwitch("Note Interne", "showInternalNote"),
                    _buildSwitch("Code Barre (Ticket)", "showBarcode"),
                    _buildSwitch("Cachet & Signature", "showSignature"),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),

          // BOUTON D'IMPRESSION
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
                icon: const Icon(Icons.print, color: Colors.white),
                label: const Text("Générer sur le PC", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                onPressed: () {
                  // On renvoie la configuration COMPLÈTE
                  final resultOptions = Map<String, dynamic>.from(_cfg);
                  resultOptions['format'] = _format; // On rajoute le format
                  
                  Navigator.pop(context, resultOptions);
                },
              ),
            ),
          )
        ],
      ),
    );
  }
}