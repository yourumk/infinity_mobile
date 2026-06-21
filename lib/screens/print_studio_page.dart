// =============================================================================
// 🖨️ PRINT STUDIO — Studio d'Impression 100% ESC/POS Natif
// =============================================================================
// Tour de contrôle d'impression thermique. AUCUN appel PDF/PC.
// Utilise uniquement PrintService pour ESC/POS via Bluetooth/Wi-Fi.
// Onglets : [Ventes] - [Achats]
// =============================================================================

import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../services/pdf_generator_service.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🟢 FIX DETECTION : Pour lire printer_type
import 'package:image_picker/image_picker.dart'; // 🖼️ FIX LOGO : Accès galerie

class PrintStudioPage extends StatefulWidget {
  final VoidCallback? onBack;

  const PrintStudioPage({super.key, this.onBack});

  @override
  State<PrintStudioPage> createState() => _PrintStudioPageState();
}

class _PrintStudioPageState extends State<PrintStudioPage> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final PrintService _print = PrintService();
  late TabController _tabController;

  // Données (plus de _charges)
  List<dynamic> _sales = [];
  List<dynamic> _purchases = [];

  bool _isLoading = true;
  bool _isPrinting = false;
  bool? _btConnected;
  String _printerType = 'bluetooth'; // 🟢 FIX DETECTION : Track type pour icône correcte
  String _printMode = 'escpos'; // 🖨️ Mode d'impression (escpos ou raster)

  // 🟢 FIX LOGO ET PREVIEW : 
  String? _logoB64;
  Map<String, dynamic> _companyInfo = {};
  Map<String, dynamic> _thermalConfig = {};

  // 🔒 RBAC : Rôle utilisateur mobile
  String _userRole = '';
  String _userName = '';
  bool get _isFieldUser => _userRole == 'chauffeur' || _userRole == 'vendeur';

  // Formatter compact
  final _fmt = NumberFormat.compactCurrency(locale: 'fr', symbol: 'DA', decimalDigits: 2);
  final _fmtFull = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserRole();
    _loadAllData();
    _checkPrinter();
    _loadPrintMode();
  }

  /// 🔒 Charge le rôle utilisateur pour adapter l'UI
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';
    final name = prefs.getString('user_full_name') ?? prefs.getString('username') ?? '';
    if (mounted) {
      setState(() {
        _userRole = role;
        _userName = name;
        // 🔒 Bloquer l'onglet Achats pour chauffeur/vendeur
        if (_isFieldUser) {
          _tabController.index = 0; // Forcer sur Ventes
        }
      });
    }
  }

  Future<void> _loadPrintMode() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> posOptions = {};
    try {
      if (prefs.containsKey('pos_options_cache')) {
        posOptions = jsonDecode(prefs.getString('pos_options_cache')!);
      }
      final cInfo = prefs.containsKey('company_info_cache') ? jsonDecode(prefs.getString('company_info_cache')!) : null;
      final thermal = prefs.containsKey('thermal_config_cache') ? jsonDecode(prefs.getString('thermal_config_cache')!) : null;
      final logo = prefs.getString('company_logo_cached_b64');
      if (mounted) {
        setState(() {
          if (cInfo != null) _companyInfo = cInfo;
          if (thermal != null) _thermalConfig = thermal;
          if (logo != null && logo.isNotEmpty) _logoB64 = logo;
          _printMode = posOptions['pos_print_mode']?.toString() ?? 'escpos';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _printMode = posOptions['pos_print_mode']?.toString() ?? 'escpos';
        });
      }
    }
  }

  Future<void> _savePrintMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> posOptions = {};
    try {
      if (prefs.containsKey('pos_options_cache')) {
        posOptions = jsonDecode(prefs.getString('pos_options_cache')!);
      }
    } catch (_) {}
    posOptions['pos_print_mode'] = mode;
    await prefs.setString('pos_options_cache', jsonEncode(posOptions));
    if (mounted) setState(() => _printMode = mode);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkPrinter() async {
    final connected = await _print.isConnected;
    // 🟢 FIX DETECTION : Lire aussi le type pour afficher la bonne icône
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString('printer_type') ?? 'bluetooth';
    if (mounted) setState(() { _btConnected = connected; _printerType = type; });
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    _checkPrinter(); // 🟢 FIX DETECTION : Rafraîchir statut imprimante au pull-to-refresh
    try {
      // 🔒 RBAC : Les chauffeurs/vendeurs ne voient que les ventes (filtrées côté serveur par mobile_user_id)
      final futures = <Future<List<dynamic>>>[
        _api.getSalesList(),
      ];
      if (!_isFieldUser) {
        futures.add(_api.getPurchasesList());
      }
      final results = await Future.wait(futures);
      if (mounted) {
        setState(() {
          _sales = results[0];
          _purchases = _isFieldUser ? [] : results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================
  // 🖨️ IMPRESSION ESC/POS DIRECTE
  // ============================================

  Future<void> _printSale(Map<String, dynamic> sale, {String format = 'Ticket', Map<String, dynamic>? clientDetail}) async {
    setState(() => _isPrinting = true);
    try {
      final items = await _api.getSaleItems(sale['id']);

      if (format == 'A4' || format == 'A5') {
        final pdfBytes = await PdfGeneratorService().generatePdfInvoice(
          saleData: sale,
          items: items,
          format: format,
          clientData: clientDetail,
          isReturn: (sale['is_return'] == 1 || sale['is_return'] == true)
        );
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat pdfFormat) async => pdfBytes,
          name: 'Facture_${sale['invoice_number'] ?? sale['id']}',
        );
        _showResult(true);
      } else {
        // 🧠 Utilise printSmartTicket pour basculer automatiquement entre ESC/POS et Raster
        final success = await _print.printSmartTicket(
          invoiceNumber: (sale['invoice_number'] ?? sale['id']).toString(),
          items: items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList(),
          totalTTC: double.tryParse(sale['total_amount']?.toString() ?? '0') ?? 0,
          totalHT: double.tryParse(sale['total_ht']?.toString() ?? '0') ?? 0,
          totalTVA: double.tryParse(sale['total_vat']?.toString() ?? '0') ?? 0,
          totalTimbre: double.tryParse(sale['timbre']?.toString() ?? '0') ?? 0,
          discount: double.tryParse(sale['discount_value']?.toString() ?? '0') ?? 0,
          amountPaid: double.tryParse(sale['amount_paid']?.toString() ?? sale['paid_amount']?.toString() ?? '0') ?? 0,
          clientName: sale['client_name'],
          paymentType: sale['payment_type'] ?? 'cash',
          isReturn: (sale['is_return'] == 1 || sale['is_return'] == true),
          note: sale['note'],
        );
        _showResult(success);
      }
    } catch (e) {
      _showResult(false);
    }
    if (mounted) setState(() => _isPrinting = false);
  }

  Future<void> _printPurchase(Map<String, dynamic> po, {String format = 'Ticket'}) async {
    setState(() => _isPrinting = true);
    try {
      final items = await _api.getPurchaseItems(po['id']);

      if (format == 'A4' || format == 'A5') {
        final pdfBytes = await PdfGeneratorService().generatePdfInvoice(
          saleData: po,
          items: items,
          format: format,
          isReturn: (po['is_return'] == 1 || po['is_return'] == true)
        );
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat pdfFormat) async => pdfBytes,
          name: 'Achat_${po['number'] ?? po['id']}',
        );
        _showResult(true);
      } else {
        final success = await _print.printPurchaseTicket(
          invoiceNumber: (po['number'] ?? po['id']).toString(),
          items: items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList(),
          totalTTC: double.tryParse(po['total_amount']?.toString() ?? '0') ?? 0,
          amountPaid: double.tryParse(po['amount_paid']?.toString() ?? po['paid_amount']?.toString() ?? '0') ?? 0,
          supplierName: po['supplier_name'],
          paymentType: po['payment_type'] ?? 'cash',
          isReturn: (po['is_return'] == 1 || po['is_return'] == true),
          note: po['note'],
        );
        _showResult(success);
      }
    } catch (e) {
      _showResult(false);
    }
    if (mounted) setState(() => _isPrinting = false);
  }

  void _showResult(bool success) {
    if (!mounted) return;
    _checkPrinter(); // 🟢 FIX DETECTION : Rafraîchir le statut après chaque impression
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? "✅ Impression réussie !" : "❌ Échec — Vérifiez l'imprimante"),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ============================================
  // 📄 APERÇU TICKET (BOTTOMSHEET)
  // ============================================

  /// Ouvre un BottomSheet élégant avec l'aperçu textuel du ticket de VENTE
  void _showSalePreview(Map<String, dynamic> sale) async {
    final GlobalKey previewKey = GlobalKey();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Charger les items pour l'aperçu
    List<dynamic> items = [];
    bool loadingItems = true;
    String? loadError;
    
    // 🟢 Données client enrichies
    Map<String, dynamic> clientDetail = {};
    bool loadingClient = true;
    List<dynamic> lastPayments = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Lancer le chargement au premier build
            if (loadingItems && items.isEmpty && loadError == null) {
              // 🟢 FIX PREVIEW : Interception pour le ticket de test (ID 9999)
              if (sale['id'] == 9999) {
                setSheetState(() {
                  items = sale['items'] ?? [];
                  loadingItems = false;
                });
              } else {
                _api.getSaleItems(sale['id']).then((result) {
                  setSheetState(() {
                    items = result;
                    loadingItems = false;
                  });
                }).catchError((e) {
                  setSheetState(() {
                    loadError = "Impossible de charger les articles";
                    loadingItems = false;
                  });
                });
              }
            }
            
            // 🟢 Charger les détails client si client_id existe
            if (loadingClient) {
              final clientId = sale['client_id'];
              if (clientId != null && clientId != 0 && clientId.toString().isNotEmpty) {
                _api.getTierDetails('client', clientId).then((detail) {
                  setSheetState(() {
                    clientDetail = detail;
                    lastPayments = List<dynamic>.from(detail['last_payments'] ?? []);
                    loadingClient = false;
                  });
                }).catchError((_) {
                  setSheetState(() => loadingClient = false);
                });
              } else {
                loadingClient = false;
              }
            }

            final amount = double.tryParse(sale['total_amount']?.toString() ?? '0') ?? 0;
            final totalHT = double.tryParse(sale['total_ht']?.toString() ?? '0') ?? 0;
            final totalTVA = double.tryParse(sale['total_vat']?.toString() ?? '0') ?? 0;
            final timbre = double.tryParse(sale['timbre']?.toString() ?? '0') ?? 0;
            final discount = double.tryParse(sale['discount_value']?.toString() ?? '0') ?? 0;
            final paid = double.tryParse(sale['amount_paid']?.toString() ?? sale['paid_amount']?.toString() ?? '0') ?? 0;
            final client = sale['client_name'] ?? 'Comptoir';
            final ref = sale['invoice_number'] ?? '#${sale['id']}';
            final dateRaw = sale['date']?.toString();
            final dateStr = dateRaw != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(dateRaw)) : '-';
            final payType = sale['payment_type'] ?? 'cash';
            final note = sale['note']?.toString();
            final remaining = amount - paid;
            final clientBalance = double.tryParse(clientDetail['balance']?.toString() ?? '0') ?? 0;

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C23) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  const SizedBox(height: 10),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),

                  // Titre
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(FontAwesomeIcons.receipt, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Ticket de Vente $ref", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                              Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Divider(color: Colors.grey.withOpacity(0.15), height: 1),

                  // Corps du ticket (scrollable)
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: RepaintBoundary(
                        key: previewKey,
                        child: Container(
                          // 🟢 FIX RASTER : Fond toujours blanc pour éviter le bloc noir à l'impression
                          color: Colors.white,
                          padding: const EdgeInsets.all(8),
                          child: Theme(
                            // 🟢 FIX RASTER : Forcer le thème clair pour les textes
                            data: ThemeData.light(),
                            child: Builder(builder: (ticketCtx) {
                              final isDark = false; // Forcer mode clair
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 🟢 FIX PREVIEW : Logo et En-tête Entreprise
                                  if (_logoB64 != null && _logoB64!.isNotEmpty)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: Builder(builder: (ctx) {
                                          try {
                                            String cleanB64 = _logoB64!;
                                            if (cleanB64.contains(',')) cleanB64 = cleanB64.split(',').last;
                                            return Image.memory(
                                              base64Decode(cleanB64),
                                              width: 120, height: 120,
                                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                            );
                                          } catch (e) {
                                            return const SizedBox.shrink();
                                          }
                                        }),
                                      ),
                                    ),
                                  if (_companyInfo.isNotEmpty && _companyInfo['name'] != null && _companyInfo['name'].toString().isNotEmpty)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: Text(
                                          _companyInfo['name'] ?? 'MON ENTREPRISE',
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
                                        ),
                                      ),
                                    ),

                                  // ─── BLOC CLIENT ENRICHI (identique à facturation.html) ───
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.04) : Colors.blue.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.blue.withOpacity(0.12)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Titre "Client"
                                Row(
                                  children: [
                                    Icon(FontAwesomeIcons.userTie, size: 14, color: isDark ? Colors.white70 : Colors.blue[700]),
                                    const SizedBox(width: 8),
                                    Text("Client", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: isDark ? Colors.white70 : Colors.blue[700], letterSpacing: 0.5)),
                                    const Spacer(),
                                    if (loadingClient)
                                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.blue)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                // Nom client
                                Text(client, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
                                
                                // Sous-client
                                if (clientDetail['sub_client_name']?.toString().isNotEmpty == true)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text("Contact : ${clientDetail['sub_client_name']}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                                  ),

                                // Activité
                                if (clientDetail['activity']?.toString().isNotEmpty == true)
                                  _clientField(Icons.business_outlined, "Activité", clientDetail['activity'].toString(), isDark),

                                // Adresse
                                if (clientDetail['address']?.toString().isNotEmpty == true)
                                  _clientField(Icons.location_on_outlined, "Adresse", clientDetail['address'].toString(), isDark),

                                // Téléphone
                                if (clientDetail['phone']?.toString().isNotEmpty == true)
                                  _clientField(Icons.phone_outlined, "Tél", clientDetail['phone'].toString(), isDark),

                                // Email
                                if (clientDetail['email']?.toString().isNotEmpty == true)
                                  _clientField(Icons.email_outlined, "Email", clientDetail['email'].toString(), isDark),

                                // ── Section Fiscale ──
                                if (_hasAnyFiscal(clientDetail)) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.03) : Colors.grey.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Wrap(
                                      spacing: 16,
                                      runSpacing: 6,
                                      children: [
                                        if (clientDetail['rc']?.toString().isNotEmpty == true)
                                          _fiscalBadge("RC", clientDetail['rc'].toString(), isDark),
                                        if (clientDetail['nif']?.toString().isNotEmpty == true)
                                          _fiscalBadge("NIF", clientDetail['nif'].toString(), isDark),
                                        if (clientDetail['nis']?.toString().isNotEmpty == true)
                                          _fiscalBadge("NIS", clientDetail['nis'].toString(), isDark),
                                        if ((clientDetail['art'] ?? clientDetail['artImposition'])?.toString().isNotEmpty == true)
                                          _fiscalBadge("ART", (clientDetail['art'] ?? clientDetail['artImposition']).toString(), isDark),
                                        if (clientDetail['rib']?.toString().isNotEmpty == true)
                                          _fiscalBadge("RIB", clientDetail['rib'].toString(), isDark),
                                      ],
                                    ),
                                  ),
                                ],

                                // ── Solde / Dette ──
                                if (clientBalance.abs() > 0.1)
                                  Container(
                                    margin: const EdgeInsets.only(top: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: clientBalance > 0 ? Colors.red.withOpacity(0.08) : Colors.green.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: (clientBalance > 0 ? Colors.red : Colors.green).withOpacity(0.2)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(clientBalance > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline, size: 16, color: clientBalance > 0 ? Colors.red : Colors.green),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            clientBalance > 0 ? "Dette totale : ${_fmtFull.format(clientBalance)}" : "Solde client OK ✓",
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: clientBalance > 0 ? Colors.red[700] : Colors.green[700]),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),
                          
                          _previewInfoRow("Paiement", payType == 'credit' ? 'Crédit' : 'Comptant', isDark),
                          if (note != null && note.isNotEmpty)
                            _previewInfoRow("Note", note, isDark),

                          const SizedBox(height: 12),
                          // En-tête articles
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(flex: 5, child: Text("Article", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]))),
                                Expanded(flex: 2, child: Text("Qté", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]), textAlign: TextAlign.center)),
                                Expanded(flex: 3, child: Text("Total", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]), textAlign: TextAlign.right)),
                              ],
                            ),
                          ),

                          // Articles
                          if (loadingItems)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal)),
                            )
                          else if (loadError != null)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Center(child: Text(loadError!, style: const TextStyle(color: Colors.red))),
                            )
                          else
                            ...items.map((item) {
                              final name = item['name']?.toString() ?? 'Article';
                              final qty = item['quantity'] ?? item['qty'] ?? 1;
                              final price = double.tryParse(item['unit_price']?.toString() ?? item['price']?.toString() ?? '0') ?? 0;
                              final lineTotal = price * (qty is num ? qty : (int.tryParse(qty.toString()) ?? 1));
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.08))),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 5, child: Text(name, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 2, child: Text("$qty", style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87), textAlign: TextAlign.center)),
                                    Expanded(flex: 3, child: Text(_fmtFull.format(lineTotal), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black), textAlign: TextAlign.right)),
                                  ],
                                ),
                              );
                            }),

                          const SizedBox(height: 12),
                          Divider(color: Colors.grey.withOpacity(0.2)),

                          // ─── TOTAUX ───
                          if (totalHT > 0)   _previewTotalRow("Total HT", totalHT, isDark),
                          if (totalTVA > 0)  _previewTotalRow("TVA", totalTVA, isDark),
                          if (timbre > 0)    _previewTotalRow("Timbre", timbre, isDark),
                          if (discount > 0)  _previewTotalRow("Remise", -discount, isDark, color: Colors.red),
                          _previewTotalRow("TOTAL TTC", amount, isDark, isBold: true, color: AppColors.primary),
                          _previewTotalRow("Montant Payé", paid, isDark),
                          if (remaining > 0.1)
                            _previewTotalRow("Reste à Payer", remaining, isDark, color: Colors.red, isBold: true),
                          
                          // ─── DETTE CLIENT ───
                          if (clientBalance > 0.1) ...[
                            const SizedBox(height: 4),
                            Divider(color: Colors.red.withOpacity(0.2)),
                            _previewTotalRow("Ancienne Dette", clientBalance - remaining, isDark, color: Colors.orange),
                            _previewTotalRow("Nouveau Solde", clientBalance, isDark, color: Colors.red, isBold: true),
                          ],
                          
                          // ─── HISTORIQUE PAIEMENTS ───
                          if (lastPayments.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.03) : Colors.green.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.withOpacity(0.1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(FontAwesomeIcons.clockRotateLeft, size: 12, color: Colors.green[700]),
                                      const SizedBox(width: 6),
                                      Text("Derniers Paiements", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.green[700])),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...lastPayments.take(5).map((p) {
                                    final pAmount = double.tryParse(p['amount']?.toString() ?? '0') ?? 0;
                                    final pDate = p['date']?.toString() ?? '';
                                    final pMethod = p['method']?.toString() ?? '';
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          Icon(Icons.circle, size: 6, color: Colors.green[400]),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(pDate, style: TextStyle(fontSize: 11, color: Colors.grey[500]))),
                                          if (pMethod.isNotEmpty)
                                            Container(
                                              margin: const EdgeInsets.only(right: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(pMethod, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
                                            ),
                                          Text(_fmtFull.format(pAmount), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green[700])),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),

          // Boutons d'action
                  SafeArea(
                    bottom: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text("Fermer"),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                                foregroundColor: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: PopupMenuButton<String>(
                                    initialValue: 'Ticket',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: [Colors.teal.withOpacity(0.15), Colors.teal.withOpacity(0.05)]),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.teal.withOpacity(0.3)),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.print, color: Colors.teal),
                                    ),
                                    onSelected: (format) {
                                      Navigator.pop(ctx);
                                      _printSale(Map<String, dynamic>.from(sale), format: format, clientDetail: clientDetail);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'Ticket', child: Text("Direct (Ticket 80mm)")),
                                      const PopupMenuItem(value: 'A5', child: Text("PDF (A5)")),
                                      const PopupMenuItem(value: 'A4', child: Text("PDF (A4)")),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton.icon(
                                    onPressed: _isPrinting
                                        ? null
                                        : () {
                                            Navigator.pop(ctx);
                                            _printSale(Map<String, dynamic>.from(sale), format: 'Ticket', clientDetail: clientDetail);
                                          },
                                    icon: const Icon(FontAwesomeIcons.print, size: 16),
                                    label: const Text("Imprimer", style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      elevation: 4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Ouvre un BottomSheet élégant avec l'aperçu textuel du ticket d'ACHAT
  void _showPurchasePreview(Map<String, dynamic> po) async {
    final GlobalKey previewKey = GlobalKey();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    List<dynamic> items = [];
    bool loadingItems = true;
    String? loadError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (loadingItems && items.isEmpty && loadError == null) {
              _api.getPurchaseItems(po['id']).then((result) {
                setSheetState(() {
                  items = result;
                  loadingItems = false;
                });
              }).catchError((e) {
                setSheetState(() {
                  loadError = "Impossible de charger les articles";
                  loadingItems = false;
                });
              });
            }

            final amount = double.tryParse(po['total_amount']?.toString() ?? '0') ?? 0;
            final totalHT = double.tryParse(po['total_ht']?.toString() ?? '0') ?? 0;
            final totalTVA = double.tryParse(po['total_vat']?.toString() ?? '0') ?? 0;
            final discount = double.tryParse(po['discount']?.toString() ?? '0') ?? 0;
            final paid = double.tryParse(po['amount_paid']?.toString() ?? po['paid_amount']?.toString() ?? '0') ?? 0;
            final supplier = po['supplier_name'] ?? 'Fournisseur';
            final ref = po['number'] ?? '#${po['id']}';
            final dateRaw = po['date']?.toString();
            final dateStr = dateRaw != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(dateRaw)) : '-';
            final payType = po['payment_type'] ?? 'cash';
            final note = po['note']?.toString();
            final remaining = amount - paid;

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C23) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),

                  // Titre
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(FontAwesomeIcons.truckFast, color: Colors.orange, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Bon d'Achat $ref", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                              Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Divider(color: Colors.grey.withOpacity(0.15), height: 1),

                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: RepaintBoundary(
                        key: previewKey,
                        child: Container(
                          // 🟢 FIX RASTER : Fond toujours blanc pour éviter le bloc noir à l'impression
                          color: Colors.white,
                          padding: const EdgeInsets.all(8),
                          child: Theme(
                            // 🟢 FIX RASTER : Forcer le thème clair pour les textes
                            data: ThemeData.light(),
                            child: Builder(builder: (ticketCtx) {
                              final isDark = false; // Forcer mode clair
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 🟢 FIX PREVIEW : Logo et En-tête Entreprise
                                  if (_logoB64 != null && _logoB64!.isNotEmpty)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: Builder(builder: (ctx) {
                                          try {
                                            String cleanB64 = _logoB64!;
                                            if (cleanB64.contains(',')) cleanB64 = cleanB64.split(',').last;
                                            return Image.memory(
                                              base64Decode(cleanB64),
                                              width: 120, height: 120,
                                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                            );
                                          } catch (e) {
                                            return const SizedBox.shrink();
                                          }
                                        }),
                                      ),
                                    ),
                                  if (_companyInfo.isNotEmpty && _companyInfo['name'] != null && _companyInfo['name'].toString().isNotEmpty)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: Text(
                                          _companyInfo['name'] ?? 'MON ENTREPRISE',
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
                                        ),
                                      ),
                                    ),
                                  _previewInfoRow("Fournisseur", supplier, isDark),
                          _previewInfoRow("Paiement", payType == 'credit' ? 'Crédit' : 'Comptant', isDark),
                          if (note != null && note.isNotEmpty)
                            _previewInfoRow("Note", note, isDark),

                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(flex: 5, child: Text("Article", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]))),
                                Expanded(flex: 2, child: Text("Qté", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]), textAlign: TextAlign.center)),
                                Expanded(flex: 3, child: Text("Total", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]), textAlign: TextAlign.right)),
                              ],
                            ),
                          ),

                          if (loadingItems)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal)),
                            )
                          else if (loadError != null)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Center(child: Text(loadError!, style: const TextStyle(color: Colors.red))),
                            )
                          else
                            ...items.map((item) {
                              final name = item['name']?.toString() ?? 'Article';
                              final qty = item['quantity'] ?? item['qty'] ?? 1;
                              final cost = double.tryParse(item['unit_cost']?.toString() ?? item['cost']?.toString() ?? item['unit_price']?.toString() ?? '0') ?? 0;
                              final lineTotal = cost * (qty is num ? qty : (int.tryParse(qty.toString()) ?? 1));
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.08))),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 5, child: Text(name, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 2, child: Text("$qty", style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87), textAlign: TextAlign.center)),
                                    Expanded(flex: 3, child: Text(_fmtFull.format(lineTotal), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black), textAlign: TextAlign.right)),
                                  ],
                                ),
                              );
                            }),

                          const SizedBox(height: 12),
                          Divider(color: Colors.grey.withOpacity(0.2)),

                          if (totalHT > 0)   _previewTotalRow("Total HT", totalHT, isDark),
                          if (totalTVA > 0)  _previewTotalRow("TVA", totalTVA, isDark),
                          if (discount > 0)  _previewTotalRow("Remise", -discount, isDark, color: Colors.red),
                          _previewTotalRow("TOTAL TTC", amount, isDark, isBold: true, color: Colors.orange),
                          _previewTotalRow("Montant Payé", paid, isDark),
                          if (remaining > 0.1)
                            _previewTotalRow("Reste (Dette)", remaining, isDark, color: Colors.red, isBold: true),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SafeArea(
                    bottom: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                              ),
                              child: Text("Fermer", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: PopupMenuButton<String>(
                                    initialValue: 'Ticket',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.teal.withOpacity(0.3)),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.print, color: Colors.teal),
                                    ),
                                    onSelected: (format) {
                                      Navigator.pop(ctx);
                                      _printPurchase(Map<String, dynamic>.from(po), format: format);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'Ticket', child: Text("Direct (Ticket 80mm)")),
                                      const PopupMenuItem(value: 'A5', child: Text("PDF (A5)")),
                                      const PopupMenuItem(value: 'A4', child: Text("PDF (A4)")),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton.icon(
                                    onPressed: _isPrinting
                                        ? null
                                        : () async {
                                            if (_printMode == 'raster') {
                                                setState(() => _isPrinting = true);
                                                try {
                                                  final boundary = previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                                                  if (boundary != null) {
                                                    ui.Image image = await boundary.toImage(pixelRatio: 1.0);
                                                    
                                                    // 🟢 FIX FREEZE : On extrait les pixels bruts RGBA au lieu de compresser en PNG
                                                    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
                                                    
                                                    if (byteData != null) {
                                                      final rawBytes = byteData.buffer.asUint8List();
                                                      // On envoie à la nouvelle fonction instantanée
                                                      await _print.printRasterRaw(rawBytes, image.width, image.height);
                                                    }
                                                  }
                                                } catch (e) {
                                                  debugPrint("Erreur capture raster: $e");
                                                }
                                                if (mounted) setState(() => _isPrinting = false);
                                                if (mounted) Navigator.pop(ctx);
                                            } else {
                                              Navigator.pop(ctx);
                                              _printPurchase(Map<String, dynamic>.from(po), format: 'Ticket');
                                            }
                                          },
                                    icon: const Icon(FontAwesomeIcons.print, size: 16),
                                    label: const Text("Imprimer", style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Helpers Client Bloc (identique à facturation.html) ──
  Widget _clientField(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            child: Text("$label :", style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87))),
        ],
      ),
    );
  }

  Widget _fiscalBadge(String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.blue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: (isDark ? Colors.white : Colors.blue).withOpacity(0.1)),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: "$label: ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isDark ? Colors.white60 : Colors.blue[800])),
          TextSpan(text: value, style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey[700])),
        ]),
      ),
    );
  }

  bool _hasAnyFiscal(Map<String, dynamic> d) {
    return (d['rc']?.toString().isNotEmpty == true) ||
           (d['nif']?.toString().isNotEmpty == true) ||
           (d['nis']?.toString().isNotEmpty == true) ||
           (d['art']?.toString().isNotEmpty == true) ||
           (d['artImposition']?.toString().isNotEmpty == true) ||
           (d['rib']?.toString().isNotEmpty == true);
  }

  // Helpers pour le BottomSheet d'aperçu
  Widget _previewInfoRow(String label, String value, bool isDark) {

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text("$label : ", style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black))),
        ],
      ),
    );
  }

  Widget _previewTotalRow(String label, double value, bool isDark, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.w900 : FontWeight.w500, color: color ?? (isDark ? Colors.white70 : Colors.black54))),
          Text(_fmtFull.format(value), style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.w900 : FontWeight.w600, color: color ?? (isDark ? Colors.white : Colors.black))),
        ],
      ),
    );
  }

  // ============================================
  // 🎨 BUILD UI
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // ─── HEADER (Exploite le notch) ───
          Container(
            padding: EdgeInsets.fromLTRB(20, topPadding + 8, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF1A2E35), const Color(0xFF0F1A1D)]
                    : [const Color(0xFF009688), const Color(0xFF00796B)],
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              boxShadow: [
                BoxShadow(color: Colors.teal.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onBack ?? () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(FontAwesomeIcons.print, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Print Studio", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                          Text("Impression thermique directe", style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
                        ],
                      ),
                    ),
                    // ⚙️ Bouton Settings
                    GestureDetector(
                      onTap: () => _showSettingsModal(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.tune_rounded, size: 20, color: Colors.white),
                      ),
                    ),
                    // 🔵 Statut Imprimante
                    GestureDetector(
                      onTap: () async {
                        await _print.connectSavedPrinter();
                        _checkPrinter();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (_btConnected == true ? Colors.greenAccent : Colors.redAccent).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: (_btConnected == true ? Colors.greenAccent : Colors.redAccent).withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _btConnected == true
                                  ? (_printerType == 'network' ? Icons.wifi : Icons.bluetooth_connected)
                                  : (_printerType == 'network' ? Icons.wifi_off : Icons.bluetooth_disabled),
                              size: 14,
                              color: _btConnected == true ? Colors.greenAccent : Colors.redAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _btConnected == true ? "OK" : "Off",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _btConnected == true ? Colors.greenAccent : Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ─── 🖨️ TOGGLE MODE IMPRESSION ───
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _savePrintMode('escpos'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _printMode == 'escpos' ? Colors.white.withOpacity(0.25) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.text_fields, size: 14, color: _printMode == 'escpos' ? Colors.white : Colors.white54),
                                const SizedBox(width: 6),
                                Text("Texte (ESC/POS)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _printMode == 'escpos' ? Colors.white : Colors.white54)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _savePrintMode('raster'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _printMode == 'raster' ? Colors.white.withOpacity(0.25) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_outlined, size: 14, color: _printMode == 'raster' ? Colors.white : Colors.white54),
                                const SizedBox(width: 6),
                                Text("Image (PNG)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _printMode == 'raster' ? Colors.white : Colors.white54)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ─── ONGLETS + BADGE RÔLE ───
                if (_isFieldUser) ...[
                  // 🔒 Badge indiquant le filtre actif
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_pin_circle, size: 14, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text(
                          "${_userName.isNotEmpty ? _userName : _userRole} — Mes Ventes uniquement",
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.amber),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    onTap: (index) {
                      // 🔒 Bloquer l'onglet Achats pour les chauffeurs/vendeurs
                      if (_isFieldUser && index == 1) {
                        _tabController.index = 0;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("L'onglet Achats n'est pas disponible pour le rôle ${_userRole == 'chauffeur' ? 'Chauffeur' : 'Vendeur'}"),
                            backgroundColor: Colors.orange[700],
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withOpacity(0.25),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorPadding: const EdgeInsets.all(3),
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: [
                      Tab(text: _isFieldUser ? "Mes Ventes" : "Ventes"),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("Achats", style: TextStyle(
                              color: _isFieldUser ? Colors.white24 : null,
                              decoration: _isFieldUser ? TextDecoration.lineThrough : null,
                            )),
                            if (_isFieldUser) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.lock_outline, size: 12, color: Colors.white24),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              ],
            ),
          ),

          // ─── PRINTING INDICATOR ───
          if (_isPrinting)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.teal.withOpacity(0.15), Colors.teal.withOpacity(0.05)]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal)),
                  const SizedBox(width: 12),
                  Text("Impression en cours...", style: TextStyle(color: Colors.teal[700], fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),

          // ─── CONTENU ───
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : TabBarView(
                    controller: _tabController,
                    // 🔒 Bloquer le swipe vers Achats pour les chauffeurs/vendeurs
                    physics: _isFieldUser ? const NeverScrollableScrollPhysics() : null,
                    children: [
                      _buildSalesList(isDark),
                      // 🔒 Onglet Achats : verrouillé ou normal
                      _isFieldUser
                          ? _buildLockedTab(isDark)
                          : _buildPurchasesList(isDark),
                    ],
                  ),
          ),

        ],
      ),
    );
  }

  // ============================================
  // 📋 ONGLET VENTES
  // ============================================
  Widget _buildSalesList(bool isDark) {
    if (_sales.isEmpty) return _buildEmptyState("Aucune vente", FontAwesomeIcons.basketShopping);

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: Colors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: _sales.length,
        itemBuilder: (ctx, i) {
          final sale = _sales[i];
          final amount = double.tryParse(sale['total_amount']?.toString() ?? '0') ?? 0;
          final client = sale['client_name'] ?? 'Comptoir';
          final ref = sale['invoice_number'] ?? '#${sale['id']}';
          final dateRaw = sale['date']?.toString();
          final dateStr = dateRaw != null ? DateFormat('dd/MM HH:mm').format(DateTime.parse(dateRaw)) : '-';
          final status = sale['status']?.toString().toLowerCase() ?? '';

          return _buildDocCard(
            isDark: isDark,
            icon: FontAwesomeIcons.receipt,
            iconColor: AppColors.primary,
            title: client,
            subtitle: "$dateStr • $ref",
            amount: amount,
            amountColor: AppColors.primary,
            status: status,
            onTap: () => _showSalePreview(Map<String, dynamic>.from(sale)),
            onPrint: () => _printSale(Map<String, dynamic>.from(sale)),
          );
        },
      ),
    );
  }

  // ============================================
  // 🔒 ONGLET VERROUILLÉ (Chauffeur/Vendeur)
  // ============================================
  Widget _buildLockedTab(bool isDark) {
    final roleLabel = _userRole == 'chauffeur' ? 'Chauffeur' : 'Vendeur';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.withOpacity(0.08),
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: isDark ? Colors.white24 : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Achats non disponible",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white38 : Colors.grey[500],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Le rôle $roleLabel ne permet pas d'accéder aux bons d'achat.\nSeules vos ventes personnelles sont affichées.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white24 : Colors.grey[400],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_pin_circle, size: 16, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Text(
                    "$roleLabel : ${_userName.isNotEmpty ? _userName : 'Vous'}",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.amber[700]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // 📋 ONGLET ACHATS
  // ============================================
  Widget _buildPurchasesList(bool isDark) {
    if (_purchases.isEmpty) return _buildEmptyState("Aucun achat", FontAwesomeIcons.truckFast);

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: Colors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: _purchases.length,
        itemBuilder: (ctx, i) {
          final po = _purchases[i];
          final amount = double.tryParse(po['total_amount']?.toString() ?? '0') ?? 0;
          final supplier = po['supplier_name'] ?? 'Fournisseur';
          final ref = po['number'] ?? '#${po['id']}';
          final dateRaw = po['date']?.toString();
          final dateStr = dateRaw != null ? DateFormat('dd/MM HH:mm').format(DateTime.parse(dateRaw)) : '-';
          final status = po['status']?.toString().toLowerCase() ?? '';

          return _buildDocCard(
            isDark: isDark,
            icon: FontAwesomeIcons.truckFast,
            iconColor: Colors.orange,
            title: supplier,
            subtitle: "$dateStr • $ref",
            amount: amount,
            amountColor: Colors.orange,
            status: status,
            onTap: () => _showPurchasePreview(Map<String, dynamic>.from(po)),
            onPrint: () => _printPurchase(Map<String, dynamic>.from(po)),
          );
        },
      ),
    );
  }

  // ============================================
  // 🧩 COMPOSANTS RÉUTILISABLES
  // ============================================

  Widget _buildDocCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required double amount,
    required Color amountColor,
    required String status,
    required VoidCallback onTap,
    required VoidCallback onPrint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isDark ? const Color(0xFF1C1C23) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: iconColor.withOpacity(0.08),
          highlightColor: iconColor.withOpacity(0.04),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                // Icône
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 12),
                // Titre + sous-titre
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(child: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (status.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _buildStatusChip(status),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Montant
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_fmt.format(amount), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: amountColor)),
                  ),
                ),
                const SizedBox(width: 8),
                // 🖨️ Bouton impression
                Material(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: _isPrinting ? null : onPrint,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        FontAwesomeIcons.print,
                        size: 16,
                        color: _isPrinting ? Colors.grey : Colors.teal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color chipColor;
    String label;

    switch (status) {
      case 'paid':
        chipColor = Colors.green;
        label = 'Payé';
        break;
      case 'partial':
        chipColor = Colors.orange;
        label = 'Partiel';
        break;
      case 'unpaid':
      case 'credit':
        chipColor = Colors.red;
        label = 'Crédit';
        break;
      default:
        chipColor = Colors.grey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: chipColor)),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 50, color: Colors.grey.withOpacity(0.25)),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadAllData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("Rafraîchir"),
            style: TextButton.styleFrom(foregroundColor: Colors.teal),
          ),
        ],
      ),
    );
  }

  // ============================================
  // ⚙️ MODAL SETTINGS (Config Thermique + Entreprise)
  // ============================================
  void _showSettingsModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C23) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.tune_rounded, color: Colors.deepPurple, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Réglages Impression", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                              Text("Configuration ticket thermique", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(color: Colors.grey.withOpacity(0.15), height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // === SECTION: MODE IMPRESSION ===
                          _settingsSection("Mode d'impression", Icons.print, Colors.teal, isDark),
                          const SizedBox(height: 8),
                          _settingsTile(
                            isDark,
                            title: "Mode Image Universel (PNG/Raster)",
                            subtitle: "Compatible toutes imprimantes. Convertit le ticket en image.",
                            icon: Icons.image_outlined,
                            isActive: _printMode == 'raster',
                            onTap: () {
                              _savePrintMode('raster');
                              setSheetState(() {});
                            },
                          ),
                          _settingsTile(
                            isDark,
                            title: "Mode Texte Rapide (ESC/POS)",
                            subtitle: "Impression rapide en texte natif. Moins de mémoire.",
                            icon: Icons.text_fields,
                            isActive: _printMode == 'escpos',
                            onTap: () {
                              _savePrintMode('escpos');
                              setSheetState(() {});
                            },
                          ),
                          const SizedBox(height: 20),

                         // === SECTION: CONNEXION IMPRIMANTE ===
                          _settingsSection("Connexion Imprimante", Icons.bluetooth_connected, Colors.indigo, isDark),
                          const SizedBox(height: 8),
                        _settingsTile(
                            isDark,
                            title: "Configurer le Bluetooth",
                            subtitle: "Sélectionner une imprimante jumelée",
                            icon: Icons.bluetooth,
                            isActive: _printerType == 'bluetooth',
                            onTap: () async {
                              Navigator.pop(ctx);
                              
                              // 1. Demande de permission
                              bool hasPerms = await _print.requestBluetoothPermissions();
                              if (!hasPerms) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                    content: Text("❌ Permissions refusées. Autorisez le Bluetooth et le GPS dans les paramètres de l'application."),
                                    backgroundColor: Colors.red,
                                  ));
                                }
                                return;
                              }

                              // 2. Scan des appareils
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text("🔍 Recherche des imprimantes jumelées..."),
                                  backgroundColor: Colors.blue,
                                  duration: Duration(seconds: 1),
                                ));
                              }
                              
                              final devices = await _print.getPairedDevices();
                              
                              if (mounted) {
                                // 3. Si aucun appareil n'est trouvé
                                if (devices.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                    content: Text("⚠️ Aucune imprimante trouvée. Avez-vous jumelé l'imprimante dans les paramètres Bluetooth du téléphone ?"),
                                    backgroundColor: Colors.orange,
                                    duration: Duration(seconds: 4),
                                  ));
                                  return;
                                }

                                // 4. Affichage de la liste
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Imprimantes Bluetooth"),
                                    content: SizedBox(
                                      width: double.maxFinite,
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: devices.length,
                                        itemBuilder: (c, i) => ListTile(
                                          leading: const Icon(Icons.print, color: Colors.indigo),
                                          title: Text(devices[i].name),
                                          subtitle: Text(devices[i].macAdress),
                                          onTap: () async {
                                            final prefs = await SharedPreferences.getInstance();
                                            await prefs.setString('printer_type', 'bluetooth');
                                            await prefs.setString('mac_printer', devices[i].macAdress);
                                            Navigator.pop(context);
                                            _checkPrinter();
                                            
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                              content: Text("✅ Imprimante ${devices[i].name} sélectionnée !"),
                                              backgroundColor: Colors.green,
                                            ));
                                          },
                                        ),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler"))
                                    ],
                                  ),
                                );
                              }
                            },
                          ),
                          _settingsTile(
                            isDark,
                            title: "Configurer le Wi-Fi / Réseau",
                            subtitle: "Saisir l'adresse IP de l'imprimante",
                            icon: Icons.wifi,
                            isActive: _printerType == 'network',
                            onTap: () async {
                              Navigator.pop(ctx);
                              TextEditingController ipCtrl = TextEditingController();
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text("Imprimante Réseau"),
                                  content: TextField(
                                    controller: ipCtrl,
                                    decoration: const InputDecoration(hintText: "Ex: 192.168.1.100"),
                                    keyboardType: TextInputType.number,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () async {
                                        final prefs = await SharedPreferences.getInstance();
                                        await prefs.setString('printer_type', 'network');
                                        await prefs.setString('network_printer', ipCtrl.text.trim());
                                        Navigator.pop(context);
                                        _checkPrinter();
                                      },
                                      child: const Text("Sauvegarder"),
                                    )
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // === SECTION: ENTREPRISE ===
                          _settingsSection("Informations Entreprise", Icons.business, Colors.blue, isDark),
                          const SizedBox(height: 8),
                          _settingsTile(
                            isDark,
                            title: "Modifier les infos entreprise",
                            subtitle: "Nom, adresse, téléphone, NIF, RC...",
                            icon: Icons.edit_outlined,
                            isActive: false,
                            onTap: () {
                              Navigator.pop(ctx);
                              _showCompanyEditSheet();
                            },
                          ),
                          _settingsTile(
                            isDark,
                            title: "Changer le logo",
                            subtitle: "Uploadez un logo depuis votre galerie",
                            icon: Icons.add_photo_alternate_outlined,
                            isActive: false,
                            onTap: () async {
                              Navigator.pop(ctx);
                              await _pickAndUploadLogo();
                            },
                          ),
                          const SizedBox(height: 20),

                          // === SECTION: CONFIG TICKET ===
                          _settingsSection("Configuration Ticket", Icons.receipt_long, Colors.orange, isDark),
                          const SizedBox(height: 8),
                          _settingsTile(
                            isDark,
                            title: "Personnaliser le ticket",
                            subtitle: "Colonnes, blocs, message de pied de page",
                            icon: Icons.dashboard_customize_outlined,
                            isActive: false,
                            onTap: () {
                              Navigator.pop(ctx);
                              _showTicketConfigSheet();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _settingsSection(String title, IconData icon, Color color, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isDark ? Colors.white70 : Colors.black54)),
      ],
    );
  }

  Widget _settingsTile(bool isDark, {required String title, required String subtitle, required IconData icon, required bool isActive, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isActive ? Colors.teal.withOpacity(0.1) : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isActive ? Colors.teal.withOpacity(0.4) : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: isActive ? Colors.teal : (isDark ? Colors.white54 : Colors.grey[600])),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
                      Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                ),
                if (isActive) const Icon(Icons.check_circle, size: 20, color: Colors.teal),
                if (!isActive) Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // 🏢 MODIFIER INFOS ENTREPRISE
  // ============================================
  void _showCompanyEditSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> company = {};
    try {
      if (prefs.containsKey('company_info_cache')) {
        company = jsonDecode(prefs.getString('company_info_cache')!);
      }
    } catch (_) {}

    final nameCtrl = TextEditingController(text: company['name']?.toString() ?? '');
    final addressCtrl = TextEditingController(text: company['address']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: company['phone']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: company['email']?.toString() ?? '');
    final activityCtrl = TextEditingController(text: company['activity']?.toString() ?? '');
    final rcCtrl = TextEditingController(text: company['rc']?.toString() ?? '');
    final nifCtrl = TextEditingController(text: company['nif']?.toString() ?? '');
    final nisCtrl = TextEditingController(text: company['nis']?.toString() ?? '');
    final artCtrl = TextEditingController(text: company['art']?.toString() ?? '');
    final ribCtrl = TextEditingController(text: company['rib']?.toString() ?? '');

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C23) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.business, color: Colors.blue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text("Infos Entreprise", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: Colors.grey.withOpacity(0.15), height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    children: [
                      _companyField(nameCtrl, "Nom de l'entreprise", Icons.store, isDark),
                      _companyField(activityCtrl, "Activité", Icons.work_outline, isDark),
                      _companyField(addressCtrl, "Adresse", Icons.location_on_outlined, isDark),
                      _companyField(phoneCtrl, "Téléphone", Icons.phone_outlined, isDark),
                      _companyField(emailCtrl, "Email", Icons.email_outlined, isDark),
                      _companyField(rcCtrl, "RC", Icons.assignment_outlined, isDark),
                      _companyField(nifCtrl, "NIF", Icons.numbers, isDark),
                      _companyField(nisCtrl, "NIS", Icons.numbers, isDark),
                      _companyField(artCtrl, "Article d'imposition", Icons.article_outlined, isDark),
                      _companyField(ribCtrl, "RIB", Icons.account_balance_outlined, isDark),
                    ],
                  ),
                ),
              ),
              SafeArea(
                bottom: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final fields = {
                          'name': nameCtrl.text, 'address': addressCtrl.text,
                          'phone': phoneCtrl.text, 'email': emailCtrl.text,
                          'activity': activityCtrl.text, 'rc': rcCtrl.text,
                          'nif': nifCtrl.text, 'nis': nisCtrl.text,
                          'art': artCtrl.text, 'rib': ribCtrl.text,
                        };
                        Navigator.pop(ctx);
                        final ok = await _api.updateCompanyInfo(fields);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok ? "✅ Infos entreprise sauvegardées" : "❌ Erreur de sauvegarde"),
                            backgroundColor: ok ? Colors.green : Colors.red,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.all(16),
                          ));
                        }
                      },
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text("Enregistrer", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _companyField(TextEditingController ctrl, String label, IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
          prefixIcon: Icon(icon, size: 18, color: Colors.grey[400]),
          filled: true,
          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blue, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  // ============================================
  // 🖼️ UPLOAD LOGO
  // ============================================
  Future<void> _pickAndUploadLogo() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 256,
        imageQuality: 85,
      );

      if (image == null) {
        // L'utilisateur a annulé la sélection
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text("📸 Upload du logo en cours..."),
          ],
        ),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
      ));

      // Lire les bytes et convertir en Base64
      final bytes = await image.readAsBytes();
      final base64Data = 'data:image/png;base64,${base64Encode(bytes)}';

      // Upload via l'API existante
      final logoUrl = await _api.uploadCompanyLogo(base64Data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(logoUrl != null ? "✅ Logo mis à jour avec succès !" : "❌ Erreur lors de l'upload"),
        backgroundColor: logoUrl != null ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    } catch (e) {
      debugPrint('Erreur pick logo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("❌ Erreur: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  // ============================================
  // 🧪 TICKET DE TEST (PREVIEW)
  // ============================================
  void _showTestTicketPreview() {
    final fakeSale = {
      'id': 9999,
      'invoice_number': 'TEST-0001',
      'date': DateTime.now().toIso8601String(),
      'client_name': 'Client de Test',
      'total_amount': 2500,
      'total_ht': 2100,
      'total_vat': 400,
      'timbre': 0,
      'discount_value': 0,
      'amount_paid': 2500,
      'payment_type': 'cash',
      'note': 'Ceci est un ticket généré pour tester vos paramètres.',
      'items': [
        {'name': 'Produit A (Test)', 'qty': 2, 'price': 500, 'unit_price': 500},
        {'name': 'Produit B (Test)', 'qty': 1, 'price': 1500, 'unit_price': 1500},
      ]
    };
    _showSalePreview(fakeSale);
  }

// ============================================
  // 📋 CONFIG TICKET THERMIQUE
  // ============================================
  void _showTicketConfigSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Map<String, dynamic> config = await _api.getThermalConfig();
    final footerCtrl = TextEditingController(text: config['footer_msg']?.toString() ?? 'Merci de votre visite !');

    // 🟢 LECTURE TAILLE PAPIER (80mm ou 58mm)
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> posOptions = {};
    try {
      if (prefs.containsKey('pos_options_cache')) {
        posOptions = jsonDecode(prefs.getString('pos_options_cache')!);
      }
    } catch (_) {}
    String currentPaperSize = posOptions['pos_receipt_size']?.toString() ?? '80mm';

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final cols = config['columns'] ?? {};
            final blocsCompany = config['blocs_company'] ?? {};
            final blocsClient = config['blocs_client'] ?? {};

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C23) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.receipt_long, color: Colors.orange, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text("Config Ticket", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: Colors.grey.withOpacity(0.15), height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🟢 NOUVEAU : FORMAT PAPIER
                          _settingsSection("Format de l'imprimante", Icons.format_size, Colors.pink, isDark),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setSheetState(() => currentPaperSize = '80mm'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: currentPaperSize == '80mm' ? Colors.pink.withOpacity(0.15) : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey[100]),
                                      border: Border.all(color: currentPaperSize == '80mm' ? Colors.pink : Colors.transparent),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(child: Text("Standard (80mm)", style: TextStyle(fontWeight: FontWeight.bold, color: currentPaperSize == '80mm' ? Colors.pink : (isDark ? Colors.white70 : Colors.black87)))),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setSheetState(() => currentPaperSize = '58mm'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: currentPaperSize == '58mm' ? Colors.pink.withOpacity(0.15) : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey[100]),
                                      border: Border.all(color: currentPaperSize == '58mm' ? Colors.pink : Colors.transparent),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(child: Text("Petit (58mm)", style: TextStyle(fontWeight: FontWeight.bold, color: currentPaperSize == '58mm' ? Colors.pink : (isDark ? Colors.white70 : Colors.black87)))),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Colonnes Ticket
                          _settingsSection("Colonnes du tableau", Icons.table_chart_outlined, Colors.teal, isDark),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _configChip("Quantité", cols['qty'] != false, isDark, (v) { setSheetState(() { cols['qty'] = v; config['columns'] = cols; }); }),
                            _configChip("Prix Unit.", cols['price'] != false, isDark, (v) { setSheetState(() { cols['price'] = v; config['columns'] = cols; }); }),
                            _configChip("Total", cols['total'] != false, isDark, (v) { setSheetState(() { cols['total'] = v; config['columns'] = cols; }); }),
                            _configChip("Référence", cols['ref'] == true, isDark, (v) { setSheetState(() { cols['ref'] = v; config['columns'] = cols; }); }),
                            _configChip("TVA %", cols['tva'] == true, isDark, (v) { setSheetState(() { cols['tva'] = v; config['columns'] = cols; }); }),
                          ]),
                          const SizedBox(height: 20),

                          // Blocs Entreprise
                          _settingsSection("Blocs Entreprise", Icons.business, Colors.blue, isDark),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _configChip("Nom", blocsCompany['name'] != false, isDark, (v) { setSheetState(() { blocsCompany['name'] = v; config['blocs_company'] = blocsCompany; }); }),
                            _configChip("Activité", blocsCompany['activity'] != false, isDark, (v) { setSheetState(() { blocsCompany['activity'] = v; config['blocs_company'] = blocsCompany; }); }),
                            _configChip("Adresse", blocsCompany['address'] != false, isDark, (v) { setSheetState(() { blocsCompany['address'] = v; config['blocs_company'] = blocsCompany; }); }),
                            _configChip("Téléphone", blocsCompany['phone'] != false, isDark, (v) { setSheetState(() { blocsCompany['phone'] = v; config['blocs_company'] = blocsCompany; }); }),
                            _configChip("RC", blocsCompany['rc'] != false, isDark, (v) { setSheetState(() { blocsCompany['rc'] = v; config['blocs_company'] = blocsCompany; }); }),
                            _configChip("NIF", blocsCompany['nif'] != false, isDark, (v) { setSheetState(() { blocsCompany['nif'] = v; config['blocs_company'] = blocsCompany; }); }),
                            _configChip("NIS", blocsCompany['nis'] != false, isDark, (v) { setSheetState(() { blocsCompany['nis'] = v; config['blocs_company'] = blocsCompany; }); }),
                            _configChip("ART", blocsCompany['art'] != false, isDark, (v) { setSheetState(() { blocsCompany['art'] = v; config['blocs_company'] = blocsCompany; }); }),
                          ]),
                          const SizedBox(height: 20),

                          // Blocs Client
                          _settingsSection("Blocs Client", Icons.person_outline, Colors.green, isDark),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _configChip("Nom", blocsClient['name'] != false, isDark, (v) { setSheetState(() { blocsClient['name'] = v; config['blocs_client'] = blocsClient; }); }),
                            _configChip("Adresse", blocsClient['address'] == true, isDark, (v) { setSheetState(() { blocsClient['address'] = v; config['blocs_client'] = blocsClient; }); }),
                            _configChip("Téléphone", blocsClient['phone'] == true, isDark, (v) { setSheetState(() { blocsClient['phone'] = v; config['blocs_client'] = blocsClient; }); }),
                            _configChip("NIF", blocsClient['nif'] == true, isDark, (v) { setSheetState(() { blocsClient['nif'] = v; config['blocs_client'] = blocsClient; }); }),
                            _configChip("RC", blocsClient['rc'] == true, isDark, (v) { setSheetState(() { blocsClient['rc'] = v; config['blocs_client'] = blocsClient; }); }),
                          ]),
                          const SizedBox(height: 20),

                          // Options
                          _settingsSection("Options", Icons.settings_outlined, Colors.deepPurple, isDark),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _configChip("Logo", config['show_logo'] != false, isDark, (v) { setSheetState(() { config['show_logo'] = v; }); }),
                            _configChip("Code-barre", config['show_barcode'] == true, isDark, (v) { setSheetState(() { config['show_barcode'] = v; }); }),
                          ]),
                          const SizedBox(height: 16),

                          // Message de pied de page
                          TextField(
                            controller: footerCtrl,
                            style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                            decoration: InputDecoration(
                              labelText: "Message fin de ticket",
                              labelStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              prefixIcon: Icon(Icons.message_outlined, size: 18, color: Colors.grey[400]),
                              filled: true,
                              fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            onChanged: (val) => config['footer_msg'] = val,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showTestTicketPreview();
                              },
                              icon: const Icon(Icons.preview_outlined, size: 18, color: Colors.blue),
                              label: const Text("Aperçu Test", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                side: BorderSide(color: Colors.blue.withOpacity(0.5)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                // 🟢 SAUVEGARDE FORMAT PAPIER
                                posOptions['pos_receipt_size'] = currentPaperSize;
                                await prefs.setString('pos_options_cache', jsonEncode(posOptions));

                                config['footer_msg'] = footerCtrl.text;
                                await _api.saveThermalConfig(config);
                                Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: const Text("✅ Configuration ticket sauvegardée"),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    margin: const EdgeInsets.all(16),
                                  ));
                                }
                              },
                              icon: const Icon(Icons.save_outlined, size: 18),
                              label: const Text("Sauvegarder", style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _configChip(String label, bool isActive, bool isDark, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87))),
      selected: isActive,
      onSelected: onChanged,
      selectedColor: Colors.teal,
      checkmarkColor: Colors.white,
      backgroundColor: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: isActive ? Colors.teal : Colors.grey.withOpacity(0.2)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    );
  }
}
