import 'dart:convert';
// =============================================================================
// 🖨️ PRINT SERVICE - Impression ESC/POS directe (Bluetooth & Réseau)
// =============================================================================
// Ce service génère les commandes ESC/POS nativement sur le mobile
// sans passer par le PC.
// Supporte Bluetooth (print_bluetooth_thermal) et Réseau TCP/IP (dart:io).
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';

class PrintService {
  static final PrintService _instance = PrintService._internal();
  factory PrintService() => _instance;
  PrintService._internal();


  // ============================================
  // 🔗 CONNEXION (BLUETOOTH & RÉSEAU)
  // ============================================

  // 🟢 FIX DETECTION IMPRIMANTE : Demande des permissions strictes Android 12+
  Future<bool> requestBluetoothPermissions() async {
    try {
      debugPrint("[PrintService Diagnostic] Demande des permissions Bluetooth/Location...");
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      bool allGranted = true;
      statuses.forEach((permission, status) {
        if (!status.isGranted) {
          debugPrint("[PrintService Diagnostic] Permission $permission refusée ($status).");
          allGranted = false;
        }
      });
      return allGranted;
    } catch (e) {
      debugPrint("[PrintService Diagnostic] Erreur lors de la demande de permissions: $e");
      return false;
    }
  }

  // 🟢 FIX DETECTION IMPRIMANTE : Découverte robuste des appareils jumelés avec purge
  Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      bool hasPerms = await requestBluetoothPermissions();
      if (!hasPerms) {
        debugPrint("[PrintService Diagnostic] Impossible de scanner : permissions manquantes.");
        return [];
      }
      
      debugPrint("[PrintService Diagnostic] Scan des appareils jumelés en cours...");
      final List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
      debugPrint("[PrintService Diagnostic] ${devices.length} appareil(s) trouvé(s).");
      return devices;
    } catch (e) {
      debugPrint("[PrintService Diagnostic] Erreur scan BT: $e");
      return [];
    }
  }

  // 🟢 FIX DETECTION IMPRIMANTE : Ping réseau ultra-rapide avant d'envoyer les bytes
  Future<bool> pingPrinterIP(String ip) async {
    try {
      debugPrint("[PrintService Diagnostic] Ping TCP sur $ip:9100...");
      final socket = await Socket.connect(ip, 9100, timeout: const Duration(milliseconds: 1500));
      socket.destroy();
      debugPrint("[PrintService Diagnostic] Ping réussi sur $ip:9100");
      return true;
    } on SocketException catch (e) {
      debugPrint("[PrintService Diagnostic] Échec du ping TCP (SocketException) sur $ip: $e");
      return false;
    } catch (e) {
      debugPrint("[PrintService Diagnostic] Échec du ping TCP (Inconnu) sur $ip: $e");
      return false;
    }
  }



  /// Vérifie si l'imprimante est réellement joignable (Bluetooth ou Réseau)
  Future<bool> get isConnected async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final type = prefs.getString('printer_type') ?? 'bluetooth';
      
      if (type == 'network') {
        final ip = prefs.getString('network_printer') ?? "";
        if (ip.isEmpty) return false;
        // 🟢 FIX DETECTION IMPRIMANTE : Utilisation du nouveau ping rapide
        return await pingPrinterIP(ip);
      }

      // 🟢 FIX DETECTION : Timeout sur la vérification BT pour éviter les blocages
      return await PrintBluetoothThermal.connectionStatus
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  /// Se connecte à l'imprimante (Bluetooth) avec retry automatique
  Future<bool> connectSavedPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final type = prefs.getString('printer_type') ?? 'bluetooth';
      
      if (type == 'network') {
         return true; // Connexion réseau établie à la volée
      }

      final mac = prefs.getString('mac_printer') ?? "";
      if (mac.isEmpty) {
        debugPrint("[PrintService Diagnostic] Aucune imprimante Bluetooth configurée.");
        return false;
      }

      // 🟢 FIX DETECTION IMPRIMANTE : Vérifier d'abord les permissions
      bool hasPerms = await requestBluetoothPermissions();
      if (!hasPerms) {
        debugPrint("[PrintService Diagnostic] Permissions BT manquantes pour la connexion.");
        return false;
      }

      // 🟢 FIX DETECTION IMPRIMANTE : Purge du cache si faux positif
      try {
        bool status = await PrintBluetoothThermal.connectionStatus
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        if (status) {
            debugPrint("[PrintService Diagnostic] L'appareil semble déjà connecté.");
            return true;
        } else {
            // Forcer la déconnexion pour purger l'état interne du plugin
            await disconnect();
        }
      } catch (_) {
          await disconnect();
      }

      // Retry loop (3 tentatives avec backoff)
      const maxRetries = 3;
      const delays = [Duration(milliseconds: 500), Duration(seconds: 1), Duration(seconds: 2)];
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          debugPrint("[PrintService Diagnostic] Tentative BT ${attempt + 1}/$maxRetries vers $mac...");
          final result = await PrintBluetoothThermal.connect(macPrinterAddress: mac)
              .timeout(const Duration(seconds: 5), onTimeout: () => false);
          if (result) {
            debugPrint("[PrintService Diagnostic] ✅ Connecté à $mac (tentative ${attempt + 1})");
            return true;
          }
        } catch (e) {
          debugPrint("[PrintService Diagnostic] ⚠️ Erreur tentative ${attempt + 1}: $e");
        }
        // Purge d'état entre les tentatives
        await disconnect();
        if (attempt < maxRetries - 1) await Future.delayed(delays[attempt]);
      }
      debugPrint("[PrintService Diagnostic] ❌ Échec connexion BT après $maxRetries tentatives");
      return false;
    } catch (e) {
      debugPrint("[PrintService Diagnostic] Erreur connexion BT: $e");
      return false;
    }
  }

  /// Déconnecte l'imprimante (Bluetooth)
  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
  }

/// Fonction UNIFIÉE d'envoi des bytes (route vers BT ou Réseau)
  Future<bool> sendBytesToPrinter(List<int> bytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final type = prefs.getString('printer_type') ?? 'bluetooth';
      debugPrint("[PrintService] 📤 Envoi de ${bytes.length} bytes via $type...");

      if (type == 'network') {
        final ipAddress = prefs.getString('network_printer') ?? "";
        if (ipAddress.isEmpty) return false;
        return await printViaNetwork(ipAddress, bytes);
      } else {
        // 🟢 FIX : Le plugin gère le MTU en interne. On envoie tout d'un coup.
        final ok = await PrintBluetoothThermal.writeBytes(bytes);
        debugPrint("[PrintService] ${ok ? '✅' : '❌'} Envoi BT terminé (${bytes.length} bytes)");
        return ok;
      }
    } catch (e) {
      debugPrint("[PrintService] Erreur sendBytesToPrinter: $e");
      return false;
    }
  }
  /// Impression via Réseau TCP/IP (Port 9100)
  Future<bool> printViaNetwork(String ipAddress, List<int> bytes) async {
    // 🟢 FIX DETECTION IMPRIMANTE : On ping d'abord pour éviter le blocage
    bool isAlive = await pingPrinterIP(ipAddress);
    if (!isAlive) return false;

    Socket? socket;
    try {
      socket = await Socket.connect(ipAddress, 9100, timeout: const Duration(seconds: 3));
      socket.add(bytes);
      await socket.flush().timeout(const Duration(seconds: 5));
      await socket.close();
      return true;
    } catch (e) {
      debugPrint("[PrintService Diagnostic] Erreur Réseau inconnue : $e");
      socket?.destroy();
      return false;
    }
  }

  // ============================================
  // 🧠 IMPRESSION INTELLIGENTE — BASCULE RASTER / ESC/POS
  // ============================================

  /// Méthode unifiée qui choisit automatiquement entre :
  /// - **Mode ESC/POS** (texte natif, rapide, léger)
  /// - **Mode Raster** (HTML → Image PNG, compatibilité universelle)
  ///
  /// Le mode est lu depuis `pos_print_mode` dans SharedPreferences.
  Future<bool> printSmartTicket({
    required String invoiceNumber,
    required List<Map<String, dynamic>> items,
    required double totalTTC,
    double totalHT = 0,
    double totalTVA = 0,
    double totalTimbre = 0,
    double discount = 0,
    double amountPaid = 0,
    String? clientName,
    Map<String, dynamic>? clientData,
    String paymentType = "cash",
    bool isReturn = false,
    String? note,
    double oldDebt = 0,
    double finalDue = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> posOptions = {};
    try {
      if (prefs.containsKey('pos_options_cache')) {
        posOptions = json.decode(prefs.getString('pos_options_cache')!);
      }
    } catch (_) {}

    final mode = posOptions['pos_print_mode']?.toString() ?? 'escpos';
    debugPrint('[PrintService] 🧠 Mode d\'impression: $mode');

    if (mode == 'raster') {
      // === MODE RASTER : HTML → Image ===
      final html = await _buildSmartHtmlTicket(
        invoiceNumber: invoiceNumber,
        items: items,
        totalTTC: totalTTC,
        totalHT: totalHT,
        totalTVA: totalTVA,
        totalTimbre: totalTimbre,
        discount: discount,
        amountPaid: amountPaid,
        clientName: clientName,
        clientData: clientData,
        paymentType: paymentType,
        isReturn: isReturn,
        note: note,
        oldDebt: oldDebt,
        finalDue: finalDue,
      );
      return await printRichHtmlTicket(html);
    } else {
      // === MODE ESC/POS : Texte natif ===
      return await printSaleTicket(
        invoiceNumber: invoiceNumber,
        items: items,
        totalTTC: totalTTC,
        totalHT: totalHT,
        totalTVA: totalTVA,
        totalTimbre: totalTimbre,
        discount: discount,
        amountPaid: amountPaid,
        clientName: clientName,
        clientData: clientData,
        paymentType: paymentType,
        isReturn: isReturn,
        note: note,
        oldDebt: oldDebt,
        finalDue: finalDue,
      );
    }
  }

/// 🟢 FIX STUDIO MOBILE FLUTTER : Impression Raster Native depuis PNG
  Future<bool> printRasterImage(Uint8List pngBytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final posOptions = prefs.containsKey('pos_options_cache') ? json.decode(prefs.getString('pos_options_cache')!) : {};
      final is58mm = (posOptions['pos_receipt_size']?.toString() ?? '80mm').contains('58');
      final paperSize = is58mm ? PaperSize.mm58 : PaperSize.mm80;
      final printerWidth = is58mm ? 384 : 576;

      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);
      List<int> bytes = [];

      img.Image? image = await compute(img.decodeImage, pngBytes);
      
      if (image != null) {
        if (image.width > printerWidth) {
          image = img.copyResize(image, width: printerWidth);
        }
        bytes += generator.imageRaster(image, align: PosAlign.center);
      }

      bytes += generator.feed(4); // 🟢 FIX : On avance le papier de 4 lignes au lieu de cut() pour éviter le BIP d'erreur !

      return await sendBytesToPrinter(bytes);
    } catch (e) {
      debugPrint("[PrintService Diagnostic] Erreur printRasterImage: $e");
      return false;
    }
  }

  // 🟢 FIX FREEZE : Le calcul lourd est déporté ici, hors de l'interface graphique
  static Future<List<int>> _processRasterBackground(Map<String, dynamic> params) async {
    final int width = params['width'];
    final int height = params['height'];
    final Uint8List rgbaBytes = params['bytes'];
    final bool is58mm = params['is58mm'];
    final int printerWidth = is58mm ? 384 : 576;

    final profile = await CapabilityProfile.load();
    final generator = Generator(is58mm ? PaperSize.mm58 : PaperSize.mm80, profile);

    img.Image image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgbaBytes.buffer,
      numChannels: 4,
    );

    if (image.width > printerWidth) {
      image = img.copyResize(image, width: printerWidth);
    }
    
    List<int> bytes = generator.imageRaster(image, align: PosAlign.center);
    bytes += generator.feed(4);
    return bytes;
  }

  /// Impression Image Instantanée (Zéro Freeze grâce à compute)
  Future<bool> printRasterRaw(Uint8List rgbaBytes, int width, int height) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> posOptions = {};
      try {
        if (prefs.containsKey('pos_options_cache')) {
          posOptions = json.decode(prefs.getString('pos_options_cache')!);
        }
      } catch (_) {}
      
      final is58mm = (posOptions['pos_receipt_size']?.toString() ?? '80mm').contains('58');

      // 🟢 FIX FREEZE : On envoie les millions de calculs dans un autre processeur
      final bytes = await compute(_processRasterBackground, {
        'width': width,
        'height': height,
        'bytes': rgbaBytes,
        'is58mm': is58mm,
      });

      return await sendBytesToPrinter(bytes);
    } catch (e) {
      debugPrint("[PrintService Diagnostic] Erreur printRasterRaw: $e");
      return false;
    }
  }

  /// 🖼️ Génère un ticket HTML riche pour le mode Raster
  Future<String> _buildSmartHtmlTicket({
    required String invoiceNumber,
    required List<Map<String, dynamic>> items,
    required double totalTTC,
    double totalHT = 0,
    double totalTVA = 0,
    double totalTimbre = 0,
    double discount = 0,
    double amountPaid = 0,
    String? clientName,
    Map<String, dynamic>? clientData,
    String paymentType = "cash",
    bool isReturn = false,
    String? note,
    double oldDebt = 0,
    double finalDue = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> company = {};
    Map<String, dynamic> thermalCfg = {};
    try {
      if (prefs.containsKey('company_info_cache')) company = json.decode(prefs.getString('company_info_cache')!);
      if (prefs.containsKey('thermal_config_cache')) thermalCfg = json.decode(prefs.getString('thermal_config_cache')!);
    } catch (_) {}

    final blocs = thermalCfg['blocs_company'] ?? {};
    final clientBlocs = thermalCfg['blocs_client'] ?? {};
    final cols = thermalCfg['columns'] ?? {};
    final fonts = thermalCfg['fonts'] ?? {};
    final footerMsg = thermalCfg['footer_msg']?.toString() ?? 'Merci de votre visite !';
    final showLogo = thermalCfg['show_logo'] != false;

    final headerFont = fonts['header'] ?? 16;
    final bodyFont = fonts['body'] ?? 12;
    final totalsFont = fonts['totals'] ?? 14;

    final showQty = cols['qty'] != false;
    final showPrice = cols['price'] != false;
    final showTotal = cols['total'] != false;
    final showRef = cols['ref'] == true;
    final showTva = cols['tva'] == true;

    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final rest = totalTTC.abs() - amountPaid.abs();

    // Logo en base64
    String logoHtml = '';
    if (showLogo) {
      final logoB64 = prefs.getString('company_logo_cached_b64');
      if (logoB64 != null && logoB64.isNotEmpty) {
        String cleanB64 = logoB64;
        if (cleanB64.contains(',')) cleanB64 = cleanB64.split(',').last;
        logoHtml = '<div style="text-align:center;margin-bottom:8px;"><img src="data:image/png;base64,$cleanB64" style="max-width:120px;max-height:60px;" /></div>';
      }
    }

    // Header Entreprise
    String companyHtml = '';
    if (blocs['name'] != false) companyHtml += '<div style="font-size:${headerFont}px;font-weight:900;text-align:center;">${company['name'] ?? 'MON ENTREPRISE'}</div>';
    if (blocs['activity'] != false && (company['activity']?.toString().isNotEmpty == true)) companyHtml += '<div style="text-align:center;font-size:${bodyFont}px;font-weight:600;">${company['activity']}</div>';
    if (blocs['address'] != false && (company['address']?.toString().isNotEmpty == true)) companyHtml += '<div style="text-align:center;font-size:${bodyFont}px;">${company['address']}</div>';
    if (blocs['phone'] != false && (company['phone']?.toString().isNotEmpty == true)) companyHtml += '<div style="text-align:center;font-size:${bodyFont}px;">Tél: ${company['phone']}</div>';
    if (blocs['rc'] != false && (company['rc']?.toString().isNotEmpty == true)) companyHtml += '<div style="font-size:${bodyFont - 1}px;">RC: ${company['rc']}</div>';
    if (blocs['nif'] != false && (company['nif']?.toString().isNotEmpty == true)) companyHtml += '<div style="font-size:${bodyFont - 1}px;">NIF: ${company['nif']}</div>';
    if (blocs['nis'] != false && (company['nis']?.toString().isNotEmpty == true)) companyHtml += '<div style="font-size:${bodyFont - 1}px;">NIS: ${company['nis']}</div>';
    if (blocs['art'] != false && (company['art']?.toString().isNotEmpty == true)) companyHtml += '<div style="font-size:${bodyFont - 1}px;">ART: ${company['art']}</div>';

    // Client info
    String clientHtml = '';
    if (clientName != null && clientName.isNotEmpty && clientName != 'Client Comptoir') {
      if (clientBlocs['name'] != false) clientHtml += '<div style="font-size:${bodyFont}px;font-weight:700;">Client: $clientName</div>';
      if (clientData != null) {
        if (clientBlocs['address'] == true && (clientData['address']?.toString().isNotEmpty == true)) clientHtml += '<div style="font-size:${bodyFont - 1}px;">${clientData['address']}</div>';
        if (clientBlocs['phone'] == true && (clientData['phone']?.toString().isNotEmpty == true)) clientHtml += '<div style="font-size:${bodyFont - 1}px;">Tél: ${clientData['phone']}</div>';
        if (clientBlocs['nif'] == true && (clientData['nif']?.toString().isNotEmpty == true)) clientHtml += '<div style="font-size:${bodyFont - 1}px;">NIF: ${clientData['nif']}</div>';
        if (clientBlocs['rc'] == true && (clientData['rc']?.toString().isNotEmpty == true)) clientHtml += '<div style="font-size:${bodyFont - 1}px;">RC: ${clientData['rc']}</div>';
      }
    }

    // Tableau d'articles — colonnes dynamiques
    int colCount = 1; // Article (toujours)
    if (showQty) colCount++;
    if (showPrice) colCount++;
    if (showTotal) colCount++;
    if (showRef) colCount++;
    if (showTva) colCount++;

    String headerRow = '<th style="text-align:left;">Article</th>';
    if (showRef) headerRow += '<th>Réf</th>';
    if (showQty) headerRow += '<th>Qté</th>';
    if (showPrice) headerRow += '<th>P.U.</th>';
    if (showTva) headerRow += '<th>TVA</th>';
    if (showTotal) headerRow += '<th style="text-align:right;">Total</th>';

    String itemsHtml = '';
    for (final item in items) {
      final name = item['name']?.toString() ?? 'Article';
      final qty = (double.tryParse(item['qty']?.toString() ?? '1') ?? 1).abs();
      final price = (double.tryParse(item['price']?.toString() ?? '0') ?? 0).abs();
      final lineTotal = qty * price;
      final ref = item['ref']?.toString() ?? '';
      final vatPct = item['vat_percent']?.toString() ?? '0';

      String row = '<td>$name</td>';
      if (showRef) row += '<td style="text-align:center;">$ref</td>';
      if (showQty) row += '<td style="text-align:center;">x${qty.toInt()}</td>';
      if (showPrice) row += '<td style="text-align:right;">${price.toStringAsFixed(0)}</td>';
      if (showTva) row += '<td style="text-align:center;">$vatPct%</td>';
      if (showTotal) row += '<td style="text-align:right;">${lineTotal.toStringAsFixed(0)}</td>';
      itemsHtml += '<tr>$row</tr>';
    }

    // Totaux
    String totalsHtml = '';
    if (totalHT > 0) totalsHtml += '<tr><td>Sous-total HT</td><td style="text-align:right;">${totalHT.toStringAsFixed(0)} DA</td></tr>';
    if (discount > 0) totalsHtml += '<tr><td>Remise</td><td style="text-align:right;color:red;">-${discount.toStringAsFixed(0)} DA</td></tr>';
    if (totalTVA > 0) totalsHtml += '<tr><td>TVA</td><td style="text-align:right;">${totalTVA.toStringAsFixed(0)} DA</td></tr>';
    if (totalTimbre > 0) totalsHtml += '<tr><td>Timbre</td><td style="text-align:right;">${totalTimbre.toStringAsFixed(0)} DA</td></tr>';
    totalsHtml += '<tr style="font-weight:900;font-size:${totalsFont}px;"><td>TOTAL TTC</td><td style="text-align:right;">${totalTTC.abs().toStringAsFixed(0)} DA</td></tr>';
    totalsHtml += '<tr><td>${paymentType.contains('credit') ? 'Crédit' : 'Versé'}</td><td style="text-align:right;">${amountPaid.abs().toStringAsFixed(0)} DA</td></tr>';
    if (rest > 0 && !paymentType.contains('credit')) {
      totalsHtml += '<tr style="color:red;font-weight:700;"><td>Reste à payer</td><td style="text-align:right;">${rest.toStringAsFixed(0)} DA</td></tr>';
    }
    if (oldDebt > 0 || finalDue > 0) {
      totalsHtml += '<tr><td>Ancien Solde</td><td style="text-align:right;">${oldDebt.toStringAsFixed(0)} DA</td></tr>';
      totalsHtml += '<tr style="font-weight:700;"><td>Nouveau Solde</td><td style="text-align:right;">${finalDue.toStringAsFixed(0)} DA</td></tr>';
    }

    final docTitle = isReturn ? 'TICKET DE RETOUR / AVOIR' : 'TICKET DE CAISSE';
    final noteHtml = (note != null && note.isNotEmpty) ? '<div style="margin-top:6px;font-size:${bodyFont}px;text-align:center;"><em>Note: $note</em></div>' : '';

    return '''
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><style>
  body { font-family: 'Courier New', monospace; margin: 0; padding: 8px; width: 72mm; font-size: ${bodyFont}px; }
  table { width: 100%; border-collapse: collapse; }
  th, td { padding: 2px 4px; font-size: ${bodyFont}px; }
  hr { border: none; border-top: 1px dashed #000; margin: 6px 0; }
</style></head><body>
  $logoHtml
  $companyHtml
  <hr/>
  <div style="text-align:center;font-weight:900;font-size:${bodyFont + 2}px;">$docTitle</div>
  <div style="font-size:${bodyFont}px;">Date: $now</div>
  <div style="font-size:${bodyFont}px;">Ticket: #$invoiceNumber</div>
  $clientHtml
  <hr/>
  <table><thead><tr>$headerRow</tr></thead><tbody>$itemsHtml</tbody></table>
  <hr/>
  <table>$totalsHtml</table>
  $noteHtml
  <hr/>
  <div style="text-align:center;font-weight:700;margin-top:8px;font-size:${bodyFont}px;">$footerMsg</div>
</body></html>
''';
  }

  // ============================================
  // 🎫 IMPRESSION TICKET DE VENTE
  // ============================================

  /// Imprime un ticket de caisse complet en ESC/POS
  /// 
  /// [storeName] : Nom de la boutique (en-tête)
  /// [storeAddress] : Adresse (optionnel)
  /// [storePhone] : Téléphone (optionnel)
  /// [invoiceNumber] : Numéro de facture/ticket
  /// [items] : Liste des articles [{name, qty, price, variant_id, vat_percent}]
  /// [totalHT] : Total Hors Taxes
  /// [totalTVA] : Montant TVA
  /// [totalTimbre] : Timbre fiscal
  /// [discount] : Remise
  /// [totalTTC] : Total TTC final
  /// [amountPaid] : Montant versé
  /// [clientName] : Nom du client (optionnel)
  /// [paymentType] : Mode de paiement
  /// [isReturn] : (obsolète, toujours false)
  Future<bool> printSaleTicket({
    String storeName = "Infinity POS",
    String? storeAddress,
    String? storePhone,
    String invoiceNumber = "",
    required List<Map<String, dynamic>> items,
    double totalHT = 0,
    double totalTVA = 0,
    double totalTimbre = 0,
    double discount = 0,
    required double totalTTC,
    double amountPaid = 0,
    String? clientName,
    Map<String, dynamic>? clientData,
    String paymentType = "cash",
    bool isReturn = false,
    String? note,
    double oldDebt = 0,
    double finalDue = 0,
  }) async {
    try {
      if (!await connectSavedPrinter()) {
        debugPrint("[PrintService] Impossible de se connecter à l'imprimante.");
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> company = {};
      Map<String, dynamic> posOptions = {};
      Map<String, dynamic> thermalCfg = {};
      try {
        if (prefs.containsKey('company_info_cache')) company = json.decode(prefs.getString('company_info_cache')!);
        if (prefs.containsKey('pos_options_cache')) posOptions = json.decode(prefs.getString('pos_options_cache')!);
        if (prefs.containsKey('thermal_config_cache')) thermalCfg = json.decode(prefs.getString('thermal_config_cache')!);
      } catch (_) {}

      final blocs = thermalCfg['blocs_company'] ?? {};
      final clientBlocs = thermalCfg['blocs_client'] ?? {};
      final cols = thermalCfg['columns'] ?? {};
      final showLogo = thermalCfg['show_logo'] != false;
      final showQty = cols['qty'] != false;
      final showPrice = cols['price'] != false;
      final showTotal = cols['total'] != false;

      final profile = await CapabilityProfile.load();
      final sizeOption = posOptions['pos_receipt_size']?.toString() ?? '80mm';
      final paperSize = sizeOption.contains('58') ? PaperSize.mm58 : PaperSize.mm80;
      final generator = Generator(paperSize, profile);
      List<int> bytes = [];

      bytes += generator.reset();
      
   // 0. LOGO (Si existant dans le cache)
      if (showLogo) {
        final logoCached = prefs.getString('company_logo_cached_b64');
        if (logoCached != null && logoCached.isNotEmpty) {
          try {
            String cleanB64 = logoCached;
            if (cleanB64.contains(',')) cleanB64 = cleanB64.split(',').last;
            cleanB64 = cleanB64.replaceAll(RegExp(r'\s+'), ''); // 🟢 CORRECTIF CRITIQUE
            final logoBytes = base64Decode(cleanB64);
            img.Image? logoImg = img.decodeImage(logoBytes);
            if (logoImg != null) {
              // Largeur max 380px pour les logos en mode texte (évite les blocs énormes)
              if (logoImg.width > 380) logoImg = img.copyResize(logoImg, width: 380);
              try {
                bytes += generator.imageRaster(logoImg, align: PosAlign.center);
                bytes += generator.feed(1);
              } catch (e) {
                debugPrint("[PrintService Diagnostic] Erreur imageRaster logo: $e");
              }
            }
          } catch (e) {
            debugPrint("[PrintService Diagnostic] Erreur décodage logo ESC/POS: $e");
          }
        }
      }

      // 1. HEADER (COMPANY INFO)
      if (blocs['name'] != false) {
        final cName = company['name']?.toString() ?? storeName;
        bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
        bytes += generator.text(cName);
        bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      }

      if (blocs['activity'] != false) {
        final cActivity = company['activity']?.toString();
        if (cActivity != null && cActivity.isNotEmpty) {
            bytes += generator.text(cActivity, styles: const PosStyles(align: PosAlign.center, bold: true));
        }
      }

      if (blocs['address'] != false) {
        final cAddress = company['address']?.toString() ?? storeAddress;
        if (cAddress != null && cAddress.isNotEmpty) bytes += generator.text(cAddress, styles: const PosStyles(align: PosAlign.center));
      }

      if (blocs['phone'] != false) {
        final cPhone = company['phone']?.toString() ?? storePhone;
        if (cPhone != null && cPhone.isNotEmpty) bytes += generator.text("Tél: $cPhone", styles: const PosStyles(align: PosAlign.center));
      }
      
      // Tax info
      if (blocs['rc'] != false) {
        final cRc = company['rc']?.toString();
        if (cRc != null && cRc.isNotEmpty) bytes += generator.text("RC: $cRc", styles: const PosStyles(align: PosAlign.center));
      }
      if (blocs['nif'] != false) {
        final cNif = company['nif']?.toString();
        if (cNif != null && cNif.isNotEmpty) bytes += generator.text("NIF: $cNif", styles: const PosStyles(align: PosAlign.center));
      }
      if (blocs['nis'] != false) {
        final cNis = company['nis']?.toString();
        if (cNis != null && cNis.isNotEmpty) bytes += generator.text("NIS: $cNis", styles: const PosStyles(align: PosAlign.center));
      }
      if (blocs['art'] != false) {
        final cArt = company['art']?.toString();
        if (cArt != null && cArt.isNotEmpty) bytes += generator.text("ART: $cArt", styles: const PosStyles(align: PosAlign.center));
      }

      bytes += generator.hr(ch: '=');

      // 2. DOCUMENT INFO
      final docTitle = isReturn ? "TICKET DE RETOUR / AVOIR" : "TICKET DE CAISSE";
      bytes += generator.text(docTitle, styles: const PosStyles(align: PosAlign.center, bold: true));
      
      final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      bytes += generator.text("Date: $now", styles: const PosStyles(align: PosAlign.left));
      if (invoiceNumber.isNotEmpty) bytes += generator.text("Ticket: #$invoiceNumber", styles: const PosStyles(align: PosAlign.left));
      
      // 3. CLIENT INFO
      final hideClient = posOptions['pos_hide_client'] == true || posOptions['pos_hide_client'] == 'true';
      if (!hideClient && clientName != null && clientName.isNotEmpty && clientName != "Client Comptoir") {
        if (clientBlocs['name'] != false) {
          bytes += generator.text("Client: $clientName", styles: const PosStyles(align: PosAlign.left, bold: true));
        }
        if (clientData != null) {
            final rc = clientData['rc']?.toString();
            final nif = clientData['nif']?.toString();
            if (clientBlocs['rc'] == true && rc != null && rc.isNotEmpty) bytes += generator.text("RC Client: $rc", styles: const PosStyles(align: PosAlign.left));
            if (clientBlocs['nif'] == true && nif != null && nif.isNotEmpty) bytes += generator.text("NIF Client: $nif", styles: const PosStyles(align: PosAlign.left));
            if (clientBlocs['address'] == true && clientData['address'] != null) bytes += generator.text("Adresse: ${clientData['address']}", styles: const PosStyles(align: PosAlign.left));
            if (clientBlocs['phone'] == true && clientData['phone'] != null) bytes += generator.text("Tél: ${clientData['phone']}", styles: const PosStyles(align: PosAlign.left));
        }
      }

      bytes += generator.hr(ch: '-');

      // 4. ITEMS
      int wQty = showQty ? 2 : 0;
      int wTotal = showTotal ? 4 : 0;
      int wArt = 12 - wQty - wTotal;
      if (wArt < 4) wArt = 4; // safety fallback

      List<PosColumn> hCols = [PosColumn(text: 'Article', width: wArt, styles: const PosStyles(bold: true))];
      if (showQty) hCols.add(PosColumn(text: 'Qté', width: wQty, styles: const PosStyles(bold: true, align: PosAlign.center)));
      if (showTotal) hCols.add(PosColumn(text: 'Total', width: wTotal, styles: const PosStyles(bold: true, align: PosAlign.right)));

      bytes += generator.row(hCols);
      bytes += generator.hr(ch: '-');

      for (final item in items) {
        final name = (item['name'] ?? 'Article').toString();
        final qty = (double.tryParse(item['qty']?.toString() ?? '1') ?? 1).abs();
        final price = (double.tryParse(item['price']?.toString() ?? '0') ?? 0).abs();
        final lineTotal = qty * price;

        List<PosColumn> rCols = [];
        rCols.add(PosColumn(text: showPrice ? '  @ ${price.toStringAsFixed(0)} DA' : ' ', width: wArt));
        if (showQty) rCols.add(PosColumn(text: 'x${qty.toInt()}', width: wQty, styles: const PosStyles(align: PosAlign.center)));
        if (showTotal) rCols.add(PosColumn(text: '${lineTotal.toStringAsFixed(0)}', width: wTotal, styles: const PosStyles(align: PosAlign.right)));

        if (name.length > 20) {
          bytes += generator.text(name, styles: const PosStyles(bold: true));
          bytes += generator.row(rCols);
        } else {
          rCols[0] = PosColumn(text: name, width: wArt);
          bytes += generator.row(rCols);
          if (showPrice) bytes += generator.text('  @ ${price.toStringAsFixed(0)} DA', styles: const PosStyles(height: PosTextSize.size1));
        }
      }

      bytes += generator.hr(ch: '=');

      // 5. TOTALS
      if (totalHT > 0) {
        bytes += generator.row([
          PosColumn(text: 'Sous-total HT', width: 7),
          PosColumn(text: '${totalHT.toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }
      if (discount > 0) {
        bytes += generator.row([
          PosColumn(text: 'Remise', width: 7, styles: const PosStyles(bold: true)),
          PosColumn(text: '-${discount.toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }
      if (totalTVA > 0) {
        bytes += generator.row([
          PosColumn(text: 'TVA', width: 7),
          PosColumn(text: '${totalTVA.toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }
      if (totalTimbre > 0) {
        bytes += generator.row([
          PosColumn(text: 'Timbre', width: 7),
          PosColumn(text: '${totalTimbre.toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.hr(ch: '-');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text('${totalTTC.abs().toStringAsFixed(0)} DA');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.left));

      // 6. PAYMENT
      bytes += generator.hr(ch: '-');
      final payLabel = paymentType.contains('credit') ? 'Crédit' : 'Versé';
      bytes += generator.row([
        PosColumn(text: payLabel, width: 7),
        PosColumn(text: '${amountPaid.abs().toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right)),
      ]);

      final rest = totalTTC.abs() - amountPaid.abs();
      if (rest > 0 && !paymentType.contains('credit')) {
        bytes += generator.row([
          PosColumn(text: 'Reste à payer', width: 7, styles: const PosStyles(bold: true)),
          PosColumn(text: '${rest.toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
      } else if (rest < 0) {
        bytes += generator.row([
          PosColumn(text: 'Rendu', width: 7, styles: const PosStyles(bold: true)),
          PosColumn(text: '${(-rest).toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
      }

      // 7. FINANCES (If client is not default and has balances)
      if (finalDue > 0 || oldDebt > 0) {
          bytes += generator.hr(ch: '-');
          bytes += generator.row([
            PosColumn(text: 'Ancien Solde', width: 7),
            PosColumn(text: '${oldDebt.toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right)),
          ]);
          bytes += generator.row([
            PosColumn(text: 'Nouveau Solde', width: 7, styles: const PosStyles(bold: true)),
            PosColumn(text: '${finalDue.toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right, bold: true)),
          ]);
      }

      if (note != null && note.isNotEmpty) {
          bytes += generator.hr(ch: '-');
          bytes += generator.text("Note: $note", styles: const PosStyles(align: PosAlign.center));
      }

      bytes += generator.feed(2);
      bytes += generator.text("Merci de votre visite !", styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.feed(3);
      bytes += generator.feed(4); // 🟢 FIX : Avance papier au lieu de cut() pour éviter le BIP !

      return await sendBytesToPrinter(bytes);
    } catch (e) {
      debugPrint("[PrintService] Erreur impression vente: $e");
      return false;
    }
  }

  // ============================================
  // 🧪 PAGE DE TEST
  // ============================================

  /// Imprime une page de test universelle en ASCII pur
  Future<bool> printTestPage() async {
    try {
      if (!await connectSavedPrinter()) return false;

      // 🟢 FIX BEEP : Envoi des octets bruts universels (ASCII)
      // Les imprimantes XPrinter peuvent bipper si on utilise une page de code non reconnue.
      List<int> bytes = [];
      
      bytes.addAll([27, 64]); // Commande ESC @ (Initialisation stricte)
      bytes.addAll(utf8.encode("\n--------------------------------\n"));
      bytes.addAll(utf8.encode("           TEST OK\n"));
      bytes.addAll(utf8.encode("--------------------------------\n"));
      bytes.addAll(utf8.encode("L'imprimante communique bien\n"));
      bytes.addAll(utf8.encode("avec le telephone.\n"));
      bytes.addAll(utf8.encode("--------------------------------\n"));
      bytes.addAll([10, 10, 10, 10, 10]); // 5 sauts de ligne pour dégager le papier

      return await sendBytesToPrinter(bytes);
    } catch (e) {
      debugPrint("[PrintService] Erreur test: $e");
      return false;
    }
  }

  // ============================================
  // 📦 IMPRESSION TICKET D'ACHAT (Bon de Réception Fournisseur)
  // ============================================

  /// Imprime un bon d'achat/réception fournisseur en ESC/POS
  Future<bool> printPurchaseTicket({
    String storeName = "Infinity POS",
    String? storeAddress,
    String? storePhone,
    String invoiceNumber = "",
    required List<Map<String, dynamic>> items,
    required double totalTTC,
    double amountPaid = 0,
    String? supplierName,
    Map<String, dynamic>? supplierData,
    String paymentType = "cash",
    String? note,
    bool isReturn = false,
  }) async {
    try {
      if (!await connectSavedPrinter()) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> company = {};
      Map<String, dynamic> posOptions = {};
      try {
        if (prefs.containsKey('company_info_cache')) company = json.decode(prefs.getString('company_info_cache')!);
        if (prefs.containsKey('pos_options_cache')) posOptions = json.decode(prefs.getString('pos_options_cache')!);
      } catch (_) {}

      final profile = await CapabilityProfile.load();
      final sizeOption = posOptions['pos_receipt_size']?.toString() ?? '80mm';
      final paperSize = sizeOption.contains('58') ? PaperSize.mm58 : PaperSize.mm80;
      final generator = Generator(paperSize, profile);
      List<int> bytes = [];

      bytes += generator.reset();
      
      final cName = company['name']?.toString() ?? storeName;
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text(cName);
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));

      bytes += generator.hr(ch: '=');

      final docTitle = isReturn ? "TICKET RETOUR FOURNISSEUR" : "TICKET ACHAT";
      bytes += generator.text(docTitle, styles: const PosStyles(align: PosAlign.center, bold: true));
      
      final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      bytes += generator.text("Date: $now", styles: const PosStyles(align: PosAlign.left));
      if (invoiceNumber.isNotEmpty) bytes += generator.text("Bon N°: $invoiceNumber", styles: const PosStyles(align: PosAlign.left));
      
      if (supplierName != null && supplierName.isNotEmpty) {
        bytes += generator.text("Fournisseur: $supplierName", styles: const PosStyles(align: PosAlign.left, bold: true));
      }

      bytes += generator.hr(ch: '-');

      bytes += generator.row([
        PosColumn(text: 'Article', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(text: 'Qté', width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
        PosColumn(text: 'Total', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);
      bytes += generator.hr(ch: '-');

      for (final item in items) {
        final name = (item['name'] ?? 'Article').toString();
        final qty = (double.tryParse(item['qty']?.toString() ?? '1') ?? 1).abs();
        final price = (double.tryParse(item['price']?.toString() ?? '0') ?? 0).abs();
        final lineTotal = qty * price;

        if (name.length > 20) {
          bytes += generator.text(name, styles: const PosStyles(bold: true));
          bytes += generator.row([
            PosColumn(text: '  @ ${price.toStringAsFixed(0)} DA', width: 6),
            PosColumn(text: 'x${qty.toInt()}', width: 2, styles: const PosStyles(align: PosAlign.center)),
            PosColumn(text: '${lineTotal.toStringAsFixed(0)}', width: 4, styles: const PosStyles(align: PosAlign.right)),
          ]);
        } else {
          bytes += generator.row([
            PosColumn(text: name, width: 6),
            PosColumn(text: 'x${qty.toInt()}', width: 2, styles: const PosStyles(align: PosAlign.center)),
            PosColumn(text: '${lineTotal.toStringAsFixed(0)}', width: 4, styles: const PosStyles(align: PosAlign.right)),
          ]);
        }
      }

      bytes += generator.hr(ch: '=');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text('${totalTTC.abs().toStringAsFixed(0)} DA');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.left));

      bytes += generator.hr(ch: '-');
      final payLabel = paymentType.contains('credit') ? 'Crédit' : 'Payé';
      bytes += generator.row([
        PosColumn(text: payLabel, width: 7),
        PosColumn(text: '${amountPaid.abs().toStringAsFixed(0)} DA', width: 5, styles: const PosStyles(align: PosAlign.right)),
      ]);

      bytes += generator.feed(3);
      bytes += generator.feed(4); // 🟢 FIX : Avance papier au lieu de cut() pour éviter le BIP !

      return await sendBytesToPrinter(bytes);
    } catch (e) {
      debugPrint("[PrintService] Erreur impression achat: $e");
      return false;
    }
  }

  // ============================================
  // 📉 IMPRESSION TICKET DE PERTE
  // ============================================

  /// Imprime un ticket de déclaration de perte en ESC/POS
  Future<bool> printLossTicket({
    String storeName = "Infinity POS",
    required String productName,
    String? variantName,
    required double qty,
    required String reason,
    double unitCost = 0,
    bool financialImpact = true,
    String? note,
  }) async {
    try {
      if (!await connectSavedPrinter()) {
        debugPrint("[PrintService] Impossible de se connecter à l'imprimante.");
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final posOptions = prefs.containsKey('pos_options_cache') ? json.decode(prefs.getString('pos_options_cache')!) : {};
      final is58mm = (posOptions['pos_receipt_size']?.toString() ?? '80mm').contains('58');
      final paperSize = is58mm ? PaperSize.mm58 : PaperSize.mm80;

      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);
      List<int> bytes = [];

      bytes += generator.reset();
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text(storeName);
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      bytes += generator.hr(ch: '=');

      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
      bytes += generator.text("DECLARATION PERTE");
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));

      final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      bytes += generator.text("Date: $now");
      bytes += generator.hr(ch: '-');

      // ─── DÉTAILS ───
      bytes += generator.row([
        PosColumn(text: 'Produit:', width: 4, styles: const PosStyles(bold: true)),
        PosColumn(text: productName, width: 8, styles: const PosStyles(align: PosAlign.right)),
      ]);

      if (variantName != null && variantName.isNotEmpty) {
        bytes += generator.row([
          PosColumn(text: 'Variante:', width: 4),
          PosColumn(text: variantName, width: 8, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.row([
        PosColumn(text: 'Quantite:', width: 4, styles: const PosStyles(bold: true)),
        PosColumn(text: '${qty.toInt()} unites', width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);

      bytes += generator.row([
        PosColumn(text: 'Raison:', width: 4),
        PosColumn(text: reason, width: 8, styles: const PosStyles(align: PosAlign.right)),
      ]);

      bytes += generator.hr(ch: '-');

      // ─── IMPACT FINANCIER ───
      final totalLoss = qty * unitCost;
      bytes += generator.row([
        PosColumn(text: 'Cout unit.:', width: 6),
        PosColumn(text: '${unitCost.toStringAsFixed(0)} DA', width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.setStyles(const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2));
      bytes += generator.text('Perte: ${totalLoss.toStringAsFixed(0)} DA');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.left));

      bytes += generator.hr(ch: '-');
      bytes += generator.text(financialImpact ? "Comptabilise en charge" : "Non-financier");

      if (note != null && note.isNotEmpty) {
        bytes += generator.text("Note: $note");
      }

      bytes += generator.hr(ch: '-');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      bytes += generator.text("Infinity POS");

      bytes += generator.feed(3);
      bytes += generator.feed(4); // 🟢 FIX : Avance papier au lieu de cut() pour éviter le BIP !

      await sendBytesToPrinter(bytes);
      return true;
    } catch (e) {
      debugPrint("[PrintService] Erreur impression perte: $e");
      return false;
    }
  }

  // ============================================
  // 🖨️ IMPRESSION RICHE HTML -> ESC/POS (NOUVEAU MOTEUR)
  // ============================================
  Future<bool> printRichHtmlTicket(String htmlContent) async {
    try {
      if (!await connectSavedPrinter()) {
        debugPrint("[PrintService] Impossible de se connecter à l'imprimante.");
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> posOptions = {};
      try {
        if (prefs.containsKey('pos_options_cache')) posOptions = json.decode(prefs.getString('pos_options_cache')!);
      } catch (_) {}

      final sizeOption = posOptions['pos_receipt_size']?.toString() ?? '80mm';
      final is58mm = sizeOption.contains('58');
      final paperSize = is58mm ? PaperSize.mm58 : PaperSize.mm80;
      final printerWidthPx = is58mm ? 384 : 576; // Largeur standard pour imprimantes ESC/POS

      // 1. HTML -> PDF (Silencieux)
      final pdfBytes = await Printing.convertHtml(
        html: htmlContent,
        format: is58mm ? PdfPageFormat.roll57 : PdfPageFormat.roll80,
      );

      // 2. PDF -> Raster Images
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);
      
      bytes += generator.reset();

      await for (var page in Printing.raster(pdfBytes, dpi: 200)) {
        // 3. Convertir en img.Image
        final image = img.Image.fromBytes(
          width: page.width,
          height: page.height,
          bytes: page.pixels.buffer,
          numChannels: 4,
        );

        // Redimensionner pour l'imprimante (largeur fixe)
        final resized = img.copyResize(image, width: printerWidthPx);

        // 4. ESC/POS
        bytes += generator.imageRaster(resized, align: PosAlign.center);
      }

      bytes += generator.feed(2);
      bytes += generator.feed(4); // 🟢 FIX : Avance papier au lieu de cut() pour éviter le BIP !

      // 5. Envoi à l'imprimante
      return await sendBytesToPrinter(bytes);
    } catch (e) {
      debugPrint("[PrintService] Erreur impression HTML: $e");
      return false;
    }
  }
}
