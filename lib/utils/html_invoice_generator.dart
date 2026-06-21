// 🟢 FIX STUDIO MOBILE FLUTTER : Générateur HTML Clone du PC (DocumentRenderer)
// Clone complet de facturation.renderer.js avec les 16 thèmes CSS
import 'package:intl/intl.dart';

class HtmlInvoiceGenerator {
  // ============================================================
  // UTILITAIRES SÉCURISÉS (Null-safe)
  // ============================================================
  static String _s(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  static double _d(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static String fmtMoney(double amount, {bool hideCurrency = false}) {
    final formatter = NumberFormat.currency(locale: 'fr', symbol: '', decimalDigits: 2);
    String res = formatter.format(amount).trim();
    return hideCurrency ? res : '$res DA';
  }

  static String fmtDate(dynamic date) {
    if (date == null) return '-';
    try {
      final d = DateTime.parse(date.toString());
      return DateFormat('dd/MM/yyyy').format(d);
    } catch (e) {
      return date.toString();
    }
  }

  static String _cleanName(String? text) {
    if (text == null || text.isEmpty) return 'Opération';
    return text
        .replaceAll(RegExp(r'Produit\s*\(Archivé\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(Archivé\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'Archivé', caseSensitive: false), '')
        .replaceAll(RegExp(r'Supprimé', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[Ref:\d+\]', caseSensitive: false), '')
        .trim();
  }

  // ============================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : POINT D'ENTRÉE PRINCIPAL
  // ============================================================
  static String generate(
    String context,
    String docType,
    Map<String, dynamic> data,
    Map<String, dynamic> config,
    Map<String, dynamic> companyInfo,
  ) {
    final renderer = _DocumentRenderer(context, docType, data, config, companyInfo);
    return renderer.generate();
  }
}

// ============================================================
// 🟢 FIX STUDIO MOBILE FLUTTER : CLASSE INTERNE DocumentRenderer
// Clone fidèle de la classe JS du PC
// ============================================================
class _DocumentRenderer {
  final String ctx;
  final String type;
  final Map<String, dynamic> data;
  final Map<String, dynamic> config;
  final Map<String, dynamic> company;

  late bool isTicket;
  late bool isPurchase;
  late bool isSingleReceipt;
  late bool isStatement;
  late bool isPaymentList;

  Map<String, dynamic> header = {'title': '', 'ref': '?', 'date': '-'};
  Map<String, dynamic> client = {'name': 'Inconnu', 'address': '', 'phone': '', 'email': '', 'detail': '', 'sub_client_name': ''};
  Map<String, dynamic> targetTaxInfo = {'nif': '', 'nis': '', 'rc': '', 'art': '', 'rib': ''};
  Map<String, dynamic> receiptData = {'amount': 0.0, 'note': '', 'method': ''};

  String payModeStr = '';
  List<Map<String, dynamic>> rows = [];
  Map<String, double> totals = {};
  Map<double, double> tvaByRate = {};
  List<dynamic> paymentsHistory = [];
  double totalProductSavings = 0;

  _DocumentRenderer(this.ctx, this.type, this.data, this.config, this.company) {
    isTicket = (config['format'] == 'Ticket' || config['format'] == 'ticket' || type == 'ticket');
    isPurchase = (ctx == 'purchases' || ctx == 'suppliers');
    isSingleReceipt = (type == 'recu_versement_unique' || type == 'recu_paiement');
    isStatement = type.contains('releve');
    isPaymentList = (type.contains('versement') || type.contains('paiements') || type.contains('bon_versement')) && !isSingleReceipt;

    _processData();
  }

  double _d(dynamic v) => HtmlInvoiceGenerator._d(v);
  String _s(dynamic v) => HtmlInvoiceGenerator._s(v);
  String _fm(double v, {bool h = false}) => HtmlInvoiceGenerator.fmtMoney(v, hideCurrency: h);
  String _fd(dynamic v) => HtmlInvoiceGenerator.fmtDate(v);
  String _cn(String? v) => HtmlInvoiceGenerator._cleanName(v);

  // ============================================================
  // TRAITEMENT DES DONNÉES
  // ============================================================
  void _processData() {
    // --- HEADER ---
    String customTitle = _s(config['customTitle']);
    header['title'] = customTitle.isNotEmpty ? customTitle.toUpperCase() : type.replaceAll('_', ' ').toUpperCase();
    if (customTitle.isEmpty) {
      if (type == 'facture') header['title'] = 'FACTURE';
      if (type == 'bl') header['title'] = 'BON DE LIVRAISON';
      if (type == 'avoir') header['title'] = 'AVOIR / RETOUR';
      if (type == 'proforma' || type == 'proforma_sale') header['title'] = 'FACTURE PROFORMA';
      if (type == 'ticket') header['title'] = 'TICKET DE CAISSE';
      if (type == 'bon_commande') header['title'] = 'BON DE COMMANDE';
      if (type == 'bon_reception') header['title'] = 'BON DE RÉCEPTION';
      if (type == 'releve_client') header['title'] = 'RELEVÉ DE COMPTE';
      if (type == 'releve_detail_client') header['title'] = 'RELEVÉ DE COMPTE DÉTAILLÉ';
      if (type == 'releve_fourn') header['title'] = 'RELEVÉ FOURNISSEUR';
      if (type == 'releve_detail_fourn') header['title'] = 'RELEVÉ FOURNISSEUR DÉTAILLÉ';
      if (type == 'bon_versement_client') header['title'] = 'HISTORIQUE DES VERSEMENTS';
      if (type == 'bon_versement_fourn') header['title'] = 'HISTORIQUE DES PAIEMENTS';
    }

    // --- CLIENT/FOURNISSEUR ---
    Map<String, dynamic> target = {};
    if (data['client'] != null) target = Map<String, dynamic>.from(data['client']);
    else if (data['supplier'] != null) target = Map<String, dynamic>.from(data['supplier']);
    else if (data['clientOrSupplier'] != null) target = Map<String, dynamic>.from(data['clientOrSupplier']);
    else if (data['payload'] != null && data['payload']['client'] != null) target = Map<String, dynamic>.from(data['payload']['client']);

    client['name'] = target['name'] ?? (data['sale'] != null ? data['sale']['client_name'] : null) ?? (data['po'] != null ? data['po']['supplier_name'] : null) ?? 'Client Comptoir';
    client['address'] = target['address'] ?? '';
    client['phone'] = target['phone'] ?? '';
    client['email'] = target['email'] ?? '';
    client['sub_client_name'] = target['sub_client_name'] ?? data['sub_client_name'] ?? (data['sale'] != null ? data['sale']['sub_client_name'] : null) ?? '';

    targetTaxInfo = {
      'nif': _s(target['nif']),
      'nis': _s(target['nis']),
      'rc': _s(target['rc']),
      'art': _s(target['artImposition'] ?? target['art']),
      'rib': _s(target['rib']),
    };

    // --- MODE DE PAIEMENT ---
    if (config['showPaymentMode'] == true && data['sale'] != null && data['sale']['payment_type'] != null) {
      String m = _s(data['sale']['payment_type']).toLowerCase();
      if (m.contains('cash') || m.contains('espece')) payModeStr = 'ESPÈCE';
      else if (m.contains('cheque')) payModeStr = 'CHÈQUE';
      else if (m.contains('card') || m.contains('carte')) payModeStr = 'CARTE';
      else if (m.contains('virement')) payModeStr = 'VIREMENT';
      else if (m.contains('credit')) payModeStr = 'CRÉDIT';
      else payModeStr = _s(data['sale']['payment_type']).toUpperCase();
    }
    if (isPurchase && data['po'] != null && data['po']['payment_type'] != null) {
      payModeStr = _s(data['po']['payment_type']).toUpperCase();
    }

    // --- INITIALISATION TOTAUX ---
    totals = {
      'ht': 0, 'tva': 0, 'ttc': 0, 'paid': 0, 'rest': 0,
      'discount': 0, 'old_debt': 0, 'final_due': 0, 'timbre': 0,
      'total_debit': 0, 'total_credit': 0,
    };
    tvaByRate = {};
    totalProductSavings = 0;

    _calculateRowsAndTotals();
  }

  // ============================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : MOTEUR DE CALCUL (Clone PC)
  // ============================================================
  void _calculateRowsAndTotals() {
    // ========== REÇUS DE VERSEMENT ==========
    if (isSingleReceipt) {
      header['title'] = isPurchase ? 'BON DE PAIEMENT' : 'REÇU DE VERSEMENT';
      Map<String, dynamic>? pObj;
      if (data['amount'] != null && data['date'] != null) {
        pObj = data;
      } else if (data['payments'] != null && (data['payments'] as List).isNotEmpty) {
        pObj = Map<String, dynamic>.from((data['payments'] as List).first);
      }
      if (pObj != null) {
        header['ref'] = pObj['id'] != null ? (isPurchase ? 'PAY-FRN-${pObj['id']}' : 'PAY-CLT-${pObj['id']}') : 'NOUVEAU';
        header['date'] = _fd(pObj['date']);
        receiptData['amount'] = _d(pObj['amount']);
        receiptData['method'] = _s(pObj['method']).isEmpty ? 'Espèces' : _s(pObj['method']);
        receiptData['note'] = _s(pObj['note']);
        payModeStr = _s(receiptData['method']).toUpperCase();
      }
      totals['ttc'] = _d(receiptData['amount']);
      if (config['showTva'] == true) {
        totals['ht'] = totals['ttc']! / 1.19;
        totals['tva'] = totals['ttc']! - totals['ht']!;
      } else {
        totals['ht'] = totals['ttc']!;
        totals['tva'] = 0;
      }
      double finalBalance = _d(data['totals']?['balance'] ?? data['supplier']?['balance'] ?? data['client']?['balance'] ?? 0);
      totals['rest'] = finalBalance;
      totals['old_debt'] = finalBalance + totals['ttc']!;

      if (data['payments'] != null && config['showPayments'] == true) {
        rows = (data['payments'] as List).map((p) => <String, dynamic>{
          'ref': _fd(p['date']),
          'name': _cn(_s(p['note'])).isEmpty ? 'Versement (${p['method']})' : _cn(_s(p['note'])),
          'qty': '-',
          'priceTtc': 0.0,
          'total': _d(p['amount']),
        }).toList();
      }
      return;
    }

    // ========== VENTES, ACHATS, BROUILLONS ==========
    if (ctx == 'sales' || ctx == 'purchases' || ctx == 'drafts') {
      Map<String, dynamic> docData = {};
      List<dynamic> items = [];
      bool isDraft = false;

      if (ctx == 'sales') { docData = Map<String, dynamic>.from(data['sale'] ?? {}); items = data['items'] ?? []; }
      else if (ctx == 'purchases') { docData = Map<String, dynamic>.from(data['po'] ?? {}); items = data['items'] ?? []; }
      else if (ctx == 'drafts') { isDraft = true; docData = Map<String, dynamic>.from(data['payload'] ?? {}); items = docData['cart'] ?? []; }

      header['ref'] = _s(docData['invoice_number'] ?? docData['number'] ?? docData['label'] ?? docData['id'] ?? '-');
      header['date'] = _fd(docData['date'] ?? docData['created_at'] ?? DateTime.now().toIso8601String());

      if (isDraft) {
        if (type == 'bl') { config['showBalance'] = false; config['colPriceTtc'] = false; }
        if (type == 'proforma') { config['showBalance'] = false; }
      }

      totals['discount'] = _d(docData['discount_value'] ?? docData['discount']).abs();
      double dbTotalTTC = _d(docData['total_amount'] ?? docData['total']).abs();

      // 🟢 FIX STUDIO MOBILE FLUTTER : Détection intelligente HT/TTC
      double sumRaw = 0, sumRawWithTva = 0;
      bool showTva = config['showTva'] == true;

      for (var i in items) {
        double q = _d(i['quantity'] ?? i['qty']);
        double p = _d(i['price_at_sale'] ?? i['unit_price_ttc'] ?? i['unit_price'] ?? i['price'] ?? i['cost'] ?? i['unit_price_ht']);
        double v = showTva ? _d(i['vat_percent'] ?? i['tva']) : 0;
        sumRaw += (q * p);
        sumRawWithTva += (q * p * (1 + (v / 100)));
      }

      double expectedTotal = dbTotalTTC + totals['discount']!;
      bool pricesAreHT = ((sumRawWithTva - expectedTotal).abs() < (sumRaw - expectedTotal).abs());

      int lineNum = 1;
      for (var i in items) {
        double qty = _d(i['quantity'] ?? i['qty']);
        double itemVatRate = showTva ? _d(i['vat_percent'] ?? i['tva']) : 0;
        double rawPrice = _d(i['price_at_sale'] ?? i['unit_price_ttc'] ?? i['unit_price'] ?? i['price'] ?? i['cost'] ?? i['unit_price_ht']);

        double priceHt, priceTtc;
        if (pricesAreHT) {
          priceHt = rawPrice;
          priceTtc = priceHt * (1 + (itemVatRate / 100));
        } else {
          priceTtc = rawPrice;
          priceHt = priceTtc / (1 + (itemVatRate / 100));
        }

        double lineTotalHt = qty * priceHt;
        double lineTotalTtc = qty * priceTtc;
        double lineTva = lineTotalTtc - lineTotalHt;

        totals['ht'] = totals['ht']! + lineTotalHt;
        totals['tva'] = totals['tva']! + lineTva;

        if (itemVatRate > 0) {
          tvaByRate[itemVatRate] = (tvaByRate[itemVatRate] ?? 0) + lineTva;
        }

        // Remise par produit
        double basePrice = _d(i['original_price'] ?? i['base_price']);
        double comparePrice = pricesAreHT ? priceHt : priceTtc;
        if (basePrice <= 0) basePrice = comparePrice;

        String displayName = _cn(_s(i['product_name'] ?? i['designation'] ?? i['base_product_name'] ?? i['name'] ?? 'Produit'));
        if (config['showProductDiscount'] == true && basePrice > comparePrice && (basePrice - comparePrice) < basePrice) {
          totalProductSavings += ((basePrice - comparePrice) * qty);
          int percent = (((basePrice - comparePrice) / basePrice) * 100).round();
          if (percent > 0) {
            displayName += '<br><span style="font-size:0.85em; color:#64748b;"><span style="text-decoration:line-through;">${_fm(basePrice)}</span><strong style="color:#ef4444; margin-left:4px;">(-$percent%)</strong></span>';
          }
        }

        rows.add({
          'lineNumber': lineNum++,
          'ref': _s(i['barcode'] ?? i['product_code'] ?? i['product_ref'] ?? i['ref'] ?? i['base_reference'] ?? '-'),
          'name': displayName,
          'colis': (i['unit_per_package'] != null && _d(i['unit_per_package']) > 1) ? (qty / _d(i['unit_per_package'])).toStringAsFixed(2) : '-',
          'qty': qty,
          'vatRate': itemVatRate,
          'priceTtc': priceTtc,
          'priceHt': priceHt,
          'total': lineTotalTtc,
          'totalHt': lineTotalHt,
        });
      }

      // Timbre intelligent
      double subtotalTtc = totals['ht']! + totals['tva']! - totals['discount']!;
      double explicitTimbre = _d(docData['timbre_amount'] ?? docData['timbre']);
      if (explicitTimbre > 0) {
        totals['timbre'] = explicitTimbre;
      } else {
        double diff = dbTotalTTC - subtotalTtc;
        if (dbTotalTTC > 0 && diff > 0.5 && diff <= 10005) {
          totals['timbre'] = diff;
        }
      }

      totals['ttc'] = dbTotalTTC > 0 ? dbTotalTTC : (subtotalTtc + totals['timbre']!);

      if (isDraft) {
        totals['paid'] = 0;
        totals['rest'] = totals['ttc']!;
        totals['final_due'] = totals['ttc']!;
      } else {
        totals['paid'] = _d(docData['amount_paid']).abs();
        totals['rest'] = totals['ttc']! - totals['paid']!;
        double balanceField = _d(data['globalBalance'] ?? data['supplier']?['balance'] ?? 0);
        if (balanceField != 0) {
          totals['final_due'] = balanceField;
          bool isReturnTicket = (_d(docData['total_amount']) < 0 || docData['is_return'] == 1 || docData['is_return'] == true);
          totals['old_debt'] = totals['final_due']! - (totals['rest']! * (isReturnTicket ? -1 : 1));
        } else {
          totals['final_due'] = totals['rest']!;
        }
      }
      paymentsHistory = data['payments'] ?? [];
    }

    // ========== RELEVÉS DE COMPTE ==========
    else if (isStatement) {
      bool isDetailed = type.contains('detail');
      header['title'] = isPurchase
          ? 'RELEVÉ FOURNISSEUR${isDetailed ? ' DÉTAILLÉ' : ''}'
          : 'RELEVÉ DE COMPTE${isDetailed ? ' DÉTAILLÉ' : ''}';
      Map<String, dynamic> target = Map<String, dynamic>.from(data['client'] ?? data['supplier'] ?? {});
      header['ref'] = _s(target['id']);
      header['date'] = _fd(DateTime.now().toIso8601String());

      List<Map<String, dynamic>> timeline = [];

      if (ctx == 'clients') {
        for (var s in (data['sales'] ?? [])) {
          bool isRet = s['is_return'] == 1 || s['is_return'] == true || _d(s['total_amount']) < 0;
          double amt = _d(s['total_amount']).abs();
          String labelStr = isRet ? 'Retour / Avoir N° ${s['invoice_number'] ?? s['id']}' : 'Vente N° ${s['invoice_number'] ?? s['id']}';
          if (config['showSubClient'] == true && s['sub_client_name'] != null) labelStr += ' (Contact : ${s['sub_client_name']})';
          timeline.add({'date': s['date'], 'label': labelStr, 'debit': isRet ? 0.0 : amt, 'credit': isRet ? amt : 0.0, 'items': isDetailed ? (s['items'] ?? []) : []});
        }
        for (var p in (data['payments'] ?? [])) {
          String payLabel = 'Versement (${p['method']}) ${_s(p['note']).isNotEmpty ? '- ${p['note']}' : ''}'.trim();
          if (config['showSubClient'] == true && p['sub_client_name'] != null) payLabel += ' (Contact : ${p['sub_client_name']})';
          timeline.add({'date': p['date'], 'label': payLabel, 'debit': 0.0, 'credit': _d(p['amount'])});
        }
      } else {
        for (var p in (data['pos'] ?? [])) {
          String st = _s(p['status']);
          if (st != 'confirmed' && st != 'received' && st != 'return' && st != 'returned') continue;
          bool isRet = p['is_return'] == 1 || p['is_return'] == true || _d(p['total_amount']) < 0 || st == 'return' || st == 'returned';
          double amt = _d(p['total_amount']).abs();
          timeline.add({
            'date': p['date'],
            'label': isRet ? 'Retour Fournisseur N° ${p['number'] ?? p['id']}' : 'Achat N° ${p['number'] ?? p['id']}',
            'debit': isRet ? 0.0 : amt, 'credit': isRet ? amt : 0.0,
            'items': isDetailed ? (p['items'] ?? []) : [],
          });
        }
        for (var p in (data['payments'] ?? [])) {
          timeline.add({'date': p['date'], 'label': 'Paiement (${p['method']}) ${_s(p['note']).isNotEmpty ? '- ${p['note']}' : ''}', 'debit': 0.0, 'credit': _d(p['amount'])});
        }
      }

      timeline.sort((a, b) => _s(a['date']).compareTo(_s(b['date'])));

      double oldBalance = _d(data['oldBalance']);
      double bal = oldBalance;
      double totalDebit = 0, totalCredit = 0;

      if (data['from'] != null && data['to'] != null && oldBalance != 0) {
        rows.add({'date': '-', 'label': '<span style="font-weight:bold; color:#64748b;">RELIQUAT / SOLDE ANTÉRIEUR (Avant le ${_fd(data['from'])})</span>', 'debit': 0.0, 'credit': 0.0, 'balance': oldBalance, 'isBold': true});
      }

      for (var t in timeline) {
        double deb = _d(t['debit']);
        double cred = _d(t['credit']);
        bal += (deb - cred);
        totalDebit += deb;
        totalCredit += cred;
        rows.add({'date': _fd(t['date']), 'label': _cn(t['label']), 'debit': deb, 'credit': cred, 'balance': bal, 'isBold': true});

        if (isDetailed && t['items'] != null && (t['items'] as List).isNotEmpty) {
          for (var it in t['items']) {
            String iName = _s(it['product_name'] ?? it['designation'] ?? it['base_product_name'] ?? it['name'] ?? 'Article');
            double iQty = _d(it['quantity'] ?? it['qty']);
            double iPrice = _d(it['price_at_sale'] ?? it['unit_price'] ?? it['price']);
            rows.add({'isDetail': true, 'label': '↳ $iName (x$iQty) | ${_fm(iQty * iPrice)}'});
          }
        }
      }

      totals['ttc'] = bal;
      totals['old_debt'] = oldBalance;
      totals['total_debit'] = totalDebit;
      totals['total_credit'] = totalCredit;
      totals['rest'] = bal;
    }

    // ========== HISTORIQUE VERSEMENTS ==========
    else if (isPaymentList) {
      header['title'] = isPurchase ? 'HISTORIQUE DES PAIEMENTS' : 'HISTORIQUE DES VERSEMENTS';
      Map<String, dynamic> target = Map<String, dynamic>.from(data['client'] ?? data['supplier'] ?? {});
      header['ref'] = _s(target['id']);
      header['date'] = _fd(DateTime.now().toIso8601String());
      List<dynamic> payList = List.from(data['payments'] ?? []);
      payList.sort((a, b) => _s(b['date']).compareTo(_s(a['date'])));
      rows = payList.map((p) {
        String nameStr = _s(p['note']).isNotEmpty ? _s(p['note']) : 'Versement (${p['method']})';
        if (config['showSubClient'] == true && p['sub_client_name'] != null) nameStr += ' (Contact : ${p['sub_client_name']})';
        return <String, dynamic>{'ref': _fd(p['date']), 'name': nameStr, 'qty': '-', 'priceTtc': 0.0, 'total': _d(p['amount'])};
      }).toList();
      totals['ttc'] = rows.fold(0.0, (sum, r) => sum + _d(r['total']));
      if (data['totals'] != null && data['totals']['balance'] != null) totals['rest'] = _d(data['totals']['balance']);
    }
  }

  // ============================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : GÉNÉRATION CSS (16 THÈMES)
  // ============================================================
  String _generateCSS() {
    String styleType = _s(config['headerStyle']).isEmpty ? 'classic_boxes' : _s(config['headerStyle']);
    String color = _s(config['color']).isEmpty ? (isTicket ? '#000000' : '#6f2dbd') : _s(config['color']);
    String fontFamily = _s(config['fontFamily']).isEmpty ? 'Inter' : _s(config['fontFamily']);
    double fontSize = _d(config['fontSize']);
    if (fontSize <= 0) fontSize = 12;
    double fontSizeHeader = _d(config['fontSizeHeader']);
    if (fontSizeHeader <= 0) fontSizeHeader = fontSize;
    double fontSizeTable = _d(config['fontSizeTable']);
    if (fontSizeTable <= 0) fontSizeTable = fontSize - 1;
    double fontSizeFooter = _d(config['fontSizeFooter']);
    if (fontSizeFooter <= 0) fontSizeFooter = fontSize;
    double paddingY = _d(config['paddingY']);
    if (paddingY <= 0) paddingY = 5;
    bool zebraRows = config['zebraRows'] == true;

    String themeCSS = '';

    // 🟢 FIX STUDIO MOBILE FLUTTER : 16 thèmes CSS complets
    switch (styleType) {
      case 'style_apple_glossy':
        themeCSS = '''
          table { border-spacing: 0 8px !important; border-collapse: separate !important; }
          th { background: transparent !important; color: #94a3b8 !important; border: none !important; padding: 10px 8px !important; font-size: 0.75em !important; letter-spacing: 1px !important; }
          td { background: #ffffff !important; border-top: 1px solid #f1f5f9 !important; border-bottom: 1px solid #f1f5f9 !important; border-left: none !important; border-right: none !important; box-shadow: 0 2px 5px rgba(0,0,0,0.02) !important; }
          td:first-child { border-left: 1px solid #f1f5f9 !important; border-top-left-radius: 12px !important; border-bottom-left-radius: 12px !important; }
          td:last-child { border-right: 1px solid #f1f5f9 !important; border-top-right-radius: 12px !important; border-bottom-right-radius: 12px !important; }
          .totals-box { background: rgba(255,255,255,0.8) !important; border: 1px solid #e2e8f0 !important; border-radius: 16px !important; box-shadow: 0 10px 30px rgba(0,0,0,0.04) !important; padding: 20px !important; }
          .total-final { border-top: 1px solid #e2e8f0 !important; font-size: 1.3em !important; padding-top: 10px !important; }
        ''';
        break;
      case 'style_creative_pill':
        themeCSS = '''
          table { border-spacing: 0 10px !important; border-collapse: separate !important; }
          th { background: ${color}15 !important; color: $color !important; border-radius: 20px !important; border: none !important; padding: 12px 5px !important; }
          td { border-top: 2px dashed ${color}40 !important; border-bottom: 2px dashed ${color}40 !important; background: transparent !important; border-left: none !important; border-right: none !important; }
          td:first-child { border-left: 2px dashed ${color}40 !important; border-top-left-radius: 20px !important; border-bottom-left-radius: 20px !important; }
          td:last-child { border-right: 2px dashed ${color}40 !important; border-top-right-radius: 20px !important; border-bottom-right-radius: 20px !important; }
          .totals-box { border: 2px dashed $color !important; border-radius: 30px !important; background: ${color}05 !important; }
          .total-final { border-top: 2px dashed $color !important; }
        ''';
        break;
      case 'style_vintage_paper':
        themeCSS = '''
          body, .page-container { background: #fdfbf7 !important; color: #3e3328 !important; font-family: 'Times New Roman', serif !important; }
          * { color: #3e3328 !important; font-family: 'Times New Roman', serif !important; }
          table { border: 4px double #4a3f35 !important; border-collapse: collapse !important; }
          th { background: #efebe1 !important; border-bottom: 2px solid #4a3f35 !important; border-right: 1px solid #4a3f35 !important; border-left: none !important; border-top: none !important; font-weight: bold !important; color: #000 !important; }
          td { border-bottom: 1px solid #d3cdc1 !important; border-right: 1px solid #d3cdc1 !important; border-left: none !important; border-top: none !important; }
          .totals-box { background: transparent !important; border: 4px double #4a3f35 !important; border-radius: 0 !important; }
          .total-final { border-top: 2px solid #4a3f35 !important; font-style: italic !important; font-size: 1.3em !important; }
        ''';
        break;
      case 'style_elegant_gold':
        themeCSS = '''
          table { border-top: 1px solid $color !important; border-bottom: 1px solid $color !important; border-collapse: collapse !important; }
          th { background: transparent !important; color: $color !important; border-bottom: 1px solid $color !important; border-top: none !important; border-left: none !important; border-right: none !important; font-weight: 400 !important; letter-spacing: 1px !important; }
          td { border-bottom: 1px solid #f1f5f9 !important; font-weight: 300 !important; border-left: none !important; border-right: none !important; border-top: none !important; }
          .totals-box { background: transparent !important; border: 1px solid $color !important; border-radius: 0 !important; padding: 20px !important; }
          .total-final { border-top: 1px solid $color !important; font-weight: 300 !important; letter-spacing: 1px !important; font-size: 1.2em !important; color: $color !important; }
        ''';
        break;
      case 'style_color_band':
        themeCSS = '''
          table { border-collapse: collapse !important; border-radius: 8px !important; overflow: hidden !important; box-shadow: 0 4px 6px rgba(0,0,0,0.05) !important; border: 1px solid #e2e8f0 !important; }
          th { background: $color !important; color: #fff !important; border: none !important; padding: 12px 8px !important; }
          td { border-bottom: 1px solid #e2e8f0 !important; border-left: none !important; border-right: none !important; }
          .totals-box { background: #f8fafc !important; border: none !important; border-top: 4px solid $color !important; }
          .total-final { border-top: 1px solid #cbd5e1 !important; color: $color !important; }
        ''';
        break;
      case 'classic_elegant':
        themeCSS = '''
          table { border-collapse: collapse !important; border-top: 2px solid $color !important; border-bottom: 2px solid $color !important; }
          th { background: #f8fafc !important; color: #334155 !important; border-bottom: 1px solid #cbd5e1 !important; border-top: none !important; border-left: none !important; border-right: none !important; padding: 10px 5px !important; text-transform: uppercase; font-size: 0.85em !important; }
          td { border-bottom: 1px solid #f1f5f9 !important; border-left: none !important; border-right: none !important; }
          .totals-box { border: 1px solid #e2e8f0 !important; border-radius: 6px !important; background: #fdfdfd !important; }
          .total-final { border-top: 2px solid $color !important; }
        ''';
        break;
      case 'minimal_lines':
        themeCSS = '''
          table { border-collapse: collapse !important; }
          th { background: transparent !important; color: #475569 !important; border-bottom: 1px solid #e2e8f0 !important; border-top: none !important; border-left: none !important; border-right: none !important; }
          td { border-bottom: 1px solid #f1f5f9 !important; border-left: none !important; border-right: none !important; }
          .totals-box { border: none !important; border-top: 1px solid #e2e8f0 !important; border-radius: 0 !important; background: transparent !important; }
          .total-final { border-top: 1px solid $color !important; }
        ''';
        break;
      case 'ultra_compact':
        themeCSS = '''
          table { border-collapse: collapse !important; }
          th { background: #f8fafc !important; color: #1e293b !important; border-bottom: 2px solid $color !important; border-top: none !important; border-left: none !important; border-right: none !important; padding: 4px !important; font-size: 0.75em !important; text-transform: uppercase; font-weight: bold !important; }
          td { border-bottom: 1px solid #e2e8f0 !important; border-left: none !important; border-right: none !important; padding: 4px !important; font-size: 0.85em !important; }
          .totals-box { border: none !important; border-radius: 0 !important; padding: 0 0 0 15px !important; background: transparent !important; }
          .total-final { border-top: 2px solid $color !important; font-size: 1.1em !important; color: $color !important; }
        ''';
        break;
      case 'compact_clean':
        themeCSS = '''
          table { border-collapse: collapse !important; }
          th { background: ${color}10 !important; color: #000 !important; border: 1px solid #cbd5e1 !important; padding: 6px 4px !important; font-size: 0.8em !important; }
          td { border: 1px solid #e2e8f0 !important; padding: 4px !important; font-size: 0.9em !important; }
          .totals-box { border: 1px solid #cbd5e1 !important; border-radius: 0 !important; padding: 8px !important; }
          .total-final { border-top: 1px solid #000 !important; }
        ''';
        break;
      case 'elegant_centered':
        themeCSS = '''
          table { border-collapse: collapse !important; border-top: 2px solid $color !important; border-bottom: 2px solid $color !important; }
          th { background: transparent !important; color: $color !important; border-bottom: 1px solid ${color}40 !important; text-align: center !important; }
          td { border-bottom: 1px solid #f1f5f9 !important; text-align: center !important; }
          .totals-box { border: 2px solid $color !important; border-radius: 12px !important; background: ${color}05 !important; }
          .total-final { border-top: 2px solid $color !important; color: $color !important; }
        ''';
        break;
      case 'pro_modern':
        themeCSS = '''
          table { border-collapse: separate !important; border-spacing: 0 !important; border: 1px solid #e2e8f0 !important; border-radius: 8px !important; overflow: hidden !important; }
          th { background: #f1f5f9 !important; color: #475569 !important; border-bottom: 2px solid #e2e8f0 !important; border-top: none !important; border-left: none !important; border-right: none !important; }
          td { border-bottom: 1px solid #f1f5f9 !important; border-left: none !important; border-right: none !important; }
          .totals-box { background: #f8fafc !important; border: none !important; border-radius: 8px !important; }
          .total-final { border-top: 1px dashed #cbd5e1 !important; color: $color !important; }
        ''';
        break;
      case 'style_split_modern':
        themeCSS = '''
          table { border-collapse: collapse !important; }
          th { background: #f8fafc !important; color: $color !important; border-bottom: 2px solid $color !important; border-top: none !important; border-left: none !important; border-right: none !important; }
          td { border-bottom: 1px solid #f1f5f9 !important; border-left: none !important; border-right: none !important; }
          .totals-box { background: #f8fafc !important; border: 1px solid #e2e8f0 !important; border-radius: 8px !important; }
          .total-final { border-top: 2px solid $color !important; color: $color !important; }
        ''';
        break;
      case 'style_bold_title':
        themeCSS = '''
          table { border-collapse: collapse !important; border: 2px solid $color !important; }
          th { background: $color !important; color: #fff !important; border: none !important; padding: 12px 8px !important; font-size: 0.9em !important; }
          td { border-bottom: 1px solid #e2e8f0 !important; padding: 8px !important; }
          .totals-box { background: ${color}08 !important; border: 2px solid $color !important; border-radius: 8px !important; }
          .total-final { border-top: 2px solid $color !important; font-size: 1.3em !important; color: $color !important; }
        ''';
        break;
      case 'corporate_elegant':
        themeCSS = '''
          table { border-collapse: collapse !important; }
          th { background: transparent !important; color: $color !important; border-bottom: 2px solid $color !important; text-align: left !important; padding: 8px 4px !important; }
          td { border-bottom: 1px dotted #cbd5e1 !important; }
          .totals-box { background: transparent !important; border-left: 4px solid $color !important; border-radius: 0 !important; border-right: none !important; border-top: none !important; border-bottom: none !important; padding-left: 15px !important; }
          .total-final { border-top: 1px solid #cbd5e1 !important; }
        ''';
        break;
      case 'minimal_grid':
        themeCSS = '''
          table { border-collapse: collapse !important; border: 1px solid #000 !important; }
          th { background: transparent !important; color: #000 !important; border: 1px solid #000 !important; font-weight: bold !important; padding: 6px 4px !important; }
          td { border: 1px solid #000 !important; padding: 6px 4px !important; }
          .totals-box { border: 1px solid #000 !important; border-radius: 0 !important; }
          .total-final { border-top: 1px solid #000 !important; }
        ''';
        break;
      case 'compact_minimal':
        themeCSS = '''
          table { border-collapse: collapse !important; margin-top: 5px !important; }
          th { background: #f8fafc !important; color: #1e293b !important; border-bottom: 2px solid $color !important; border-top: none !important; border-left: none !important; border-right: none !important; padding: 4px !important; font-size: 0.75em !important; text-transform: uppercase; font-weight: bold !important; }
          td { border-bottom: 1px solid #e2e8f0 !important; border-left: none !important; border-right: none !important; border-top: none !important; padding: 4px !important; font-size: 0.85em !important; }
          .totals-box { border: none !important; border-radius: 0 !important; padding: 0 0 0 15px !important; background: transparent !important; }
          .total-final { border-top: 2px solid $color !important; font-size: 1.1em !important; padding-top: 4px !important; margin-top: 2px !important; color: $color !important; }
        ''';
        break;
      default: // classic_boxes
        themeCSS = '''
          table { border-collapse: collapse !important; border-radius: 8px !important; overflow: hidden !important; border: 1px solid #e2e8f0 !important; }
          th { background: $color !important; color: #fff !important; }
          td { border-bottom: 1px solid #e2e8f0 !important; }
          .totals-box { background: #f8fafc !important; border: none !important; border-top: 4px solid $color !important; }
        ''';
    }

    // 🟢 FIX STUDIO MOBILE FLUTTER : Largeurs colonnes dynamiques (clone PC)
    Map<String, double> w = {
      'num': config['showLineNumber'] == true ? (isTicket ? 6 : 4) : 0,
      'ref': config['colRef'] != false ? (isTicket ? 18 : 14) : 0,
      'desc': config['colDesc'] != false ? (isTicket ? 45 : 34) : 0,
      'colis': config['showColis'] == true ? 8 : 0,
      'qty': config['colQty'] != false ? (isTicket ? 12 : 8) : 0,
      'priceHt': config['colPriceHt'] == true ? (isTicket ? 15 : 12) : 0,
      'priceTtc': config['colPriceTtc'] != false ? (isTicket ? 18 : 12) : 0,
      'tva': (config['colTva'] == true && !isTicket) ? 6 : 0,
      'totalHt': config['colTotalHt'] == true ? (isTicket ? 18 : 14) : 0,
      'totalTtc': config['colTotalTtc'] != false ? (isTicket ? 20 : 14) : 0,
    };
    double totalW = w.values.fold(0.0, (a, b) => a + b);
    if (totalW <= 0) totalW = 1;
    String pct(double val) => '${((val / totalW) * 100).toStringAsFixed(2)}%';

    String colCSS = '''
      .col-num { width: ${pct(w['num']!)}; ${w['num']! <= 0 ? 'display: none !important;' : ''} }
      .col-ref { width: ${pct(w['ref']!)}; ${w['ref']! <= 0 ? 'display: none !important;' : ''} }
      .col-desc { width: ${pct(w['desc']!)}; ${w['desc']! <= 0 ? 'display: none !important;' : ''} }
      .col-colis { width: ${pct(w['colis']!)}; ${w['colis']! <= 0 ? 'display: none !important;' : ''} }
      .col-qty { width: ${pct(w['qty']!)}; ${w['qty']! <= 0 ? 'display: none !important;' : ''} }
      .col-price-ht { width: ${pct(w['priceHt']!)}; ${w['priceHt']! <= 0 ? 'display: none !important;' : ''} }
      .col-price-ttc { width: ${pct(w['priceTtc']!)}; ${w['priceTtc']! <= 0 ? 'display: none !important;' : ''} }
      .col-tva { width: ${pct(w['tva']!)}; ${w['tva']! <= 0 ? 'display: none !important;' : ''} }
      .col-total-ht { width: ${pct(w['totalHt']!)}; ${w['totalHt']! <= 0 ? 'display: none !important;' : ''} }
      .col-total-ttc { width: ${pct(w['totalTtc']!)}; ${w['totalTtc']! <= 0 ? 'display: none !important;' : ''} }
    ''';

    return '''<style>
      @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap');
      * { box-sizing: border-box; }
      body { margin: 0; padding: ${isTicket ? '2mm' : '10mm'}; background: transparent !important;
        font-family: '$fontFamily', sans-serif; color: #000 !important; font-size: ${fontSize}px; }
      .page-container { background: rgba(255,255,255,0.9) !important; box-sizing: border-box; position: relative;
        ${isTicket ? 'width: ${_d(config['ticketWidth']).toInt()}mm; height: auto; min-height: 50mm; margin: 0 auto; padding: 2mm; overflow: visible;' : 'width: ${config['format'] == 'A5' ? '148mm' : '210mm'}; min-height: ${config['format'] == 'A5' ? '210mm' : '297mm'}; margin: 0 auto; padding: 10mm;'} }
      .header-section { font-size: ${fontSizeHeader}pt; }
      table { font-size: ${fontSizeTable}pt; width: 100%; border-collapse: collapse; table-layout: fixed; margin-top: 10px; color: #000; }
      .totals-section, .page-footer { font-size: ${fontSizeFooter}pt; }
      .company-name { font-weight: bold; font-size: 1.4em; color: ${isTicket ? '#000' : color}; text-transform: uppercase; }
      th, td { overflow-wrap: break-word; word-break: normal; color: #000; }
      .col-qty, .col-price-ht, .col-price-ttc, .col-total-ht, .col-total-ttc, .col-num, .col-tva { white-space: nowrap; }
      .col-desc { word-break: break-word; }
      .num { text-align: right; font-weight: 700; white-space: nowrap !important; }
      .center { text-align: center; }
      th { background: ${isTicket ? 'transparent' : '${color}15'}; color: ${isTicket ? '#000' : color}; border-bottom: ${isTicket ? '2px dashed #000' : '2px solid $color'}; padding: 8px 4px; text-align: left; font-weight: bold; font-size: 0.85em; text-transform: uppercase; }
      td { border-bottom: 1px solid #f1f5f9; padding: ${paddingY}px 4px; vertical-align: middle; font-size: 0.95em; line-height: 1.3; }
      ${zebraRows ? 'tbody tr:nth-child(even) { background-color: rgba(0,0,0,0.02); }' : ''}
      .totals-section { margin-top: 15px; display: flex; flex-direction: ${isTicket ? 'column' : 'row'}; justify-content: flex-end; gap: ${isTicket ? '0' : '15px'}; color: #000; }
      .totals-box { background: transparent; padding: 12px; border-radius: 8px; width: ${isTicket ? '100%' : '50%'}; min-width: 0; box-sizing: border-box; border: 1px solid ${isTicket ? '#000' : color}; ${isTicket ? 'border-top: 2px dashed #000; border:none; margin-top: 10px;' : ''} }
      .total-row { display: flex; justify-content: space-between; margin-bottom: 4px; font-size: 0.95em; width: 100%; font-weight: 500; }
      .total-row span:last-child { white-space: nowrap; margin-left: 10px; text-align: right; font-weight: 700; }
      .total-final { border-top: 2px solid ${isTicket ? '#000' : color}; margin-top: 6px; padding-top: 6px; font-weight: 900; font-size: 1.2em; color: ${isTicket ? '#000' : color}; display: flex; justify-content: space-between; }
      ${isTicket ? '* { color: #000000 !important; font-family: "Arial", Tahoma, sans-serif !important; font-weight: 600 !important; } td, th, .total-final { font-weight: 800 !important; }' : ''}
      @media print { body { display: block !important; background: white !important; margin: 0 !important; padding: 0 !important; }
        .page-container { background: white !important; box-shadow: none !important; border: none !important; width: 100% !important; height: auto !important; min-height: 0 !important; margin: 0 !important; padding: 0 !important; overflow: visible !important; }
        table { page-break-inside: auto; } tr { page-break-inside: avoid; } thead { display: table-header-group; }
        .totals-section, .client-box-styled { page-break-inside: avoid !important; } }
      $colCSS
      $themeCSS
    </style>''';
  }

  // ============================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : RENDU HEADER
  // ============================================================
  String _renderHeader() {
    if (config['showHeader'] == false) return '';
    String color = _s(config['color']).isEmpty ? '#6f2dbd' : _s(config['color']);
    double scale = _d(config['logoScale']);
    if (scale <= 0) scale = 100;
    String vendorName = _s(data['sale']?['display_user_name'] ?? data['sale']?['full_name'] ?? data['sale']?['source'] ?? data['user_name'] ?? 'ADMIN').toUpperCase();

    // --- COMPANY INFO BLOCKS ---
    String emDataHtml = '';
    if (config['showName'] != false) emDataHtml += '<div style="font-weight: bold; font-size: 1.1em; margin-bottom: 8px; color: $color;">${_s(company['name']).isEmpty ? 'MON ENTREPRISE' : company['name']}</div>';
    if (config['showActivity'] == true && _s(company['activity']).isNotEmpty) emDataHtml += '<div><span style="display:inline-block; width:75px;">Activité :</span> ${company['activity']}</div>';
    if (config['showAddress'] != false && _s(company['address']).isNotEmpty) emDataHtml += '<div><span style="display:inline-block; width:75px;">Adresse :</span> ${company['address']}</div>';
    if (config['showPhone'] != false && _s(company['phone']).isNotEmpty) emDataHtml += '<div><span style="display:inline-block; width:75px;">Tél :</span> ${company['phone']}</div>';
    if (config['showEmail'] == true && _s(company['email']).isNotEmpty) emDataHtml += '<div><span style="display:inline-block; width:75px;">Email :</span> ${company['email']}</div>';

    String emFiscHtml = '';
    if (config['showRc'] != false && _s(company['rc']).isNotEmpty) emFiscHtml += '<div>RC : ${company['rc']}</div>';
    if (config['showNif'] != false && _s(company['nif']).isNotEmpty) emFiscHtml += '<div>NIF : ${company['nif']}</div>';
    if (config['showNis'] != false && _s(company['nis']).isNotEmpty) emFiscHtml += '<div>NIS : ${company['nis']}</div>';
    if (config['showArt'] != false && _s(company['art']).isNotEmpty) emFiscHtml += '<div>ART : ${company['art']}</div>';
    if (config['showRib'] == true && _s(company['rib']).isNotEmpty) emFiscHtml += '<div>RIB : ${company['rib']}</div>';

    // --- CLIENT INFO BLOCKS ---
    String clDataHtml = '';
    if (config['showClientName'] != false) {
      clDataHtml += '<div style="font-weight: bold; font-size: 1.1em; margin-bottom: ${_s(client['sub_client_name']).isNotEmpty ? '2px' : '8px'}; color: $color;">${client['name']}</div>';
      if (config['showSubClient'] == true && _s(client['sub_client_name']).isNotEmpty) clDataHtml += '<div style="font-size: 0.9em; font-weight: 600; color: #475569; margin-bottom: 8px;">Contact : ${client['sub_client_name']}</div>';
    }
    if (config['showClientDetail'] != false && _s(client['address']).isNotEmpty) clDataHtml += '<div><span style="display:inline-block; width:75px;">Adresse :</span> ${client['address']}</div>';
    if (config['showClientPhone'] != false && _s(client['phone']).isNotEmpty) clDataHtml += '<div><span style="display:inline-block; width:75px;">Tél :</span> ${client['phone']}</div>';
    if (config['showClientEmail'] == true && _s(client['email']).isNotEmpty) clDataHtml += '<div><span style="display:inline-block; width:75px;">Email :</span> ${client['email']}</div>';

    String clFiscHtml = '';
    if (config['showClientRc'] != false && targetTaxInfo['rc']!.isNotEmpty) clFiscHtml += '<div>RC : ${targetTaxInfo['rc']}</div>';
    if (config['showClientNif'] != false && targetTaxInfo['nif']!.isNotEmpty) clFiscHtml += '<div>NIF : ${targetTaxInfo['nif']}</div>';
    if (config['showClientNis'] != false && targetTaxInfo['nis']!.isNotEmpty) clFiscHtml += '<div>NIS : ${targetTaxInfo['nis']}</div>';
    if (config['showClientArt'] == true && targetTaxInfo['art']!.isNotEmpty) clFiscHtml += '<div>ART : ${targetTaxInfo['art']}</div>';
    if (config['showClientRib'] == true && targetTaxInfo['rib']!.isNotEmpty) clFiscHtml += '<div>RIB : ${targetTaxInfo['rib']}</div>';

    // ========== TICKET HEADER ==========
    if (isTicket) {
      return '''
      <div style="text-align:center; margin-bottom:5px;">
        ${config['showLogo'] == true && _s(company['logo_url']).isNotEmpty ? '<img src="${company['logo_url']}" style="max-height:${scale}px; width:auto; max-width:90%; object-fit:contain; display:block; margin: 0 auto 8px auto; border-radius:4px;">' : ''}
        ${config['showName'] != false ? '<div style="font-size:1.4em; font-weight:bold; margin-bottom:2px;">${_s(company['name']).isEmpty ? 'MON ENTREPRISE' : company['name']}</div>' : ''}
        <div style="font-size:0.9em; line-height:1.2;">
          ${config['showAddress'] != false && _s(company['address']).isNotEmpty ? '<div>${company['address']}</div>' : ''}
          ${config['showPhone'] != false && _s(company['phone']).isNotEmpty ? '<div>Tel: ${company['phone']}</div>' : ''}
        </div>
        <div style="font-size:0.8em; margin-top:3px; line-height:1.1;">
          ${config['showRc'] != false && _s(company['rc']).isNotEmpty ? '<span>RC:${company['rc']}</span> ' : ''}
          ${config['showNif'] != false && _s(company['nif']).isNotEmpty ? '<span>NIF:${company['nif']}</span> ' : ''}
          ${config['showNis'] != false && _s(company['nis']).isNotEmpty ? '<span>NIS:${company['nis']}</span> ' : ''}
          ${config['showArt'] != false && _s(company['art']).isNotEmpty ? '<span>ART:${company['art']}</span>' : ''}
        </div>
        ${config['showRib'] == true && _s(company['rib']).isNotEmpty ? '<div style="font-size:0.8em; font-weight:bold; margin-top:2px;">RIB: ${company['rib']}</div>' : ''}
        <div style="margin-top:8px; border-top:1px dashed #000; border-bottom:1px dashed #000; padding:8px 0;">
          <div style="border:2px solid #000; display:inline-block; padding:4px 8px; font-weight:bold; margin-bottom:8px; border-radius:4px; font-size:1.1em;">${header['title']}</div>
          <div style="font-size:1.2em; font-weight:bold;">N° ${header['ref']}</div>
          <div style="font-size:0.9em;">Le ${header['date']}</div>
          ${config['showUser'] == true ? '<div style="font-size:0.9em; margin-top:3px;">Vendeur : <strong>$vendorName</strong></div>' : ''}
          ${config['showPaymentMode'] == true && payModeStr.isNotEmpty ? '<div style="font-size:0.9em;">Mode : <strong>$payModeStr</strong></div>' : ''}
        </div>
      </div>
      ${!isSingleReceipt && config['showClientBox'] != false ? '''
      <div style="text-align:center; padding:5px; border:1px solid #000; margin-bottom:10px; border-radius:4px;">
        <div style="font-size:0.8em; font-weight:bold; text-transform:uppercase;">${isPurchase ? 'Fournisseur' : 'Client'}</div>
        ${config['showClientName'] != false ? '<div style="font-weight:bold; font-size:1.1em;">${client['name']}</div>' : ''}
        <div style="font-size:0.9em;">
          ${config['showClientDetail'] != false && _s(client['address']).isNotEmpty ? '<div>${client['address']}</div>' : ''}
          ${config['showClientPhone'] != false && _s(client['phone']).isNotEmpty ? '<div>Tél: ${client['phone']}</div>' : ''}
        </div>
        <div style="font-size:0.8em; margin-top:4px;">
          ${config['showClientRc'] != false && targetTaxInfo['rc']!.isNotEmpty ? 'RC: ${targetTaxInfo['rc']}<br>' : ''}
          ${config['showClientNif'] != false && targetTaxInfo['nif']!.isNotEmpty ? 'NIF: ${targetTaxInfo['nif']}<br>' : ''}
        </div>
      </div>''' : ''}''';
    }

    // ========== A4/A5 HEADER (Default / classic_boxes) ==========
    String clientBoxHtml = '';
    if (!isSingleReceipt && config['showClientBox'] != false) {
      clientBoxHtml = '''
      <div class="client-box-styled" style="background: ${color}08; border: 1px solid ${color}30; padding: 15px; border-radius: 8px; margin-bottom: 20px; font-size: 0.9em; display: flex; justify-content: space-between; align-items: flex-start;">
        <div style="max-width: 50%;"><span style="color:$color; font-weight:bold; display:block; margin-bottom:4px; text-transform:uppercase;">${isPurchase ? 'Fournisseur' : 'Client'} :</span>$clDataHtml</div>
        <div style="text-align: right; color: #334155; font-size: 0.9em; max-width: 50%; line-height: 1.4;">$clFiscHtml</div>
      </div>''';
    }

    return '''
    <div class="header-section" style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 25px;">
      <div style="max-width: 50%; text-align: left;">
        ${config['showLogo'] == true && _s(company['logo_url']).isNotEmpty ? '<img src="${company['logo_url']}" style="height:${scale}px; max-height:200px; margin-bottom:8px; max-width:100%; object-fit:contain; display: block;">' : ''}
        $emDataHtml
        <div style="margin-top: 8px; font-size: 0.85em; color: #475569; display: grid; grid-template-columns: 1fr 1fr; gap: 4px;">$emFiscHtml</div>
      </div>
      <div style="text-align: right; min-width: 260px;">
        <div style="margin-bottom: 15px;"><span style="font-size: 1.6em; font-weight: bold; color: $color; border: 2px solid $color; padding: 6px 15px; border-radius: 4px; display: inline-block;">${header['title']}</span></div>
        <div style="display: flex; flex-direction: column; gap: 6px; font-size: 0.9em; color: #000; align-items: flex-end;">
          <div><span style="margin-right: 15px;">N° Document :</span><strong>${header['ref']}</strong></div>
          <div><span style="margin-right: 15px;">Date :</span><strong>${header['date']}</strong></div>
          ${config['showPaymentMode'] == true && payModeStr.isNotEmpty ? '<div><span style="margin-right: 15px;">Paiement :</span><strong>$payModeStr</strong></div>' : ''}
          ${config['showUser'] == true && data['sale'] != null ? '<div><span style="margin-right: 15px;">Vendeur :</span><strong>$vendorName</strong></div>' : ''}
        </div>
      </div>
    </div>
    $clientBoxHtml''';
  }

  // ============================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : RENDU TABLE
  // ============================================================
  String _renderTable() {
    if (isSingleReceipt) return _renderSingleReceipt();

    // --- STATEMENT TABLE ---
    if (isStatement) {
      String rowsHtml = rows.map((r) {
        if (r['isDetail'] == true) {
          return '<tr><td colspan="5" style="color:#64748b; font-size:0.9em; padding-left:20px;">${r['label']}</td></tr>';
        }
        return '''<tr style="${r['isBold'] == true ? 'font-weight:bold; background:#f1f5f9;' : ''}">
          <td>${r['date']}</td><td>${r['label']}</td>
          <td class="num">${_d(r['debit']) > 0 ? _fm(_d(r['debit'])) : '-'}</td>
          <td class="num">${_d(r['credit']) > 0 ? _fm(_d(r['credit'])) : '-'}</td>
          <td class="num">${_fm(_d(r['balance']))}</td>
        </tr>''';
      }).join('');

      return '''<table><thead><tr><th>Date</th><th>Opération</th><th class="num">Débit</th><th class="num">Crédit</th><th class="num">Solde</th></tr></thead><tbody>$rowsHtml</tbody></table>''';
    }

    // --- PAYMENT LIST TABLE ---
    if (isPaymentList) {
      String rowsHtml = rows.map((r) {
        return '<tr><td>${r['ref']}</td><td>${r['name']}</td><td class="num"><strong>${_fm(_d(r['total']))}</strong></td></tr>';
      }).join('');
      double totalPay = rows.fold(0.0, (sum, r) => sum + _d(r['total']));
      String totalRow = '<tr style="font-weight:bold; border-top:2px solid ${_s(config['color']).isEmpty ? '#6f2dbd' : config['color']};"><td colspan="2" style="text-align:right; padding-top:8px;">TOTAL VERSEMENTS</td><td class="num" style="padding-top:8px;">${_fm(totalPay)}</td></tr>';
      if (totals['rest'] != null && _d(totals['rest']) != 0) {
        totalRow += '<tr style="font-weight:bold;"><td colspan="2" style="text-align:right;">SOLDE RESTANT</td><td class="num" style="color:${_d(totals['rest']) > 0 ? '#dc2626' : '#16a34a'};">${_fm(_d(totals['rest']))}</td></tr>';
      }
      return '<table><thead><tr><th style="width:20%">Date</th><th style="width:auto;">Note / Méthode</th><th class="num" style="width:20%">Montant</th></tr></thead><tbody>$rowsHtml$totalRow</tbody></table>';
    }

    // --- INVOICE TABLE ---
    String headerRow = '<tr>';
    if (config['showLineNumber'] == true) headerRow += '<th class="col-num center">N°</th>';
    if (config['colRef'] != false) headerRow += '<th class="col-ref">Réf</th>';
    if (config['colDesc'] != false) headerRow += '<th class="col-desc">Désignation</th>';
    if (config['showColis'] == true) headerRow += '<th class="col-colis center">Colis</th>';
    if (config['colQty'] != false) headerRow += '<th class="col-qty center">Qté</th>';
    if (config['colPriceHt'] == true) headerRow += '<th class="col-price-ht num">PU HT</th>';
    if (config['colPriceTtc'] != false) headerRow += '<th class="col-price-ttc num">PU TTC</th>';
    if (config['colTva'] == true && !isTicket) headerRow += '<th class="col-tva center">TVA%</th>';
    if (config['colTotalHt'] == true) headerRow += '<th class="col-total-ht num">Total HT</th>';
    if (config['colTotalTtc'] != false) headerRow += '<th class="col-total-ttc num">Total TTC</th>';
    headerRow += '</tr>';

    String rowsHtml = rows.map((r) {
      String row = '<tr>';
      if (config['showLineNumber'] == true) row += '<td class="col-num center">${r['lineNumber']}</td>';
      if (config['colRef'] != false) row += '<td class="col-ref">${r['ref']}</td>';
      if (config['colDesc'] != false) row += '<td class="col-desc"><b>${r['name']}</b></td>';
      if (config['showColis'] == true) row += '<td class="col-colis center">${r['colis']}</td>';
      if (config['colQty'] != false) row += '<td class="col-qty center">${r['qty']}</td>';
      if (config['colPriceHt'] == true) row += '<td class="col-price-ht num">${_fm(_d(r['priceHt']))}</td>';
      if (config['colPriceTtc'] != false) row += '<td class="col-price-ttc num">${_fm(_d(r['priceTtc']))}</td>';
      if (config['colTva'] == true && !isTicket) row += '<td class="col-tva center">${_d(r['vatRate']).toStringAsFixed(0)}%</td>';
      if (config['colTotalHt'] == true) row += '<td class="col-total-ht num">${_fm(_d(r['totalHt']))}</td>';
      if (config['colTotalTtc'] != false) row += '<td class="col-total-ttc num"><b>${_fm(_d(r['total']))}</b></td>';
      row += '</tr>';
      return row;
    }).join('');

    // 🟢 FIX STUDIO MOBILE FLUTTER : Note interne
    String noteHtml = '';
    if (config['showInternalNote'] != false) {
      String note = _s(data['sale']?['note'] ?? data['po']?['note'] ?? '');
      if (note.isNotEmpty) {
        noteHtml = isTicket
            ? '<div style="margin-top:10px; padding:5px; border:1px dashed #000; font-size:0.9em;"><div style="font-weight:bold; text-transform:uppercase; font-size:0.8em;">Note / Instructions :</div><div style="white-space: pre-wrap;">$note</div></div>'
            : '<div style="margin-top:15px; padding:10px; background:${_s(config['color']).isEmpty ? '#6f2dbd' : config['color']}10; border:1px solid ${_s(config['color']).isEmpty ? '#6f2dbd' : config['color']}; border-radius:4px; color:#000; font-size:0.9em;"><div style="font-weight:bold; margin-bottom:2px; color:${_s(config['color']).isEmpty ? '#6f2dbd' : config['color']};">📝 Note / Instructions :</div><div style="white-space: pre-wrap; font-style:italic;">$note</div></div>';
      }
    }

    return '<table><thead>$headerRow</thead><tbody>$rowsHtml</tbody></table>$noteHtml';
  }

  // ============================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : RENDU REÇU VERSEMENT
  // ============================================================
  String _renderSingleReceipt() {
    String color = _s(config['color']).isEmpty ? '#6f2dbd' : _s(config['color']);

    String companyHtml = '<div style="font-size:1.1em; font-weight:bold;">${_s(company['name']).isEmpty ? 'MON ENTREPRISE' : company['name']}</div>';
    if (config['showAddress'] != false && _s(company['address']).isNotEmpty) companyHtml += '<div>${company['address']}</div>';
    if (config['showPhone'] != false && _s(company['phone']).isNotEmpty) companyHtml += '<div>Tél: ${company['phone']}</div>';
    List<String> companyTax = [];
    if (config['showRc'] != false && _s(company['rc']).isNotEmpty) companyTax.add('RC:${company['rc']}');
    if (config['showNif'] != false && _s(company['nif']).isNotEmpty) companyTax.add('NIF:${company['nif']}');
    if (config['showNis'] != false && _s(company['nis']).isNotEmpty) companyTax.add('NIS:${company['nis']}');
    if (companyTax.isNotEmpty) companyHtml += '<div style="font-size:0.85em; margin-top:4px;">${companyTax.join(' - ')}</div>';

    String targetHtml = '<div style="font-size:1.1em; font-weight:bold;">${client['name']}</div>';
    if (config['showSubClient'] == true && _s(client['sub_client_name']).isNotEmpty) targetHtml += '<div style="color:#475569; font-weight:600;">Contact : ${client['sub_client_name']}</div>';
    if (config['showClientDetail'] != false && _s(client['address']).isNotEmpty) targetHtml += '<div>${client['address']}</div>';
    List<String> targetTax = [];
    if (config['showClientRc'] != false && targetTaxInfo['rc']!.isNotEmpty) targetTax.add('RC:${targetTaxInfo['rc']}');
    if (config['showClientNif'] != false && targetTaxInfo['nif']!.isNotEmpty) targetTax.add('NIF:${targetTaxInfo['nif']}');
    if (targetTax.isNotEmpty) targetHtml += '<div style="font-size:0.85em; margin-top:4px;">${targetTax.join(' - ')}</div>';

    String versantHtml = isPurchase ? companyHtml : targetHtml;
    String benefHtml = isPurchase ? targetHtml : companyHtml;

    return '''
    <div style="border: 2px solid $color; padding: 15px; border-radius: 8px; margin-bottom: 20px;">
      <div style="display:flex; gap:15px;">
        <div style="flex:1;">
          <div style="text-decoration:underline; margin-bottom:5px; color:$color;">De la part de :</div>
          <div style="margin-bottom:15px; padding-left:10px; border-left:3px solid #ccc;">$versantHtml</div>
          <div style="text-decoration:underline; margin-bottom:5px; color:$color;">Au profit de :</div>
          <div style="padding-left:10px; border-left:3px solid $color;">$benefHtml</div>
        </div>
        <div style="flex:1; border-left:1px dashed $color; padding-left:15px;">
          <div style="color:$color;">Détails Paiement :</div>
          <div>Mode: <strong>${_s(receiptData['method']).toUpperCase()}</strong></div>
          <div style="font-style:italic;">Note: ${_s(receiptData['note']).isEmpty ? '-' : receiptData['note']}</div>
          <div style="margin-top:15px; background:${color}15; border:2px dashed $color; color:$color; padding:10px; text-align:center; font-weight:bold; font-size:1.6em; border-radius:8px;">${_fm(_d(receiptData['amount']))}</div>
          <div style="margin-top:15px; padding-top:10px; border-top:1px dashed $color; font-size:0.9em;">
            <div style="display:flex; justify-content:space-between;"><span>Montant HT :</span><span>${_fm(totals['ht']!)}</span></div>
            ${config['showTva'] == true ? '<div style="display:flex; justify-content:space-between;"><span>TVA :</span><span>${_fm(totals['tva']!)}</span></div>' : ''}
            <div style="display:flex; justify-content:space-between; font-weight:bold; margin-top:5px; color:$color;"><span>Montant TTC :</span><span>${_fm(totals['ttc']!)}</span></div>
          </div>
        </div>
      </div>
      ${config['showBalance'] == true ? '''
      <div style="border-top:2px solid $color; margin-top:15px; padding-top:10px;">
        ${config['showOldBalance'] == true ? '<div style="display:flex; justify-content:space-between; font-size:0.9em;"><span>Ancienne Dette :</span><span>${_fm(totals['old_debt']!)}</span></div><div style="display:flex; justify-content:space-between; font-size:0.9em; margin-bottom:5px;"><span>Montant Versé :</span><span>- ${_fm(totals['ttc']!)}</span></div>' : ''}
        <div style="display:flex; justify-content:space-between; font-weight:bold; font-size:1.2em; border-top:1px dashed $color; padding-top:5px; color:$color;"><span>Nouveau Solde :</span><span>${_fm(totals['rest']!)}</span></div>
      </div>''' : ''}
    </div>
    ${config['showPayments'] == true && rows.isNotEmpty ? '''
    <div style="margin-top:20px;">
      <div style="font-weight:bold; border-bottom:2px solid $color; margin-bottom:10px; padding-bottom:5px; color:$color">Historique des Mouvements :</div>
      <table style="width:100%; border-collapse:collapse; font-size:0.9em;">
        <thead style="background:${color}15; color:$color;"><tr><th style="padding:8px; text-align:left; border-bottom:1px solid $color;">Date</th><th style="padding:8px; text-align:left; border-bottom:1px solid $color;">Opération</th><th style="padding:8px; text-align:right; border-bottom:1px solid $color;">Montant</th></tr></thead>
        <tbody>${rows.map((p) => '<tr style="border-bottom:1px solid #f1f5f9;"><td style="padding:6px 8px;">${p['ref']}</td><td style="padding:6px 8px;">${p['name']}</td><td style="padding:6px 8px; text-align:right; font-weight:bold;">${_fm(_d(p['total']))}</td></tr>').join('')}</tbody>
      </table>
    </div>''' : ''}''';
  }

  // ============================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : RENDU TOTAUX
  // ============================================================
  String _renderTotals() {
    if (isSingleReceipt || isPaymentList) return '';
    String color = _s(config['color']).isEmpty ? '#6f2dbd' : _s(config['color']);

    // --- STATEMENT TOTALS ---
    if (isStatement) {
      bool hasDateFilter = data['from'] != null && data['to'] != null;
      String oldBalanceRow = '';
      if (hasDateFilter && _d(totals['old_debt']) != 0) {
        oldBalanceRow = '<div class="total-row" style="color:#64748b; font-weight: 500;"><span>Solde Antérieur (Avant le ${_fd(data['from'])})</span> <span>${_fm(_d(totals['old_debt']))}</span></div>';
      }

      String statementTotals = '''
      <div class="totals-section" style="margin-top:20px; display:flex; justify-content:flex-end; color:#000;">
        <div class="totals-box" style="width:${isTicket ? '100%' : '50%'}; border: 2px solid $color; padding:15px; border-radius:8px; background: ${color}05;">
          $oldBalanceRow
          <div class="total-row"><span>Total ${isPurchase ? 'Achats' : 'Facturé'} ${hasDateFilter ? '(Sur la période)' : ''}</span> <span>${_fm(totals['total_debit']!)}</span></div>
          <div class="total-row"><span>Total Versé / Retours ${hasDateFilter ? '(Sur la période)' : ''}</span> <span>${_fm(totals['total_credit']!)}</span></div>
          <div class="total-row total-final" style="border-top:2px solid $color; font-size:1.4em; font-weight:900; margin-top:8px; padding-top:8px;">
            <span>SOLDE FINAL</span>
            <span style="color:${totals['rest']! > 0 ? '#dc2626' : (totals['rest']! < 0 ? '#16a34a' : color)}">${_fm(totals['rest']!)}</span>
          </div>
        </div>
      </div>''';

      // 🟢 FIX V2 : Signatures/Cachet pour relevés (identique au PC)
      bool showLeft = config['showSignatureClient'] == true;
      bool showRight = config['showSignature'] == true || config['showStamp'] == true || config['showSignatureImg'] == true;
      if (showLeft || showRight) {
        statementTotals += '<div style="margin-top:30px; display:flex; justify-content:space-between; align-items:flex-end; page-break-inside: avoid;">';
        statementTotals += '<div style="width:40%; text-align:center;">';
        if (showLeft) statementTotals += '<div style="border-top:1px solid $color; padding-top:3px; font-size:0.75em; font-weight:bold; color:$color;">Signature ${isPurchase ? 'Fournisseur' : 'Client'}</div>';
        statementTotals += '</div>';
        statementTotals += '<div style="width:40%; text-align:center; display:flex; flex-direction:column; justify-content:flex-end; align-items:center; min-height:40px;">';
        if (config['showSignatureImg'] == true && _s(company['signature_url']).isNotEmpty) statementTotals += '<img src="${company['signature_url']}" style="max-height:80px; margin-bottom:2px;">';
        if (config['showSignature'] == true) statementTotals += '<div style="width:100%; border-top:1px solid $color; padding-top:3px; font-size:0.75em; font-weight:bold; color:$color;">Cachet & Signature</div>';
        statementTotals += '</div></div>';
      }
      return statementTotals;
    }

    // --- INVOICE TOTALS ---
    String paymentsHtml = '';
    if (config['showPayments'] == true && paymentsHistory.isNotEmpty) {
      paymentsHtml = '<div style="margin-top:20px; font-size:0.9em;"><div style="font-weight:bold; border-bottom:1px solid $color; margin-bottom:5px; color:$color;">Historique des Paiements</div><table style="width:100%; font-size:0.9em;">${paymentsHistory.map((p) => '<tr><td style="padding:2px 0;">${_fd(p['date'])}</td><td style="padding:2px 0;">${_s(p['method']).isEmpty ? 'Espèce' : p['method']}</td><td style="padding:2px 0; text-align:right;">${_fm(_d(p['amount']))}</td></tr>').join('')}</table></div>';
    }

    // TVA ventilée
    String tvaRows = '';
    if (config['showTva'] == true && totals['tva']! > 0) {
      tvaRows = tvaByRate.entries.map((e) => '<div class="total-row"><span>TVA (${e.key.toStringAsFixed(0)}%)</span> <span>${_fm(e.value)}</span></div>').join('');
    }

    String signatureHtml = '';
    if (config['showSignature'] == true || config['showSignatureClient'] == true) {
      signatureHtml = '<div style="margin-top:30px; display:flex; justify-content:space-between; align-items:flex-end;">';
      signatureHtml += '<div style="width:40%; text-align:center;">';
      if (config['showSignatureClient'] == true) signatureHtml += '<div style="border-top:1px solid $color; padding-top:3px; font-size:0.75em; font-weight:bold; color:$color;">Signature ${isPurchase ? 'Fournisseur' : 'Client'}</div>';
      signatureHtml += '</div>';
      signatureHtml += '<div style="width:40%; text-align:center;">';
      if (config['showSignatureImg'] == true && _s(company['signature_url']).isNotEmpty) signatureHtml += '<img src="${company['signature_url']}" style="max-height:80px; margin-bottom:2px;">';
      if (config['showSignature'] == true) signatureHtml += '<div style="width:100%; border-top:1px solid $color; padding-top:3px; font-size:0.75em; font-weight:bold; color:$color;">Cachet & Signature</div>';
      signatureHtml += '</div></div>';
    }

    return '''
    <div class="totals-section">
      ${paymentsHtml.isNotEmpty ? '<div style="width:${isTicket ? '100%' : '45%'}; margin-right:auto; ${isTicket ? 'order:2; margin-top:10px; border-top:1px dashed #000; padding-top:5px;' : ''}">$paymentsHtml</div>' : ''}
      <div class="totals-box" style="${isTicket ? 'width:100%; order:1;' : ''}">
        ${(config['showTotalHt'] == true || config['showTva'] == true) ? '<div class="total-row"><span>Total HT</span> <span>${_fm(totals['ht']!)}</span></div>' : ''}
        ${(config['showProductDiscount'] == true && totalProductSavings > 0 && !(config['showGlobalDiscount'] == true && totals['discount']! > 0)) ? '<div class="total-row" style="color:#000; font-weight:bold;"><span>Remise</span> <span>-${_fm(totalProductSavings)}</span></div>' : ''}
        ${(config['showGlobalDiscount'] == true && totals['discount']! > 0) ? '<div class="total-row"><span>Remise Globale</span> <span>-${_fm(totals['discount']!)}</span></div>' : ''}
        $tvaRows
        ${(config['showTva'] == true && totals['timbre']! > 0) ? '<div class="total-row"><span>Droit de Timbre</span> <span>${_fm(totals['timbre']!)}</span></div>' : ''}
        ${config['showFinalTotal'] != false ? '<div class="total-row total-final"><span>TOTAL (TTC)</span> <span>${_fm(totals['ttc']!)}</span></div>' : ''}
        ${(config['showBalance'] != false && totals['rest']! > 0.01) ? '<div class="total-row" style="margin-top:5px;"><span>Versé</span> <span>${_fm(totals['paid']!)}</span></div><div class="total-row" style="font-weight:bold;"><span>Reste Dû</span> <span>${_fm(totals['rest']!)}</span></div>' : ''}
        ${(config['showOldBalance'] == true && totals['old_debt']! > 0) ? '<div style="border-top:1px dashed $color; margin-top:5px; padding-top:5px;"><div class="total-row"><span>Ancienne Dette</span> <span>${_fm(totals['old_debt']!)}</span></div><div class="total-row" style="font-weight:bold; color:$color;"><span>SOLDE TOTAL</span> <span>${_fm(totals['final_due']!)}</span></div></div>' : ''}
      </div>
    </div>
    $signatureHtml''';
  }

  // ============================================================
  // 🟢 FIX STUDIO MOBILE FLUTTER : POINT D'ENTRÉE FINAL
  // ============================================================
  String generate() {
    String color = _s(config['color']).isEmpty ? '#6f2dbd' : _s(config['color']);
    String css = _generateCSS();

    String customMsgHtml = '';
    if (config['showCustomMsg'] != false && _s(config['customMsg']).isNotEmpty) {
      customMsgHtml = '<div style="text-align:center; margin-top: 15px; margin-bottom: 10px; font-weight: bold; font-style: italic; font-size: ${isTicket ? '0.85em' : '0.9em'}; color: ${isTicket ? '#000' : color};">${config['customMsg']}</div>';
    }

    String footerHtml = '';
    if (!isTicket && config['showFooter'] != false) {
      footerHtml = '<div class="page-footer" style="color:$color; opacity:0.8; margin-top:15px; text-align:center;">${_s(config['footerMsg']).isNotEmpty ? '${config['footerMsg']} - ' : ''}Page 1 / 1</div>';
    }

    return '''<!DOCTYPE html><html><head><meta charset="UTF-8">$css</head><body>
    <div class="page-container">
      ${_renderHeader()}
      ${_renderTable()}
      ${_renderTotals()}
      $customMsgHtml
      $footerHtml
    </div>
    </body></html>''';
  }
}
