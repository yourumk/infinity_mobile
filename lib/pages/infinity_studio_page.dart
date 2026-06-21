// 🟢 FIX STUDIO MOBILE FLUTTER : Page InfinityStudio complète avec UI Purple Glossy
// Clone de facturation.html avec TabBar, GlassCard, Preview, Paramètres exhaustifs

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../utils/html_invoice_generator.dart';
import '../core/constants.dart';
import '../widgets/glass_card.dart';

// 🟢 FIX STUDIO MOBILE FLUTTER : Page complète avec câblage API -> HTML -> Preview -> Impression
class InfinityStudioPage extends StatefulWidget {
  const InfinityStudioPage({super.key});

  @override
  State<InfinityStudioPage> createState() => _InfinityStudioPageState();
}

class _InfinityStudioPageState extends State<InfinityStudioPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 🟢 FIX STUDIO MOBILE FLUTTER : Singleton API (pas de Provider.of qui crasherait)
  final ApiService _api = ApiService();
  final PrintService _printService = PrintService();

  // 🟢 FIX STUDIO MOBILE FLUTTER : Config exhaustive (~55 clés) clone de DEFAULT_CONFIG_A4 du PC
  Map<String, dynamic> _config = {
    'format': 'A4',
    'fontFamily': 'Inter',
    'color': '#6f2dbd',
    'headerStyle': 'classic_boxes',
    'logoScale': 100.0,
    'fontSize': 12.0,
    'fontSizeHeader': 0.0,
    'fontSizeTable': 0.0,
    'fontSizeFooter': 0.0,
    'paddingY': 5.0,
    'ticketWidth': 80.0,

    // Société
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
    'showActivity': true,
    'showRib': false,
    'showUser': false,

    // Client
    'showClientBox': true,
    'showClientName': true,
    'showSubClient': true,
    'showClientDetail': true,
    'showClientPhone': true,
    'showClientEmail': true,
    'showClientRc': true,
    'showClientNif': true,
    'showClientNis': true,
    'showClientArt': false,
    'showClientRib': false,
    'showClientActivity': true,
    'showInternalNote': true,

    // Colonnes
    'showLineNumber': true,
    'showProductImages': false,
    'colRef': true,
    'colDesc': true,
    'showColis': false,
    'colQty': true,
    'colPriceHt': false,
    'colPriceTtc': true,
    'colTva': false,
    'colTotalHt': false,
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
    'showStamp': true,
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

  // 🟢 FIX STUDIO MOBILE FLUTTER : Logo B64 Cache et Capture UI
  String? _logoB64;
  final GlobalKey _previewKey = GlobalKey();

  // 🟢 FIX V2 : CompanyInfo COMPLET (tous les champs du PC)
  Map<String, dynamic> _companyInfo = {
    'name': 'MON ENTREPRISE',
    'address': '',
    'phone': '',
    'email': '',
    'activity': '',
    'rc': '',
    'nif': '',
    'nis': '',
    'art': '',
    'rib': '',
    'logo_url': '',
    'signature_url': '',
  };

  bool _isLoading = false;
  List<dynamic> _salesList = [];
  List<dynamic> _purchasesList = [];
  List<dynamic> _clientsList = [];
  List<dynamic> _suppliersList = [];

  // 🟢 FIX STUDIO MOBILE FLUTTER : Liste des 16 thèmes CSS
  static const List<Map<String, String>> _themes = [
    {'key': 'classic_boxes', 'label': '📦 Classic Boxes'},
    {'key': 'classic_elegant', 'label': '✨ Classic Elegant'},
    {'key': 'minimal_lines', 'label': '━ Minimal Lines'},
    {'key': 'ultra_compact', 'label': '📐 Ultra Compact'},
    {'key': 'compact_clean', 'label': '🧹 Compact Clean'},
    {'key': 'compact_minimal', 'label': '📄 Compact Minimal'},
    {'key': 'elegant_centered', 'label': '🎯 Elegant Centered'},
    {'key': 'style_color_band', 'label': '🎨 Color Band'},
    {'key': 'pro_modern', 'label': '💼 Pro Modern'},
    {'key': 'style_split_modern', 'label': '🔀 Split Modern'},
    {'key': 'style_bold_title', 'label': '🔤 Bold Title'},
    {'key': 'style_apple_glossy', 'label': '🍎 Apple Glossy'},
    {'key': 'corporate_elegant', 'label': '🏢 Corporate'},
    {'key': 'style_creative_pill', 'label': '💊 Creative Pill'},
    {'key': 'minimal_grid', 'label': '▦ Minimal Grid'},
    {'key': 'style_vintage_paper', 'label': '📜 Vintage Paper'},
    {'key': 'style_elegant_gold', 'label': '🥇 Elegant Gold'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadConfig();
    _loadCompanyInfo();
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 🟢 FIX STUDIO MOBILE FLUTTER : Chargement du companyInfo depuis SharedPreferences
  Future<void> _loadCompanyInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('company_info_cache')) {
        final cached = json.decode(prefs.getString('company_info_cache')!);
        setState(() {
          _companyInfo = {..._companyInfo, ...Map<String, dynamic>.from(cached)};
        });
      }
    } catch (e) {
      debugPrint("[Studio] Erreur chargement companyInfo cache: $e");
    }
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedConfig = prefs.getString('studio_config');
    final thermalConfig = prefs.getString('thermal_config_cache');
    final logoCached = prefs.getString('company_logo_cached_b64');
    
    setState(() {
      if (savedConfig != null) {
        try { _config = {..._config, ...jsonDecode(savedConfig)}; } catch (_) {}
      }
      if (thermalConfig != null) {
        try { _config = {..._config, ...jsonDecode(thermalConfig)}; } catch (_) {}
      }
      if (logoCached != null && logoCached.isNotEmpty) {
        _logoB64 = logoCached;
      }
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('studio_config', jsonEncode(_config));
  }

  // 🟢 FIX V2 : Sauvegarder les infos entreprise dans SharedPreferences
  Future<void> _saveCompanyInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_info_cache', jsonEncode(_companyInfo));
  }

  // 🟢 FIX ZERO WEBVIEW : Timeout + cache guard pour stopper les boucles de fetch
  Future<void> _fetchData({bool force = false}) async {
    // 🟢 FIX ZERO WEBVIEW : Si on a déjà les données en mémoire, on ne re-fetch PAS
    if (!force && _salesList.isNotEmpty) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      _salesList = await _api.getSalesList(limit: 50).timeout(
        const Duration(seconds: 8), onTimeout: () => _salesList.isNotEmpty ? _salesList : [],
      );
      try { _purchasesList = await _api.getPurchasesList(limit: 50).timeout(
        const Duration(seconds: 8), onTimeout: () => _purchasesList.isNotEmpty ? _purchasesList : [],
      ); } catch (e) {}
      try { _clientsList = await _api.getTiersList('client', '').timeout(
        const Duration(seconds: 8), onTimeout: () => _clientsList.isNotEmpty ? _clientsList : [],
      ); } catch (e) {}
      try { _suppliersList = await _api.getTiersList('supplier', '').timeout(
        const Duration(seconds: 8), onTimeout: () => _suppliersList.isNotEmpty ? _suppliersList : [],
      ); } catch (e) {}
    } catch (e) {
      debugPrint("[Studio] Error fetching data: $e");
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ==================================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : FLUX DE GÉNÉRATION COMPLET
  //    API -> Fetch Details -> Generate HTML -> Preview -> Print
  // ==================================================================
  // 🟢 FIX EXTREME RELIABILITY : _openPreview avec timeout, cache items, et pré-conversion PDF
  Future<void> _openPreview(String contextType, Map<String, dynamic> docData) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 1. AFFICHE LE LOADER VIOLET
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2D44) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 30)],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
              SizedBox(height: 16),
              Text("Chargement...", style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );

    // 2. FETCH DES DÉTAILS COMPLETS VIA API (avec timeout strict)
    Map<String, dynamic> fullData = {};
    String docType = 'facture';

    try {
      if (contextType == 'sales') {
        final items = docData.containsKey('_mock_items') 
            ? docData['_mock_items'] 
            : await _api.getSaleItems(docData['id']).timeout(
                const Duration(seconds: 5), onTimeout: () => [],
              );
        // 🟢 FIX V2 : Injection des infos client depuis le cache mémoire
        Map<String, dynamic>? clientInfo;
        final clientId = docData['client_id'];
        if (clientId != null) {
          try {
            clientInfo = _clientsList.firstWhere(
              (c) => c['id'] == clientId || c['id']?.toString() == clientId.toString(),
            ) as Map<String, dynamic>?;
          } catch (_) {}
        }
        fullData = {
          'sale': docData,
          'items': items,
          if (clientInfo != null) 'client': clientInfo,
        };
        docType = (docData['is_return'] == 1 || docData['is_return'] == true) ? 'avoir' : 'facture';
      }
      else if (contextType == 'purchases') {
        final items = await _api.getPurchaseItems(docData['id']).timeout(
          const Duration(seconds: 5), onTimeout: () => [],
        );
        // 🟢 FIX V2 : Injection des infos fournisseur depuis le cache mémoire
        Map<String, dynamic>? supplierInfo;
        final supplierId = docData['supplier_id'];
        if (supplierId != null) {
          try {
            supplierInfo = _suppliersList.firstWhere(
              (s) => s['id'] == supplierId || s['id']?.toString() == supplierId.toString(),
            ) as Map<String, dynamic>?;
          } catch (_) {}
        }
        fullData = {
          'po': docData,
          'items': items,
          if (supplierInfo != null) 'supplier': supplierInfo,
        };
        docType = 'bon_reception';
      }
      else if (contextType == 'clients') {
        final details = await _api.getTierDetails('client', docData['id']).timeout(
          const Duration(seconds: 5), onTimeout: () => <String, dynamic>{},
        );
        fullData = {
          'client': docData,
          'sales': details['last_sales'] ?? [],
          'payments': details['last_payments'] ?? [],
          'oldBalance': 0,
          'globalBalance': double.tryParse(details['balance']?.toString() ?? '0') ?? 0.0,
        };
        docType = 'releve_client';
      }
      else if (contextType == 'suppliers') {
        final details = await _api.getTierDetails('supplier', docData['id']).timeout(
          const Duration(seconds: 5), onTimeout: () => <String, dynamic>{},
        );
        fullData = {
          'supplier': docData,
          'pos': details['last_purchases'] ?? [],
          'payments': details['last_payments'] ?? [],
          'oldBalance': 0,
          'globalBalance': double.tryParse(details['balance']?.toString() ?? '0') ?? 0.0,
        };
        docType = 'releve_fourn';
      }
    } catch (e) {
      debugPrint("[Studio] Error fetching details: $e");
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur : Impossible de récupérer les détails. ($e)"),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    // 3. RÉCUPÉRATION DU CACHE companyInfo
    await _loadCompanyInfo();

    // 4. GÉNÉRATION DU HTML
    String htmlContent = HtmlInvoiceGenerator.generate(contextType, docType, fullData, _config, _companyInfo);

    // 🟢 FIX ZERO WEBVIEW : Injection meta viewport
    if (!htmlContent.contains('viewport')) {
      htmlContent = htmlContent.replaceFirst(
        '<head>',
        '<head><meta name="viewport" content="width=device-width, initial-scale=1.0">',
      );
    }

    if (!mounted) return;
    // 🟢 FIX ZERO WEBVIEW : On passe les données structurées pour l'aperçu Flutter natif
    _showPreviewSheet(htmlContent, docType, contextType, fullData);
  }

  // ==================================================================
  // 🟢 FIX ZERO WEBVIEW : PREVIEW SHEET 100% FLUTTER NATIF
  //    Zéro PdfPreview, zéro Printing.convertHtml, zéro WebView
  //    Aperçu document rendu en widgets Flutter + impression PDF à la demande
  // ==================================================================
  void _showPreviewSheet(String htmlContent, String docType, String contextType, Map<String, dynamic> fullData) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String currentHtml = htmlContent;
        String currentDocType = docType;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            List<Map<String, String>> availableDocTypes = [];
            if (contextType == 'sales') {
              availableDocTypes = [
                {'key': 'facture', 'label': 'Facture'},
                {'key': 'bl', 'label': 'Bon de Livraison'},
                {'key': 'proforma', 'label': 'Proforma'},
                {'key': 'ticket', 'label': 'Ticket'},
                {'key': 'avoir', 'label': 'Avoir / Retour'},
              ];
            } else if (contextType == 'purchases') {
              availableDocTypes = [
                {'key': 'bon_reception', 'label': 'Bon Réception'},
                {'key': 'bon_commande', 'label': 'Bon Commande'},
                {'key': 'facture', 'label': 'Facture Achat'},
              ];
            } else if (contextType == 'clients') {
              availableDocTypes = [
                {'key': 'releve_client', 'label': 'Relevé Compte'},
                {'key': 'releve_detail_client', 'label': 'Relevé Détaillé'},
                {'key': 'bon_versement_client', 'label': 'Hist. Versements'},
              ];
            } else if (contextType == 'suppliers') {
              availableDocTypes = [
                {'key': 'releve_fourn', 'label': 'Relevé Fourn.'},
                {'key': 'releve_detail_fourn', 'label': 'Relevé Détaillé'},
                {'key': 'bon_versement_fourn', 'label': 'Hist. Paiements'},
              ];
            }

            // 🟢 FIX ZERO WEBVIEW : Regénère juste le HTML (instantané, zéro PDF)
            void regenerateHtml(String newDocType, String newFormat) {
              _config['format'] = newFormat;
              _saveConfig();
              String newHtml = HtmlInvoiceGenerator.generate(contextType, newDocType, fullData, _config, _companyInfo);
              if (!newHtml.contains('viewport')) {
                newHtml = newHtml.replaceFirst('<head>',
                  '<head><meta name="viewport" content="width=device-width, initial-scale=1.0">',
                );
              }
              currentHtml = newHtml;
              currentDocType = newDocType;
              setModalState(() {});
            }

            // 🟢 FIX ZERO WEBVIEW : Extraction des données pour l'aperçu Flutter natif
            final isSale = (contextType == 'sales');
            final isPurchase = (contextType == 'purchases');
            final isTier = (contextType == 'clients' || contextType == 'suppliers');
            final header = isSale ? (fullData['sale'] ?? {}) : (isPurchase ? (fullData['po'] ?? {}) : (fullData['client'] ?? fullData['supplier'] ?? {}));
            final items = fullData['items'] as List<dynamic>? ?? [];
            final clientName = isSale
                ? (header['client_name'] ?? 'Client Comptoir')
                : (isPurchase ? (header['supplier_name'] ?? 'Fournisseur') : (header['name'] ?? 'Tiers'));
            final docNumber = header['invoice_number'] ?? header['number'] ?? header['id']?.toString() ?? '-';
            final docDate = header['date']?.toString().split(' ').first ?? '-';
            final total = _p(header['total_amount'] ?? header['total'] ?? 0);
            final paid = _p(header['amount_paid'] ?? 0);
            final rest = total - paid;

            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5FA),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 40, offset: const Offset(0, -5))],
              ),
              child: Column(
                children: [
                  // --- HANDLE BAR ---
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 50, height: 5,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  // --- HEADER ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text("Aperçu Document",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _config['format'],
                              dropdownColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
                              iconEnabledColor: Colors.white,
                              // 🟢 FIX V2 : Le texte sélectionné est blanc (sur gradient), mais les items du menu sont sombres
                              selectedItemBuilder: (BuildContext context) {
                                return ['A4', 'A5', 'Ticket'].map((e) => Text(e, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))).toList();
                              },
                              items: ['A4', 'A5', 'Ticket'].map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 13)),
                              )).toList(),
                              onChanged: (val) {
                                if (val != null) regenerateHtml(currentDocType, val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _openSettingsSheet();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.tune_rounded, color: AppColors.primary, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 🟢 FIX ZERO WEBVIEW : Dropdown Type de Document
                  if (availableDocTypes.isNotEmpty)
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: availableDocTypes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, idx) {
                          final dt = availableDocTypes[idx];
                          final isActive = dt['key'] == currentDocType;
                          return GestureDetector(
                            onTap: () => regenerateHtml(dt['key']!, _config['format'] ?? 'A4'),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: isActive ? AppColors.primaryGradient : null,
                                color: isActive ? null : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isActive ? Colors.transparent : AppColors.primary.withOpacity(0.2)),
                              ),
                              child: Center(
                                child: Text(dt['label']!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                    color: isActive ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 8),

                  // ======================================================
                  // 🟢 FIX ZERO WEBVIEW : APERÇU DOCUMENT 100% FLUTTER NATIF
                  //    Zéro PdfPreview, zéro WebView, zéro GPU crash
                  // ======================================================
                  Expanded(
                    child: RepaintBoundary(
                      key: _previewKey,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 25, spreadRadius: -5),
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // === EN-TÊTE SOCIÉTÉ ===
                            if (_config['showHeader'] == true) Center(
                              child: Column(
                                children: [
                                  if (_config['showLogo'] == true && _logoB64 != null && _logoB64!.isNotEmpty)
                                    Builder(
                                      builder: (context) {
                                        try {
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: Image.memory(
                                              base64Decode(_logoB64!),
                                              width: 100,
                                              height: 100,
                                              errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
                                            ),
                                          );
                                        } catch (e) {
                                          return const SizedBox.shrink();
                                        }
                                      },
                                    ),
                                  if (_config['showName'] == true && (_companyInfo['name']?.toString().isNotEmpty == true))
                                    Text(_companyInfo['name'] ?? 'MON ENTREPRISE',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(int.parse((_config['color'] ?? '#6f2dbd').replaceFirst('#', '0xFF')))),
                                    ),
                                  if (_config['showActivity'] == true && (_companyInfo['activity'] ?? '').toString().isNotEmpty)
                                    Text(_companyInfo['activity'], style: const TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
                                  if (_config['showAddress'] == true && (_companyInfo['address'] ?? '').toString().isNotEmpty)
                                    Text(_companyInfo['address'], style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                  if (_config['showPhone'] == true && (_companyInfo['phone'] ?? '').toString().isNotEmpty)
                                    Text('Tél: ${_companyInfo['phone']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                  if (_config['showEmail'] == true && (_companyInfo['email'] ?? '').toString().isNotEmpty)
                                    Text(_companyInfo['email'], style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    children: [
                                      if (_config['showRc'] == true && (_companyInfo['rc'] ?? '').toString().isNotEmpty)
                                        Text('RC: ${_companyInfo['rc']}', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                                      if (_config['showNif'] == true && (_companyInfo['nif'] ?? '').toString().isNotEmpty)
                                        Text('NIF: ${_companyInfo['nif']}', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                                      if (_config['showNis'] == true && (_companyInfo['nis'] ?? '').toString().isNotEmpty)
                                        Text('NIS: ${_companyInfo['nis']}', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                                      if (_config['showArt'] == true && (_companyInfo['art'] ?? '').toString().isNotEmpty)
                                        Text('ART: ${_companyInfo['art']}', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                                    ],
                                  ),
                                  if (_config['showRib'] == true && (_companyInfo['rib'] ?? '').toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text('RIB: ${_companyInfo['rib']}', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                                    ),
                                ],
                              ),
                            ),

                            Divider(height: 24, thickness: 2, color: Color(int.parse((_config['color'] ?? '#6f2dbd').replaceFirst('#', '0xFF')))),

                            // === TITRE DOCUMENT ===
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    Color(int.parse((_config['color'] ?? '#6f2dbd').replaceFirst('#', '0xFF'))),
                                    Color(int.parse((_config['color'] ?? '#9B59B6').replaceFirst('#', '0xFF'))).withValues(alpha: 0.7),
                                  ]),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  currentDocType.replaceAll('_', ' ').toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // === INFOS DOCUMENT ===
                            if (!isTier) ...[
                              _previewRow('N° Document', docNumber, isBold: true),
                              _previewRow('Date', docDate),
                              if (_config['showClientBox'] == true) ...[
                                _previewRow(isSale ? 'Client' : 'Fournisseur', clientName, isBold: true),
                                // 🟢 FIX V2 : Infos client détaillées depuis le cache
                                if (fullData['client'] != null) ...[
                                  if (_config['showClientDetail'] == true && (fullData['client']['address'] ?? '').toString().isNotEmpty)
                                    _previewRow('Adresse', fullData['client']['address'].toString()),
                                  if (_config['showClientPhone'] == true && (fullData['client']['phone'] ?? '').toString().isNotEmpty)
                                    _previewRow('Tél.', fullData['client']['phone'].toString()),
                                  if (_config['showClientNif'] == true && (fullData['client']['nif'] ?? '').toString().isNotEmpty)
                                    _previewRow('NIF', fullData['client']['nif'].toString()),
                                  if (_config['showClientRc'] == true && (fullData['client']['rc'] ?? '').toString().isNotEmpty)
                                    _previewRow('RC', fullData['client']['rc'].toString()),
                                  if (_config['showClientNis'] == true && (fullData['client']['nis'] ?? '').toString().isNotEmpty)
                                    _previewRow('NIS', fullData['client']['nis'].toString()),
                                ],
                                if (fullData['supplier'] != null) ...[
                                  if (_config['showClientDetail'] == true && (fullData['supplier']['address'] ?? '').toString().isNotEmpty)
                                    _previewRow('Adresse', fullData['supplier']['address'].toString()),
                                  if (_config['showClientPhone'] == true && (fullData['supplier']['phone'] ?? '').toString().isNotEmpty)
                                    _previewRow('Tél.', fullData['supplier']['phone'].toString()),
                                ],
                              ],
                              if (_config['showSubClient'] == true && (header['sub_client_name'] ?? '').toString().isNotEmpty)
                                _previewRow('Contact', header['sub_client_name'].toString()),
                              if (_config['showPaymentMode'] == true && header['payment_type'] != null)
                                _previewRow('Paiement', header['payment_type'].toString().toUpperCase()),
                              const Divider(height: 20),
                            ],

                            // === BLOC TIERS (Relevés) ===
                            if (isTier) ...[
                              _previewRow('Nom', clientName, isBold: true),
                              if ((header['phone'] ?? '').toString().isNotEmpty)
                                _previewRow('Téléphone', header['phone'].toString()),
                              if ((header['address'] ?? '').toString().isNotEmpty)
                                _previewRow('Adresse', header['address'].toString()),
                              if ((header['nif'] ?? '').toString().isNotEmpty)
                                _previewRow('NIF', header['nif'].toString()),
                              if ((header['rc'] ?? '').toString().isNotEmpty)
                                _previewRow('RC', header['rc'].toString()),
                              const Divider(height: 20),
                            ],

                            // === TABLEAU ARTICLES ===
                            if (items.isNotEmpty && !isTier) ...[
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                border: Border.all(color: Color(int.parse((_config['color'] ?? '#6f2dbd').replaceFirst('#', '0xFF'))).withValues(alpha: 0.3)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Color(int.parse((_config['color'] ?? '#6f2dbd').replaceFirst('#', '0xFF'))).withValues(alpha: 0.1),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                                      ),
                                      child: const Row(
                                        children: [
                                          SizedBox(width: 28, child: Text('#', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                                          Expanded(flex: 4, child: Text('Désignation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                                          SizedBox(width: 36, child: Text('Qté', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                                          SizedBox(width: 60, child: Text('P.U', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                                          SizedBox(width: 70, child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                                        ],
                                      ),
                                    ),
                                    ...items.asMap().entries.map((e) {
                                      final i = e.key;
                                      final item = e.value;
                                      final isZebra = i % 2 == 1;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        color: isZebra ? const Color(0xFFF8F5FF) : Colors.transparent,
                                        child: Row(
                                          children: [
                                            SizedBox(width: 28, child: Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black45))),
                                            Expanded(flex: 4, child: Text(item['product_name']?.toString() ?? item['designation']?.toString() ?? item['name']?.toString() ?? 'Article', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis, maxLines: 2)),
                                            SizedBox(width: 36, child: Text('${item['quantity'] ?? item['qty'] ?? 1}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                                            SizedBox(width: 60, child: Text(_fmtNum(_p(item['price_at_sale'] ?? item['unit_price_ttc'] ?? item['unit_price'] ?? item['price'] ?? 0)), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                                            SizedBox(width: 70, child: Text(_fmtNum(_p(item['total'] ?? (_p(item['quantity'] ?? item['qty'] ?? 1) * _p(item['price_at_sale'] ?? item['unit_price_ttc'] ?? item['unit_price'] ?? item['price'] ?? 0)))), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // === TABLEAU RELEVÉ (Tiers) — Timeline Débit/Crédit/Solde ===
                            if (isTier) ...[
                              // 🟢 FIX V2 : Construction de la timeline chronologique (identique au PC)
                              Builder(builder: (context) {
                                final themeColor = Color(int.parse((_config['color'] ?? '#6f2dbd').replaceFirst('#', '0xFF')));
                                List<Map<String, dynamic>> timeline = [];

                                // Sales/PO → Débit
                                for (var s in (fullData['sales'] as List? ?? fullData['pos'] as List? ?? [])) {
                                  bool isRet = s['is_return'] == 1 || s['is_return'] == true || _p(s['total_amount']) < 0;
                                  double amt = _p(s['total_amount']).abs();
                                  bool isSaleCtx = fullData['sales'] != null;
                                  String label = isRet
                                      ? '${isSaleCtx ? 'Retour' : 'Retour Fourn.'} N°${s['invoice_number'] ?? s['number'] ?? s['id']}'
                                      : '${isSaleCtx ? 'Vente' : 'Achat'} N°${s['invoice_number'] ?? s['number'] ?? s['id']}';
                                  timeline.add({
                                    'date': s['date']?.toString().split(' ').first ?? '-',
                                    'label': label,
                                    'debit': isRet ? 0.0 : amt,
                                    'credit': isRet ? amt : 0.0,
                                  });
                                }

                                // Payments → Crédit
                                for (var p in (fullData['payments'] as List? ?? [])) {
                                  timeline.add({
                                    'date': p['date']?.toString().split(' ').first ?? '-',
                                    'label': 'Versement (${p['method'] ?? p['mode'] ?? 'Espèces'})',
                                    'debit': 0.0,
                                    'credit': _p(p['amount']),
                                  });
                                }

                                // Sort chronologique
                                timeline.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

                                // Calcul du solde courant
                                double bal = 0;
                                double totalDebit = 0, totalCredit = 0;
                                for (var t in timeline) {
                                  double d = _p(t['debit']);
                                  double c = _p(t['credit']);
                                  bal += (d - c);
                                  totalDebit += d;
                                  totalCredit += c;
                                  t['balance'] = bal;
                                }

                                if (timeline.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Center(child: Text('Aucune opération trouvée.', style: TextStyle(color: Colors.black45))),
                                  );
                                }

                                return Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: themeColor.withValues(alpha: 0.3)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      // Header
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: themeColor.withValues(alpha: 0.1),
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                                        ),
                                        child: const Row(
                                          children: [
                                            SizedBox(width: 60, child: Text('Date', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10))),
                                            Expanded(flex: 3, child: Text('Opération', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10))),
                                            SizedBox(width: 55, child: Text('Débit', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10))),
                                            SizedBox(width: 55, child: Text('Crédit', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10))),
                                            SizedBox(width: 60, child: Text('Solde', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10))),
                                          ],
                                        ),
                                      ),
                                      // Rows
                                      ...timeline.map((t) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                          decoration: BoxDecoration(
                                            border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(width: 60, child: Text(t['date'], style: const TextStyle(fontSize: 9, color: Colors.black54))),
                                              Expanded(flex: 3, child: Text(t['label'], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 1)),
                                              SizedBox(width: 55, child: Text(
                                                _p(t['debit']) > 0 ? _fmtNum(_p(t['debit'])) : '-',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(fontSize: 10, color: _p(t['debit']) > 0 ? Colors.red.shade700 : Colors.black38),
                                              )),
                                              SizedBox(width: 55, child: Text(
                                                _p(t['credit']) > 0 ? _fmtNum(_p(t['credit'])) : '-',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(fontSize: 10, color: _p(t['credit']) > 0 ? Colors.green.shade700 : Colors.black38),
                                              )),
                                              SizedBox(width: 60, child: Text(
                                                _fmtNum(_p(t['balance'])),
                                                textAlign: TextAlign.right,
                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _p(t['balance']) > 0 ? Colors.red.shade700 : Colors.green.shade700),
                                              )),
                                            ],
                                          ),
                                        );
                                      }),
                                      // Summary row
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: themeColor.withValues(alpha: 0.05),
                                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Expanded(child: Text('TOTAUX', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10))),
                                            SizedBox(width: 55, child: Text(_fmtNum(totalDebit), textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red.shade700))),
                                            SizedBox(width: 55, child: Text(_fmtNum(totalCredit), textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.green.shade700))),
                                            SizedBox(width: 60, child: Text(_fmtNum(bal), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: bal > 0 ? Colors.red.shade700 : Colors.green.shade700))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 16),
                            ],

                            // === TOTAUX ===
                            if (!isTier) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F5FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Color(int.parse((_config['color'] ?? '#6f2dbd').replaceFirst('#', '0xFF'))).withValues(alpha: 0.2)),
                                ),
                                child: Column(
                                  children: [
                                    if (_config['showTotalHt'] == true) _previewRow('Total HT', '${_fmtNum(total / 1.19)} DA'),
                                    if (_config['showTva'] == true) _previewRow('TVA (19%)', '${_fmtNum(total - total / 1.19)} DA'),
                                    if (_config['showGlobalDiscount'] == true && _p(header['discount_value'] ?? header['discount'] ?? 0) > 0)
                                      _previewRow('Remise', '-${_fmtNum(_p(header['discount_value'] ?? header['discount'] ?? 0))} DA', color: Colors.orange),
                                    _previewRow('Total TTC', '${_fmtNum(total)} DA', isBold: true, color: Color(int.parse((_config['color'] ?? '#6f2dbd').replaceFirst('#', '0xFF')))),
                                    if (paid > 0) _previewRow('Payé', '${_fmtNum(paid)} DA', color: Colors.green),
                                    if (_config['showBalance'] == true && rest > 0) _previewRow('Reste à Payer', '${_fmtNum(rest)} DA', isBold: true, color: Colors.red),
                                  ],
                                ),
                              ),
                            ],

                            if (isTier) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F5FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Color(int.parse((_config['color'] ?? '#6f2dbd').replaceFirst('#', '0xFF'))).withValues(alpha: 0.2)),
                                ),
                                child: _previewRow('Solde', '${_fmtNum(_p(fullData['globalBalance'] ?? 0))} DA',
                                  isBold: true, color: (_p(fullData['globalBalance'] ?? 0) > 0 ? Colors.red : Colors.green)),
                              ),
                            ],

                            const SizedBox(height: 20),
                            Center(
                              child: Text(
                                _config['customMsg'] ?? 'Merci de votre visite et à bientôt !',
                                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black45),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ),

                  // --- BOTTOM BAR : Bouton IMPRIMER ---
                  _buildBottomBar(ctx, currentHtml, isDark),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 🟢 FIX ZERO WEBVIEW : Helpers pour l'aperçu natif
  Widget _previewRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: isBold ? FontWeight.w600 : FontWeight.w400)),
          Flexible(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.w700 : FontWeight.w500, color: color ?? Colors.black87), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  double _p(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
    return v.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
  }

  // 🟢 FIX STUDIO MOBILE FLUTTER : Bottom bar avec bouton impression
  Widget _buildBottomBar(BuildContext ctx, String htmlContent, bool isDark) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF2D2D44) : Colors.white).withOpacity(0.85),
            border: Border(top: BorderSide(color: AppColors.primary.withOpacity(0.15))),
          ),
          child: Row(
            children: [
              // Format Info
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _config['format'] == 'Ticket' ? FontAwesomeIcons.receipt : FontAwesomeIcons.filePdf,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _config['format'] ?? 'A4',
                      style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : AppColors.primary),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // 🟢 FIX STUDIO MOBILE FLUTTER : BOUTON IMPRIMER FINAL
              GestureDetector(
                onTap: () => _handlePrint(htmlContent),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.print_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text("IMPRIMER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : LOGIQUE D'IMPRESSION
  // ==================================================================
  Future<void> _handlePrint(String htmlContent) async {
    final format = _config['format'] ?? 'A4';

    try {
      if (format == 'Ticket') {
        final prefs = await SharedPreferences.getInstance();
        Map<String, dynamic> posOptions = {};
        try {
          if (prefs.containsKey('pos_options_cache')) {
            posOptions = jsonDecode(prefs.getString('pos_options_cache')!);
          }
        } catch (_) {}
        final printMode = posOptions['pos_print_mode']?.toString() ?? 'escpos';

        bool result = false;
        if (printMode == 'raster') {
          // 🟢 FIX STUDIO MOBILE FLUTTER : Capture d'écran Native Flutter pour Raster
          try {
            RenderRepaintBoundary boundary = _previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
            ui.Image image = await boundary.toImage(pixelRatio: 2.0); // Qualité x2 pour éviter le flou
            var byteData = await image.toByteData(format: ui.ImageByteFormat.png);
            if (byteData != null) {
              final Uint8List pngBytes = byteData.buffer.asUint8List();
              result = await _printService.printRasterImage(pngBytes);
            }
          } catch(e) {
            debugPrint("Erreur capture raster: $e");
          }
        } else {
          // 🟢 FIX STUDIO MOBILE FLUTTER : Impression Ticket via rasterisation HTML -> ESC/POS
          result = await _printService.printRichHtmlTicket(htmlContent);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result ? "✅ Ticket imprimé avec succès !" : "❌ Échec d'impression. Vérifiez l'imprimante."),
              backgroundColor: result ? AppColors.success : AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        // 🟢 FIX STUDIO MOBILE FLUTTER : Impression A4/A5 via le système natif (dialog impression)
        final pdfPageFormat = format == 'A5' ? PdfPageFormat.a5 : PdfPageFormat.a4;
        await Printing.layoutPdf(
          name: 'infinity_studio_document.pdf',
          onLayout: (PdfPageFormat actualFormat) async {
            return await Printing.convertHtml(
              html: htmlContent,
              format: pdfPageFormat,
            );
          },
        );
      }
    } catch (e) {
      debugPrint("[Studio] Erreur impression: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur d'impression : $e"),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // ==================================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : SETTINGS SHEET EXHAUSTIF (7 sections)
  // ==================================================================
  void _openSettingsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSettingsState) {

            Widget buildSwitch(String key, String title, {IconData? icon}) {
              return SwitchListTile(
                title: Row(
                  children: [
                    if (icon != null) ...[Icon(icon, size: 16, color: AppColors.secondary), const SizedBox(width: 8)],
                    Flexible(child: Text(title, style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87))),
                  ],
                ),
                value: _config[key] == true,
                activeColor: AppColors.primary,
                dense: true,
                onChanged: (val) {
                  _config[key] = val;
                  setSettingsState(() {});
                  _saveConfig();
                },
              );
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, -5))],
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 50, height: 5,
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Text("Réglages Studio", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: (isDark ? Colors.white : Colors.black).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.close, size: 20, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _openPreview('sales', {
                          'id': 999999,
                          'invoice_number': 'TEST-0001',
                          'client_name': 'Client Test',
                          'total_amount': 1000.0,
                          'total_ht': 1000.0,
                          'total_vat': 0.0,
                          'discount_value': 0.0,
                          'timbre': 0.0,
                          'amount_paid': 1000.0,
                          'payment_type': 'cash',
                          'date': DateTime.now().toIso8601String(),
                          'is_return': false,
                          '_mock_items': [
                            {'name': 'Produit A (Test)', 'quantity': 2, 'unit_price': 500.0},
                            {'name': 'Produit B (Test)', 'quantity': 1, 'unit_price': 0.0},
                          ]
                        });
                      },
                      icon: const Icon(Icons.remove_red_eye_rounded, size: 20),
                      label: const Text("Aperçu Ticket Test", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 50),
                      children: [
                        // ============ 1. APPARENCE ============
                        _buildSettingsSection("1. Apparence", Icons.palette, [
                          // Format de page
                          ListTile(
                            title: Text("Format de Page", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w600)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: ['A4', 'A5', 'Ticket'].map((f) {
                                  bool isActive = _config['format'] == f;
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () { _config['format'] = f; setSettingsState(() {}); _saveConfig(); },
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          gradient: isActive ? AppColors.primaryGradient : null,
                                          color: isActive ? null : (isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: isActive ? Colors.transparent : AppColors.primary.withOpacity(0.2)),
                                        ),
                                        child: Center(
                                          child: Text(f, style: TextStyle(
                                            fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                                            color: isActive ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                                            fontSize: 14,
                                          )),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          // Thème Global
                          ListTile(
                            title: Text("Thème Global (CSS)", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w600)),
                            subtitle: Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _themes.any((t) => t['key'] == _config['headerStyle']) ? _config['headerStyle'] : 'classic_boxes',
                                  dropdownColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
                                  isExpanded: true,
                                  items: _themes.map((t) => DropdownMenuItem(value: t['key'], child: Text(t['label']!, style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87)))).toList(),
                                  onChanged: (val) { _config['headerStyle'] = val; setSettingsState(() {}); _saveConfig(); },
                                ),
                              ),
                            ),
                          ),
                          // Police
                          ListTile(
                            title: Text("Police (Font)", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                            trailing: DropdownButton<String>(
                              value: _config['fontFamily'],
                              dropdownColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
                              items: ['Inter', 'Roboto', 'Poppins', 'Arial', 'Times New Roman', 'Courier New'].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (val) { _config['fontFamily'] = val; setSettingsState(() {}); _saveConfig(); },
                            ),
                          ),
                          // Couleur
                          ListTile(
                            title: Text("Couleur du Thème", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                            trailing: GestureDetector(
                              onTap: () => _pickColor(setSettingsState),
                              child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: Color(int.parse(_config['color'].replaceFirst('#', '0xFF'))),
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Color(int.parse(_config['color'].replaceFirst('#', '0xFF'))).withOpacity(0.4), blurRadius: 10)],
                                ),
                              ),
                            ),
                          ),
                          // Taille Police
                          ListTile(
                            title: Text("Taille Police : ${_config['fontSize'].toStringAsFixed(0)}px", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                            subtitle: SliderTheme(
                              data: SliderThemeData(activeTrackColor: AppColors.primary, thumbColor: AppColors.primary, inactiveTrackColor: AppColors.primary.withOpacity(0.2)),
                              child: Slider(
                                value: (_config['fontSize'] is double) ? _config['fontSize'] : (_config['fontSize'] as num).toDouble(),
                                min: 8, max: 20, divisions: 24, label: "${_config['fontSize']}",
                                onChanged: (val) { _config['fontSize'] = val; setSettingsState(() {}); _saveConfig(); },
                              ),
                            ),
                          ),
                          // Échelle Logo
                          ListTile(
                            title: Text("Échelle Logo : ${_d(_config['logoScale']).toStringAsFixed(0)}%", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                            subtitle: SliderTheme(
                              data: SliderThemeData(activeTrackColor: AppColors.primary, thumbColor: AppColors.primary, inactiveTrackColor: AppColors.primary.withOpacity(0.2)),
                              child: Slider(
                                value: _d(_config['logoScale']),
                                min: 30, max: 200, divisions: 34, label: "${_d(_config['logoScale']).toStringAsFixed(0)}%",
                                onChanged: (val) { _config['logoScale'] = val; setSettingsState(() {}); _saveConfig(); },
                              ),
                            ),
                          ),
                        ], isDark),

                        // ============ 2. EN-TÊTE & SOCIÉTÉ ============
                        _buildSettingsSection("2. En-tête & Société", Icons.business, [
                          buildSwitch('showHeader', 'Afficher En-tête Global', icon: Icons.view_compact),
                          buildSwitch('showLogo', 'Afficher Logo', icon: Icons.image),
                          buildSwitch('showName', 'Nom Société', icon: Icons.badge),
                          buildSwitch('showActivity', 'Activité / Secteur', icon: Icons.work),
                          buildSwitch('showAddress', 'Adresse', icon: Icons.location_on),
                          buildSwitch('showPhone', 'Téléphone', icon: Icons.phone),
                          buildSwitch('showEmail', 'Email', icon: Icons.email),
                          buildSwitch('showRc', 'Registre Commerce (RC)', icon: Icons.description),
                          buildSwitch('showNif', 'NIF', icon: Icons.numbers),
                          buildSwitch('showNis', 'NIS', icon: Icons.numbers),
                          buildSwitch('showArt', 'Article d\'Imposition', icon: Icons.gavel),
                          buildSwitch('showRib', 'RIB Bancaire', icon: Icons.account_balance),
                          buildSwitch('showUser', 'Vendeur / Utilisateur', icon: Icons.person),
                        ], isDark),

                        // ============ 3. INFOS CLIENT ============
                        _buildSettingsSection("3. Infos Client", Icons.person, [
                          buildSwitch('showClientBox', 'Afficher Bloc Client'),
                          buildSwitch('showClientName', 'Nom du Client'),
                          buildSwitch('showSubClient', 'Sous-Client (Contact)'),
                          buildSwitch('showClientDetail', 'Adresse Client'),
                          buildSwitch('showClientPhone', 'Téléphone'),
                          buildSwitch('showClientEmail', 'Email'),
                          buildSwitch('showClientActivity', 'Activité'),
                          buildSwitch('showClientRc', 'RC Client'),
                          buildSwitch('showClientNif', 'NIF Client'),
                          buildSwitch('showClientNis', 'NIS Client'),
                          buildSwitch('showClientArt', 'ART Client'),
                          buildSwitch('showClientRib', 'RIB Client'),
                          buildSwitch('showInternalNote', 'Note Interne'),
                        ], isDark),

                        // ============ 4. COLONNES DU TABLEAU ============
                        _buildSettingsSection("4. Colonnes du Tableau", Icons.view_column, [
                          buildSwitch('showLineNumber', 'Numérotation (N°)'),
                          buildSwitch('colRef', 'Réf / Code-Barre'),
                          buildSwitch('colDesc', 'Désignation'),
                          buildSwitch('showColis', 'Colisage'),
                          buildSwitch('colQty', 'Quantité'),
                          buildSwitch('colPriceHt', 'Prix Unitaire HT'),
                          buildSwitch('colPriceTtc', 'Prix Unitaire TTC'),
                          buildSwitch('colTva', 'Colonne TVA %'),
                          buildSwitch('colTotalHt', 'Total HT'),
                          buildSwitch('colTotalTtc', 'Total TTC'),
                        ], isDark),

                        // ============ 5. FINANCES & TOTAUX ============
                        _buildSettingsSection("5. Finances & Totaux", Icons.attach_money, [
                          buildSwitch('showTva', 'Calculer & Afficher TVA'),
                          buildSwitch('showTimbre', 'Appliquer Timbre'),
                          buildSwitch('showPaymentMode', 'Mode de Paiement'),
                          buildSwitch('showProductDiscount', 'Remise par Produit'),
                          buildSwitch('showGlobalDiscount', 'Remise Globale'),
                          buildSwitch('showTotalHt', 'Total HT Global'),
                          buildSwitch('showFinalTotal', 'Total TTC Final'),
                          buildSwitch('showPayments', 'Historique Paiements'),
                          buildSwitch('showBalance', 'Reste à Payer'),
                          buildSwitch('showOldBalance', 'Ancienne Dette'),
                        ], isDark),

                        // ============ 6. OPTIONS AVANCÉES ============
                        _buildSettingsSection("6. Options Avancées", Icons.star, [
                          buildSwitch('zebraRows', 'Lignes Zébrées (Tableau)'),
                          buildSwitch('showStamp', 'Cachet Société'),
                          buildSwitch('showSignature', 'Signature Société'),
                          buildSwitch('showSignatureImg', 'Image Signature'),
                          buildSwitch('showSignatureClient', 'Signature Client'),
                          buildSwitch('showFooter', 'Pied de Page'),
                          buildSwitch('showBarcode', 'Code-Barres Document'),
                        ], isDark),

                        // ============ 7. TEXTES PERSONNALISÉS ============
                        _buildSettingsSection("7. Textes", Icons.text_fields, [
                          buildSwitch('showCustomMsg', 'Message Personnalisé'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TextField(
                              controller: TextEditingController(text: _config['customMsg'] ?? ''),
                              maxLines: 2,
                              style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87),
                              decoration: InputDecoration(
                                labelText: "Message personnalisé",
                                labelStyle: TextStyle(color: AppColors.primary.withOpacity(0.7)),
                                filled: true,
                                fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
                              ),
                              onChanged: (val) { _config['customMsg'] = val; _saveConfig(); },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TextField(
                              controller: TextEditingController(text: _config['footerMsg'] ?? ''),
                              style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87),
                              decoration: InputDecoration(
                                labelText: "Message Pied de Page",
                                labelStyle: TextStyle(color: AppColors.primary.withOpacity(0.7)),
                                filled: true,
                                fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
                              ),
                              onChanged: (val) { _config['footerMsg'] = val; _saveConfig(); },
                            ),
                          ),
                        ], isDark),

                        // ============ 8. INFOS ENTREPRISE ============
                        _buildSettingsSection("8. Infos Entreprise", Icons.store, [
                          ..._buildCompanyFields(isDark, setSettingsState),
                        ], isDark),
                      ],
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

  // 🟢 FIX STUDIO MOBILE FLUTTER : Helper local pour éviter l'accès privé cross-fichier
  double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Widget _buildSettingsSection(String title, IconData icon, List<Widget> children, bool isDark) {
    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
      leading: Icon(icon, color: AppColors.primary),
      iconColor: AppColors.primary,
      collapsedIconColor: AppColors.secondary,
      children: children,
    );
  }

  // 🟢 FIX V2 : Champs de saisie des infos entreprise
  List<Widget> _buildCompanyFields(bool isDark, StateSetter setSettingsState) {
    Widget field(String key, String label, {IconData icon = Icons.edit, int maxLines = 1}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextFormField(
          initialValue: _companyInfo[key]?.toString() ?? '',
          maxLines: maxLines,
          style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
            labelStyle: TextStyle(color: AppColors.primary.withValues(alpha: 0.7)),
            filled: true,
            fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onChanged: (val) {
            _companyInfo[key] = val;
            _saveCompanyInfo();
          },
        ),
      );
    }

    return [
      field('name', 'Nom de l\'Entreprise', icon: Icons.badge),
      field('address', 'Adresse', icon: Icons.location_on),
      field('phone', 'Téléphone', icon: Icons.phone),
      field('email', 'Email', icon: Icons.email),
      field('activity', 'Activité / Secteur', icon: Icons.work),
      const Divider(indent: 16, endIndent: 16),
      field('rc', 'Registre Commerce (RC)', icon: Icons.description),
      field('nif', 'NIF (Numéro Fiscal)', icon: Icons.numbers),
      field('nis', 'NIS', icon: Icons.numbers),
      field('art', 'Article d\'Imposition', icon: Icons.gavel),
      field('rib', 'RIB Bancaire', icon: Icons.account_balance),
      const SizedBox(height: 8),
    ];
  }


  void _pickColor(StateSetter setSettingsState) {
    Color currentColor = Color(int.parse(_config['color'].replaceFirst('#', '0xFF')));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Couleur du Thème", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: currentColor,
            onColorChanged: (color) {
              _config['color'] = '#${color.value.toRadixString(16).substring(2)}';
              setSettingsState(() {});
              _saveConfig();
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==================================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : LISTE DES DOCUMENTS (Purple Glossy)
  // ==================================================================
  Widget _buildList(String contextType, List<dynamic> list, {bool isTier = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3));
    }
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FontAwesomeIcons.folderOpen, size: 48, color: AppColors.primary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              "Aucun document trouvé",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white38 : Colors.black38),
            ),
            const SizedBox(height: 8),
            Text(
              "Tirez vers le bas pour actualiser",
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white24 : Colors.black26),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _fetchData(force: true),
      child: ListView.builder(
        itemCount: list.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final doc = list[index];
          final title = isTier
              ? (doc['name'] ?? 'Inconnu')
              : (doc['client_name'] ?? doc['supplier_name'] ?? 'Client Comptoir');
          final total = doc['total_amount'] ?? doc['total'] ?? doc['balance'] ?? 0.0;
          final subTitle = isTier
              ? (doc['phone'] ?? doc['address'] ?? '')
              : ("N° ${doc['invoice_number'] ?? doc['number'] ?? doc['id']} • ${HtmlInvoiceGenerator.fmtDate(doc['date'])}");

          // Icône contextuelle
          IconData docIcon;
          Color iconBgColor;
          if (isTier) {
            docIcon = FontAwesomeIcons.userTie;
            iconBgColor = AppColors.accent;
          } else if (contextType == 'purchases') {
            docIcon = FontAwesomeIcons.truckFast;
            iconBgColor = AppColors.warning;
          } else if (doc['is_return'] == 1 || doc['is_return'] == true) {
            docIcon = FontAwesomeIcons.arrowRotateLeft;
            iconBgColor = AppColors.error;
          } else {
            docIcon = FontAwesomeIcons.fileInvoiceDollar;
            iconBgColor = AppColors.primary;
          }

          final double totalParsed = double.tryParse(total.toString()) ?? 0.0;

          // 🟢 FIX STUDIO MOBILE FLUTTER : Chaque item est dans un GlassCard
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              isDark: isDark,
              borderRadius: 16,
              padding: const EdgeInsets.all(0),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openPreview(contextType, Map<String, dynamic>.from(doc)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Icône
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: iconBgColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(child: FaIcon(docIcon, color: iconBgColor, size: 18)),
                      ),
                      const SizedBox(width: 14),
                      // Texte
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title.toString(),
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(subTitle.toString(),
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black45),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Montant
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (totalParsed < 0 ? AppColors.error : AppColors.primary).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          HtmlInvoiceGenerator.fmtMoney(totalParsed),
                          style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14,
                            color: totalParsed < 0 ? AppColors.error : (isDark ? Colors.white : AppColors.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================================================================
  // BUILD : ÉCRAN PRINCIPAL (Purple Glossy)
  // ==================================================================
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // 🟢 FIX STUDIO MOBILE FLUTTER : Background Purple Glossy
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF0F3F8),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.print_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Text("Infinity Studio",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: isDark ? Colors.white : Colors.black87),
            ),
          ],
        ),
        backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF0F3F8),
        elevation: 0,
        actions: [
          GestureDetector(
            onTap: _openSettingsSheet,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 48,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.white38 : Colors.black38,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              indicatorPadding: const EdgeInsets.all(3),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: "Ventes"),
                Tab(text: "Achats"),
                Tab(text: "Brouillons"),
                Tab(text: "Clients"),
                Tab(text: "Fournisseurs"),
                Tab(text: "Clôtures"),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList('sales', _salesList),
          _buildList('purchases', _purchasesList),
          _buildPlaceholder("Brouillons", FontAwesomeIcons.filePen, isDark),
          _buildList('clients', _clientsList, isTier: true),
          _buildList('suppliers', _suppliersList, isTier: true),
          _buildPlaceholder("Clôtures (Z)", FontAwesomeIcons.cashRegister, isDark),
        ],
      ),
      // 🟢 FIX STUDIO MOBILE FLUTTER : FAB avec gradient violet
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: FloatingActionButton(
          backgroundColor: Colors.transparent,
          elevation: 0,
          onPressed: () => _fetchData(force: true),
          child: const Icon(Icons.refresh_rounded, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String label, IconData icon, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.primary.withOpacity(0.25)),
          const SizedBox(height: 16),
          Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white30 : Colors.black26)),
          const SizedBox(height: 8),
          Text("À venir", style: TextStyle(fontSize: 13, color: isDark ? Colors.white.withOpacity(0.2) : Colors.black12)),
        ],
      ),
    );
  }
}
