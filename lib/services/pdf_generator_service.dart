import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class PdfGeneratorService {
  static final PdfGeneratorService _instance = PdfGeneratorService._internal();
  factory PdfGeneratorService() => _instance;
  PdfGeneratorService._internal();

Future<Uint8List> generatePdfInvoice({
    required Map<String, dynamic> saleData,
    required List<dynamic> items,
    required String format, // 'A4' or 'A5'
    Map<String, dynamic>? clientData,
    bool isReturn = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> company = {};
    String? logoB64;
    try {
      if (prefs.containsKey('company_info_cache')) {
        company = json.decode(prefs.getString('company_info_cache')!);
      }
      logoB64 = prefs.getString('company_logo_cached_b64');
    } catch (_) {}

    pw.MemoryImage? logoImage;
    if (logoB64 != null && logoB64.isNotEmpty) {
      try {
        String cleanB64 = logoB64;
        if (cleanB64.contains(',')) cleanB64 = cleanB64.split(',').last;
        cleanB64 = cleanB64.replaceAll(RegExp(r'\s+'), '');
        logoImage = pw.MemoryImage(base64Decode(cleanB64));
      } catch (_) {}
    }

    final pdf = pw.Document();
    final pageFormat = format.toUpperCase() == 'A5' ? PdfPageFormat.a5 : PdfPageFormat.a4;

    // Extraction sécurisée des données de l'entreprise
    final invoiceNumber = saleData['invoice_number']?.toString() ?? saleData['id']?.toString() ?? '-';
    final date = saleData['date'] != null 
        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(saleData['date'].toString()))
        : DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
        
    final cName = company['name']?.toString() ?? 'MON ENTREPRISE';
    final cActivity = company['activity']?.toString() ?? '';
    final cAddress = company['address']?.toString() ?? '';
    final cPhone = company['phone']?.toString() ?? '';
    final cEmail = company['email']?.toString() ?? '';
    final cRc = company['rc']?.toString() ?? '';
    final cNif = company['nif']?.toString() ?? '';
    final cNis = company['nis']?.toString() ?? '';
    final cArt = company['art']?.toString() ?? '';
    final cRib = company['rib']?.toString() ?? '';
    
    // Extraction sécurisée des données du client
    final clientName = saleData['client_name']?.toString() ?? 'Client Comptoir';
    final clSubClient = clientData?['sub_client_name']?.toString() ?? saleData['sub_client_name']?.toString() ?? '';
    final clActivity = clientData?['activity']?.toString() ?? '';
    final clAddress = clientData?['address']?.toString() ?? '';
    final clPhone = clientData?['phone']?.toString() ?? '';
    final clEmail = clientData?['email']?.toString() ?? '';
    final clRc = clientData?['rc']?.toString() ?? '';
    final clNif = clientData?['nif']?.toString() ?? '';
    final clNis = clientData?['nis']?.toString() ?? '';
    final clArt = clientData?['art']?.toString() ?? clientData?['artImposition']?.toString() ?? '';
    final clRib = clientData?['rib']?.toString() ?? '';

    // Calculs financiers et des soldes
    final paymentType = saleData['payment_type']?.toString() ?? 'Espèces';
    final amountPaid = (double.tryParse(saleData['amount_paid']?.toString() ?? '0') ?? 0).abs();
    final totalTtc = (double.tryParse(saleData['total_amount']?.toString() ?? '0') ?? 0).abs();
    final totalHt = (double.tryParse(saleData['total_ht']?.toString() ?? '0') ?? 0).abs();
    final totalTva = (double.tryParse(saleData['total_vat']?.toString() ?? '0') ?? 0).abs();
    final timbre = (double.tryParse(saleData['timbre']?.toString() ?? '0') ?? 0).abs();
    final discount = (double.tryParse(saleData['discount_value']?.toString() ?? '0') ?? 0).abs();

    final remaining = totalTtc - amountPaid;
    final clientBalance = double.tryParse(clientData?['balance']?.toString() ?? '0') ?? 0.0;
    final oldDebt = clientBalance - remaining;
    final finalDue = clientBalance;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20), // Marges plus compactes pour optimiser l'espace
        build: (pw.Context context) {
          return [
            // 1. EN-TÊTE DE PAGE ET INFOS ENTREPRISE
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoImage != null) ...[
                        pw.Image(logoImage, width: 70, height: 70, fit: pw.BoxFit.contain),
                        pw.SizedBox(width: 12),
                      ],
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(cName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                          if (cActivity.isNotEmpty) pw.Text(cActivity, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                          pw.SizedBox(height: 4),
                          if (cAddress.isNotEmpty) pw.Text("Adresse : $cAddress", style: const pw.TextStyle(fontSize: 8.5)),
                          if (cPhone.isNotEmpty) pw.Text("Tél : $cPhone", style: const pw.TextStyle(fontSize: 8.5)),
                          if (cEmail.isNotEmpty) pw.Text("Email : $cEmail", style: const pw.TextStyle(fontSize: 8.5)),
                          
                          // Bloc Fiscal Entreprise sur une ligne compacte
                          pw.SizedBox(height: 4),
                          pw.Text(
                            "${cRc.isNotEmpty ? 'RC: $cRc  ' : ''}${cNif.isNotEmpty ? 'NIF: $cNif  ' : ''}${cNis.isNotEmpty ? 'NIS: $cNis  ' : ''}${cArt.isNotEmpty ? 'ART: $cArt' : ''}",
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                          ),
                          if (cRib.isNotEmpty) pw.Text("RIB : $cRib", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(isReturn ? "FACTURE D'AVOIR" : "FACTURE", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                    pw.Text("N° $invoiceNumber", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Date : $date", style: const pw.TextStyle(fontSize: 8.5)),
                    pw.Text("Mode : $paymentType", style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.indigo100, thickness: 1.5),
            pw.SizedBox(height: 8),

            // 2. BLOC CLIENT ÉPURÉ ET COMPLET (STYLE COMPACT)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.blue100),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("FACTURÉ À :", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.SizedBox(height: 2),
                      pw.Text(clientName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900)),
                      if (clSubClient.isNotEmpty) pw.Text("Contact : $clSubClient", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                      if (clActivity.isNotEmpty) pw.Text("Activité : $clActivity", style: const pw.TextStyle(fontSize: 8.5)),
                      if (clAddress.isNotEmpty) pw.Text("Adresse : $clAddress", style: const pw.TextStyle(fontSize: 8.5)),
                      if (clPhone.isNotEmpty) pw.Text("Tél : $clPhone", style: const pw.TextStyle(fontSize: 8.5)),
                      if (clEmail.isNotEmpty) pw.Text("Email : $clEmail", style: const pw.TextStyle(fontSize: 8.5)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("INFORMATIONS FISCALES :", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.SizedBox(height: 4),
                      if (clRc.isNotEmpty) pw.Text("RC : $clRc", style: const pw.TextStyle(fontSize: 8.5)),
                      if (clNif.isNotEmpty) pw.Text("NIF : $clNif", style: const pw.TextStyle(fontSize: 8.5)),
                      if (clNis.isNotEmpty) pw.Text("NIS : $clNis", style: const pw.TextStyle(fontSize: 8.5)),
                      if (clArt.isNotEmpty) pw.Text("ART : $clArt", style: const pw.TextStyle(fontSize: 8.5)),
                      if (clRib.isNotEmpty) pw.Text("RIB : $clRib", style: const pw.TextStyle(fontSize: 8.5)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            // 3. TABLEAU DES ARTICLES (STYLE COMPACT ET PROPRE)
            pw.TableHelper.fromTextArray(
              headers: ['Réf', 'Désignation', 'Qté', 'P.U (DA)', 'Total (DA)'],
              data: items.map((item) {
                final ref = item['ref']?.toString() ?? item['product_code']?.toString() ?? '-';
                final name = item['name']?.toString() ?? 'Article';
                final qty = (double.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1).abs();
                final price = (double.tryParse(item['price']?.toString() ?? item['price_at_sale']?.toString() ?? '0') ?? 0).abs();
                final total = qty * price;
                return [
                  ref,
                  name,
                  qty.toStringAsFixed(0),
                  price.toStringAsFixed(0),
                  total.toStringAsFixed(0),
                ];
              }).toList(),
              border: const pw.TableBorder(
                bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                horizontalInside: pw.BorderSide(color: PdfColors.grey100, width: 0.5),
              ),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              cellAlignment: pw.Alignment.centerRight,
              cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft},
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            ),
            pw.SizedBox(height: 15),

            // 4. TOTAUX ET REPRISE DU SYSTÈME DE DETTES (SOLDE FINAL)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 220,
                  child: pw.Column(
                    children: [
                      if (totalHt > 0) _buildTotalRow("Total HT", totalHt),
                      if (totalTva > 0) _buildTotalRow("TVA", totalTva),
                      if (timbre > 0) _buildTotalRow("Timbre", timbre),
                      if (discount > 0) _buildTotalRow("Remise", discount, color: PdfColors.red700),
                      pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                      
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text("TOTAL TTC", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                          pw.Text("${totalTtc.toStringAsFixed(0)} DA", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(paymentType.toLowerCase().contains('credit') ? "Crédit" : "Montant Versé", style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                          pw.Text("${amountPaid.toStringAsFixed(0)} DA", style: pw.TextStyle(fontSize: 9, color: PdfColors.grey900, fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                      
                      // Système d'affichage de l'historique des soldes (comme le ticket thermique)
                      if (clientBalance.abs() > 0.1) ...[
                        pw.Divider(color: PdfColors.red200),
                        _buildTotalRow("Ancienne Dette", oldDebt, color: PdfColors.orange700),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text("Nouveau Solde", style: pw.TextStyle(color: PdfColors.red700, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                              pw.Text("${finalDue.toStringAsFixed(0)} DA", style: pw.TextStyle(color: PdfColors.red700, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            
            // Note interne s'il y en a une
            if (saleData['note'] != null && saleData['note'].toString().trim().isNotEmpty) ...[
              pw.SizedBox(height: 15),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
                ),
                child: pw.Text(
                  "Note : ${saleData['note']}",
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic),
                ),
              ),
            ],
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildTotalRow(String label, double value, {PdfColor color = PdfColors.black}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(color: color)),
          pw.Text("${value.toStringAsFixed(2)} DA", style: pw.TextStyle(color: color)),
        ],
      ),
    );
  }
}
