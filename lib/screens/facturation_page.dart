// 🟢 FIX EXTREME RELIABILITY : facturation_page.dart — Architecture 100% Native (Zéro WebView)
// Abandon total de webview_flutter → Rendu PDF natif via PdfPreview

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import '../services/api_service.dart';
import '../services/print_service.dart';
import '../utils/html_invoice_generator.dart';
import '../core/constants.dart';

class FacturationPage extends StatefulWidget {
  final Map<String, dynamic> saleData;
  final String docType; // 'sale' or 'purchase'

  const FacturationPage({
    super.key,
    required this.saleData,
    this.docType = 'sale',
  });

  @override
  State<FacturationPage> createState() => _FacturationPageState();
}

class _FacturationPageState extends State<FacturationPage> {
  final ApiService _api = ApiService();
  final PrintService _print = PrintService();

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMsg = '';
  String _selectedFormat = 'Ticket';
  bool _saveAsDefault = false;

  List<dynamic> _items = [];
  Map<String, dynamic> _companyInfo = {};

  // 🟢 FIX EXTREME RELIABILITY : Adieu WebView, bonjour rendu PDF natif
  Uint8List? _pdfBytes;
  String _generatedHtml = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ============================================================
  // 🟢 FIX EXTREME RELIABILITY : CHARGEMENT AVEC CACHE INTELLIGENT
  // ============================================================
  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedFormat = prefs.getString('default_print_format') ?? 'Ticket';

      if (prefs.containsKey('company_info_cache')) {
        try {
          _companyInfo = json.decode(prefs.getString('company_info_cache')!);
        } catch (_) {
          _companyInfo = {'name': 'MON ENTREPRISE'};
        }
      }

      // 🟢 FIX EXTREME RELIABILITY : Cache intelligent — on bloque la boucle de requêtes
      // Si les articles sont déjà présents dans saleData, on ne fetch PAS l'API
      if (widget.saleData.containsKey('items') &&
          widget.saleData['items'] != null &&
          (widget.saleData['items'] as List).isNotEmpty) {
        _items = widget.saleData['items'];
      } else {
        if (widget.docType == 'sale') {
          _items = await _api
              .getSaleItems(widget.saleData['id'])
              .timeout(const Duration(seconds: 5), onTimeout: () => []);
        } else {
          _items = await _api
              .getPurchaseItems(widget.saleData['id'])
              .timeout(const Duration(seconds: 5), onTimeout: () => []);
        }
      }

      // 🟢 FIX EXTREME RELIABILITY : On attend la conversion complète HTML → PDF
      await _generatePreview();
    } catch (e) {
      debugPrint("🟢 FIX EXTREME RELIABILITY : Erreur fatale : $e");
      _hasError = true;
      _errorMsg = "Erreur : $e";
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 🟢 FIX EXTREME RELIABILITY : MOTEUR DE CONVERSION SANS WEBVIEW
  //    HTML → Printing.convertHtml → Uint8List (PDF natif)
  // ============================================================
  Future<void> _generatePreview() async {
    // --- Restructuration des données (identique au fix précédent) ---
    Map<String, dynamic> formattedData = {};
    String contextType = widget.docType == 'sale' ? 'sales' : 'purchases';
    String resolvedDocType = '';

    if (widget.docType == 'sale') {
      formattedData = {'sale': widget.saleData, 'items': _items};
      bool isReturn = widget.saleData['is_return'] == 1 ||
          widget.saleData['is_return'] == true;
      resolvedDocType = isReturn ? 'avoir' : 'facture';
    } else {
      formattedData = {'po': widget.saleData, 'items': _items};
      resolvedDocType = 'bon_reception';
    }

    // --- Config complète (anti null-crash) ---
    Map<String, dynamic> defaultConfig = {
      'format': _selectedFormat,
      'color': '#6f2dbd',
      'headerStyle': 'classic_boxes',
      'fontFamily': 'Inter',
      'fontSize': 12.0,
      'fontSizeHeader': 12.0,
      'fontSizeTable': 11.0,
      'fontSizeFooter': 12.0,
      'paddingY': 5.0,
      'logoScale': 100.0,
      'ticketWidth': 80.0,
      // En-tête & Société
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
      'showActivity': false,
      'showRib': false,
      'showUser': false,
      // Client
      'showClientBox': true,
      'showClientName': true,
      'showSubClient': true,
      'showClientDetail': true,
      'showClientPhone': true,
      'showClientEmail': false,
      'showClientRc': true,
      'showClientNif': true,
      'showClientNis': true,
      'showClientArt': false,
      'showClientRib': false,
      'showClientActivity': false,
      'showInternalNote': true,
      // Colonnes
      'showLineNumber': true,
      'colRef': true,
      'colDesc': true,
      'showColis': false,
      'colQty': true,
      'colPriceHt': false,
      'colPriceTtc': true,
      'colTva': true,
      'colTotalHt': true,
      'colTotalTtc': true,
      // Finances
      'showTva': true,
      'showTimbre': true,
      'showPaymentMode': true,
      'showProductDiscount': false,
      'showGlobalDiscount': true,
      'showTotalHt': true,
      'showFinalTotal': true,
      'showLetters': false,
      'showPayments': false,
      'showBalance': true,
      'showOldBalance': true,
      // Options avancées
      'zebraRows': false,
      'showStamp': false,
      'showSignature': true,
      'showSignatureImg': false,
      'showSignatureClient': false,
      'showFooter': true,
      'showBarcode': false,
      // Textes
      'showCustomMsg': true,
      'customMsg': 'Merci de votre visite et à bientôt !',
      'footerMsg': 'Merci de votre confiance.',
    };

    // 🟢 FIX EXTREME RELIABILITY : Await obligatoire sur le chargement de config
    await _loadSavedConfig(defaultConfig);

    // --- Génération du HTML ---
    String rawHtml = HtmlInvoiceGenerator.generate(
      contextType,
      resolvedDocType,
      formattedData,
      defaultConfig,
      _companyInfo,
    );

    // 🟢 FIX EXTREME RELIABILITY : Injection meta viewport (sécurité supplémentaire pour le moteur de rendu)
    if (!rawHtml.contains('viewport')) {
      rawHtml = rawHtml.replaceFirst(
        '<head>',
        '<head><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">',
      );
    }

    _generatedHtml = rawHtml;

    // 🟢 FIX EXTREME RELIABILITY : Conversion directe HTML → PDF binaire (Zéro WebView Android)
    final pdfPageFormat = _selectedFormat == 'Ticket'
        ? PdfPageFormat.roll80
        : (_selectedFormat == 'A5' ? PdfPageFormat.a5 : PdfPageFormat.a4);

    _pdfBytes = await Printing.convertHtml(
      html: rawHtml,
      format: pdfPageFormat,
    );

    if (mounted) setState(() {});
  }

  // 🟢 FIX EXTREME RELIABILITY : Chargement config sauvegardée
  Future<void> _loadSavedConfig(Map<String, dynamic> defaultConfig) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedConfig = prefs.getString('studio_config');
      if (savedConfig != null) {
        final parsed = jsonDecode(savedConfig);
        if (parsed is Map) {
          defaultConfig.addAll(Map<String, dynamic>.from(parsed));
        }
      }
    } catch (_) {}
    defaultConfig['format'] = _selectedFormat;
  }

  // ============================================================
  // 🟢 FIX EXTREME RELIABILITY : IMPRESSION OPTIMISÉE
  //    Le PDF est DÉJÀ calculé → impression A4/A5 instantanée
  // ============================================================
  Future<void> _handlePrint() async {
    if (_pdfBytes == null && _generatedHtml.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("❌ Aucun document généré. Réessayez."),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    if (_saveAsDefault) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('default_print_format', _selectedFormat);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("⏳ Impression en cours..."),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    try {
      if (_selectedFormat == 'Ticket') {
        // 🟢 FIX EXTREME RELIABILITY : Impression Ticket via ESC/POS Bluetooth (utilise le HTML brut)
        final success = await _print.printRichHtmlTicket(_generatedHtml);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success
                  ? "✅ Ticket imprimé avec succès !"
                  : "❌ Échec d'impression Bluetooth"),
              backgroundColor: success ? AppColors.success : AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        // 🟢 FIX EXTREME RELIABILITY : Impression INSTANTANÉE — on envoie les bytes déjà calculés !
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => _pdfBytes!,
          name: 'Document_${widget.saleData['id']}',
        );
      }
    } catch (e) {
      debugPrint("🟢 FIX EXTREME RELIABILITY : Erreur impression: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Erreur d'impression : $e"),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // ============================================================
  // 🟢 FIX EXTREME RELIABILITY : BUILD UI (Purple Glossy, 100% Natif)
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF0F3F8),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              "Infinity Studio",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF0F3F8),
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
      ),
      body: _isLoading
          ? Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D2D44) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withOpacity(0.2),
                        blurRadius: 30),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 3),
                    SizedBox(height: 16),
                    Text("Génération du document...",
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            )
          : _hasError
              ? _buildErrorScreen(isDark)
              : Column(
                  children: [
                    // ========== TOOLBAR ==========
                    _buildToolbar(isDark),

                    // ========== PREVIEW ZONE (100% NATIF) ==========
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.primary.withOpacity(0.1),
                                blurRadius: 20,
                                spreadRadius: -5),
                            BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        // 🟢 FIX EXTREME RELIABILITY : ADIEU WEBVIEW, BONJOUR RENDU NATIF FLUTTER !
                        child: _pdfBytes == null
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.primary))
                            : PdfPreview(
                                build: (format) async => _pdfBytes!,
                                useActions: false,
                                allowPrinting: false,
                                allowSharing: false,
                                canChangeOrientation: false,
                                canChangePageFormat: false,
                                canDebug: false,
                                maxPageWidth:
                                    _selectedFormat == 'Ticket' ? 350 : 800,
                                scrollViewDecoration: const BoxDecoration(
                                    color: Colors.transparent),
                                pdfPreviewPageDecoration: const BoxDecoration(
                                    color: Colors.white),
                              ),
                      ),
                    ),

                    // ========== BOUTON IMPRIMER ==========
                    _buildPrintButton(isDark),
                  ],
                ),
    );
  }

  // ============================================================
  // 🟢 FIX EXTREME RELIABILITY : WIDGETS EXTRAITS (LISIBILITÉ)
  // ============================================================
  Widget _buildToolbar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Sélecteur de format
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedFormat,
                dropdownColor:
                    isDark ? const Color(0xFF2D2D44) : Colors.white,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
                iconEnabledColor: Colors.white,
                items: const [
                  DropdownMenuItem(
                      value: 'Ticket', child: Text("🎫 Ticket (80mm)")),
                  DropdownMenuItem(value: 'A5', child: Text("📄 PDF A5")),
                  DropdownMenuItem(value: 'A4', child: Text("📃 PDF A4")),
                ],
                onChanged: (val) async {
                  if (val != null) {
                    setState(() {
                      _selectedFormat = val;
                      _pdfBytes = null; // Reset pour afficher le loader
                    });
                    // 🟢 FIX EXTREME RELIABILITY : Régénération complète au changement de format
                    await _generatePreview();
                  }
                },
              ),
            ),
          ),

          const Spacer(),

          // Checkbox "Par défaut"
          GestureDetector(
            onTap: () => setState(() => _saveAsDefault = !_saveAsDefault),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient:
                        _saveAsDefault ? AppColors.primaryGradient : null,
                    color:
                        _saveAsDefault ? null : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _saveAsDefault
                          ? Colors.transparent
                          : (isDark ? Colors.white30 : Colors.black26),
                      width: 2,
                    ),
                  ),
                  child: _saveAsDefault
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 16)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  "Par défaut",
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrintButton(bool isDark) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF2D2D44) : Colors.white)
                .withOpacity(0.85),
            border: Border(
                top: BorderSide(color: AppColors.primary.withOpacity(0.15))),
          ),
          child: GestureDetector(
            onTap: _handlePrint,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.print_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    "IMPRIMER",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 64, color: AppColors.error.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              "Erreur de chargement",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMsg,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black45),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                  _errorMsg = '';
                  _pdfBytes = null;
                });
                _loadData();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Réessayer"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
