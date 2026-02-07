import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart'; 
import 'package:pdf/pdf.dart'; 
import 'package:flutter/foundation.dart'; 

class ApiService {
  static final ApiService _instance = ApiService._internal();
  
  factory ApiService() {
    return _instance;
  }

  ApiService._internal();

  static const String _cloudUrl = "https://api.infinityapp.site/api/mobile";
  static const String _queueKey = "offline_queue_v2";
  static const String _cacheKey = "offline_catalog_cache";

  List<Map<String, dynamic>> _globalQueue = [];
  String? _lastDataHash; 
  
  Timer? _syncTimer;
  final StreamController<void> _dataUpdateController = StreamController<void>.broadcast();
  Stream<void> get onDataUpdated => _dataUpdateController.stream;

  // --- SÉCURITÉ : Génération des Headers ---
  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    
    // On récupère la licence et le mot de passe stockés lors de l'activation
    final licenseKey = prefs.getString('license_key') ?? '';
    final apiPass = prefs.getString('api_pass') ?? '';
    
    return {
      "Content-Type": "application/json",
      // Le serveur attend la licence comme 'User' (x-pos-user)
      "x-pos-user": licenseKey,
      // Le serveur attend le mot de passe dans 'x-pos-pass'
      "x-pos-pass": apiPass,
    };
  }

  // --- AUTOMATISATION (Boucle de 2 secondes) ---
  Future<void> startAutoSync() async {
    await _loadState();
    if (_syncTimer != null && _syncTimer!.isActive) return;

    _syncTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      bool hasInternet = await _checkConnectivity();
      if (hasInternet) {
        if (_globalQueue.isNotEmpty) {
          await _processQueue();
        }
        await _checkForRemoteUpdates();
      }
    });
  }

  Future<bool> _checkConnectivity() async {
    try {
      final result = await http.head(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 3));
      return result.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkForRemoteUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('license_key');
    if (key == null) return;

    try {
      final headers = await _getHeaders();
      final response = await _getClient().get(
        Uri.parse('$_cloudUrl/sync-status?license_key=$key'),
        headers: headers
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String newHash = data['last_update_hash'] ?? '';

        if (_lastDataHash != null && _lastDataHash != newHash) {
          _dataUpdateController.add(null); 
        }
        _lastDataHash = newHash;
      }
    } catch (e) {
      // Erreur silencieuse (pas de connexion)
    }
  }

  // --- GESTION DE LA FILE D'ATTENTE (QUEUE) ---
  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedQueue = prefs.getString(_queueKey);
    if (storedQueue != null) {
      try {
        List<dynamic> decoded = json.decode(storedQueue);
        _globalQueue = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        debugPrint("Erreur chargement queue: $e");
      }
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, json.encode(_globalQueue));
  }

  Future<void> _processQueue() async {
    List<Map<String, dynamic>> processedItems = [];
    final queueSnapshot = List<Map<String, dynamic>>.from(_globalQueue);

    for (var task in queueSnapshot) {
      bool success = false;
      try {
        switch (task['type']) {
          case 'CHARGE':
            success = await _sendCommandInternal('CHARGE', task['data']);
            break;
          case 'SALE':
            success = await _sendCommandInternal('SALE', task['data']);
            break;
          case 'PURCHASE':
            success = await _sendCommandInternal('PURCHASE', task['data']);
            break;
          case 'ADD_PRODUCT':
             success = await _sendCommandInternal('ADD_PRODUCT', task['data']);
             break;
          case 'UPDATE_PRODUCT':
             success = await _sendCommandInternal('UPDATE_PRODUCT', task['data']);
             break;
          case 'STOCK_UPDATE':
             success = await _sendCommandInternal('STOCK_UPDATE', task['data']);
             break;
          case 'ADD_CLIENT':
          case 'ADD_SUPPLIER':
             success = await _sendCommandInternal(task['type'], task['data']);
             break;
          case 'PAYMENT':
             success = await _sendCommandInternal('PAYMENT', task['data']);
             break;
          case 'UPDATE_PRODUCT_IMAGE':
             success = await _sendCommandInternal('UPDATE_PRODUCT_IMAGE', task['data']);
             break;
        }
      } catch (e) {
        success = false;
      }

      if (success) {
        await _patchCacheWith(task);
        processedItems.add(task);
      } else {
        // On arrête si une tâche échoue pour préserver l'ordre
        break; 
      }
    }

    if (processedItems.isNotEmpty) {
      _globalQueue.removeWhere((element) => processedItems.contains(element));
      await _saveState();
      _dataUpdateController.add(null); 
    }
  }

  void _addToQueue(Map<String, dynamic> task) {
    _globalQueue.add(task);
    _saveState();
    _processQueue();
  }

  Future<void> _patchCacheWith(Map<String, dynamic> task) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jsonStr = prefs.getString(_cacheKey);
      Map<String, dynamic> cache = jsonStr != null ? json.decode(jsonStr) : {'products': [], 'categories': []};
      
      List<dynamic> products = List.from(cache['products'] ?? []);

      if (task['type'] == 'ADD_PRODUCT') {
        Map<String, dynamic> newProduct = Map<String, dynamic>.from(task['data']);
        newProduct.remove('image_data'); 
        products.insert(0, newProduct);
      } else if (task['type'] == 'UPDATE_PRODUCT') {
        int idx = products.indexWhere((p) => p['id'].toString() == task['data']['id'].toString());
        if (idx != -1) {
          products[idx] = <String, dynamic>{...products[idx], ...task['data']};
        }
      } else if (task['type'] == 'SALE') {
        List items = task['data']['items'] ?? [];
        for(var item in items) {
           int idx = products.indexWhere((p) => p['id'].toString() == item['product_id'].toString());
           if(idx != -1) {
             double current = double.tryParse(products[idx]['stock'].toString()) ?? 0;
             double qty = double.tryParse(item['qty'].toString()) ?? 0;
             products[idx]['stock'] = current - qty;
           }
        }
      }
      cache['products'] = products;
      await prefs.setString(_cacheKey, json.encode(cache));
    } catch(e) { }
  }

Future<void> addProductOptimistic(Map<String, dynamic> rawData) async {
    // Si l'ID existe déjà dans rawData, on l'utilise. Sinon, on en génère un.
    final String tempId = rawData['id'] ?? "TEMP-${DateTime.now().millisecondsSinceEpoch}";
    
    final data = Map<String, dynamic>.from(rawData);
    data['id'] = tempId;
    data['is_local'] = true;

    _addToQueue({
      'type': 'ADD_PRODUCT', 'temp_id': tempId, 'date': DateTime.now().toIso8601String(), 'data': data
    });
    _dataUpdateController.add(null);
  }

  Future<void> updateProductOptimistic(Map<String, dynamic> data) async {
    _addToQueue({
      'type': 'UPDATE_PRODUCT', 'temp_id': "UP-${data['id']}", 'date': DateTime.now().toIso8601String(), 'data': data
    });
    _dataUpdateController.add(null);
  }
Future<void> sendComplexSaleOptimistic(double total, List<dynamic> items, {String? note, int? clientId, String? clientName, double? amountPaid, String? paymentType, double? discount}) async {
    _addToQueue({
      'type': 'SALE',
      'temp_id': "SALE-${DateTime.now().millisecondsSinceEpoch}",
      'date': DateTime.now().toIso8601String(),
      'data': {
        "total": total,        // Total NET (après remise)
        "total_amount": total, // Idem
        "items": items,
        "note": note,
        "client_id": clientId,
        "client_name": clientName,
        "amount_paid": amountPaid,
        "payment_type": paymentType,
        "discount_value": discount ?? 0, // ✅ NOUVEAU : On envoie la remise
        "discount_mode": "amount" // On précise que c'est un montant fixe en DA
      }
    });
    _dataUpdateController.add(null);
}

Future<void> sendComplexPurchase(double total, List<dynamic> items, {String? note, int? supplierId, String? supplierName, double? amountPaid, String? paymentType}) async {
    _addToQueue({
      'type': 'PURCHASE',
      'temp_id': "PUR-${DateTime.now().millisecondsSinceEpoch}",
      'date': DateTime.now().toIso8601String(),
      'data': {
        "total": total,        // <--- AJOUT CRUCIAL : Le serveur lit ça pour éviter le 0
        "total_amount": total, // On garde pour compatibilité
        "items": items,
        "note": note,
        "supplier_id": supplierId,
        "supplier_name": supplierName,
        "amount_paid": amountPaid,
        "payment_type": paymentType
      }
    });
    _dataUpdateController.add(null);
  }
  Future<void> addChargeOptimistic(String label, double amount, String category) async {
    _addToQueue({
      'type': 'CHARGE', 'temp_id': "CHG-${DateTime.now().millisecondsSinceEpoch}", 'date': DateTime.now().toIso8601String(),
      'data': {'label': label, 'amount': amount, 'category': category}
    });
    _dataUpdateController.add(null);
  }
  
  Future<void> sendStockUpdate(int productId, double quantity, String type) async {
     _addToQueue({
      'type': 'STOCK_UPDATE', 'temp_id': "STK-${DateTime.now().millisecondsSinceEpoch}", 'date': DateTime.now().toIso8601String(),
      'data': {"product_id": productId, "quantity": quantity, "type": type}
    });
    _dataUpdateController.add(null);
  }

  Future<void> sendPartnerPaymentOptimistic({required int partnerId, required double amount, required String type, String? note}) async {
    _addToQueue({
      'type': 'PAYMENT', 'temp_id': "PAY-${DateTime.now().millisecondsSinceEpoch}", 'date': DateTime.now().toIso8601String(),
      'data': {"partner_id": partnerId, "amount": amount, "type": type, "note": note}
    });
    _dataUpdateController.add(null);
  }

  Future<void> createTierOptimistic(String type, Map<String, dynamic> data) async {
    final tempId = -1 * DateTime.now().millisecondsSinceEpoch;
    _addToQueue({
      'type': type == 'client' ? 'ADD_CLIENT' : 'ADD_SUPPLIER',
      'temp_id': "TIER-$tempId",
      'date': DateTime.now().toIso8601String(),
      'data': {...data, 'id': tempId, 'is_local': true}
    });
    _dataUpdateController.add(null);
  }
  
  Future<void> createTier(String type, Map<String, dynamic> data) async {
      return createTierOptimistic(type, data);
  }

  // --- 1. CATALOGUE PRODUITS (CORRIGÉ & ROBUSTE) ---
  Future<Map<String, dynamic>> getProductsWithQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('license_key');
    
    // Structure par défaut
    Map<String, dynamic> resultData = {'products': [], 'categories': [], 'sub_categories': []};

    // 1. Charger Cache Local
    if (prefs.containsKey(_cacheKey)) {
      try {
        final cacheStr = prefs.getString(_cacheKey)!;
        final decoded = json.decode(cacheStr);
        if (decoded is List) {
          resultData['products'] = decoded;
        } else if (decoded is Map) {
          resultData = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        debugPrint("⚠️ Erreur lecture cache: $e");
      }
    }

    // 2. Tenter Mise à jour Serveur (Utilise la route /get-products)
    if (key != null) {
      try {
        final headers = await _getHeaders();
        final response = await _getClient().get(
            Uri.parse('$_cloudUrl/get-products?license_key=$key'),
            headers: headers
        ).timeout(const Duration(seconds: 15));
        
        if (response.statusCode == 200) {
          final dynamic rawData = json.decode(response.body);
          List<dynamic> fetchedProducts = [];
          
          if (rawData is List) {
            fetchedProducts = rawData;
          } else if (rawData is Map && rawData.containsKey('products')) {
            fetchedProducts = rawData['products'];
          }

          resultData['products'] = fetchedProducts;
          
          final cats = <String>{};
          final subs = <String>{};
          for (var p in fetchedProducts) {
            if (p['category'] != null) cats.add(p['category'].toString());
            if (p['sub_category'] != null) subs.add(p['sub_category'].toString());
          }
          resultData['categories'] = cats.toList();
          resultData['sub_categories'] = subs.toList();

          // Mise à jour du cache
          await prefs.setString(_cacheKey, json.encode(resultData));
        }
      } catch (e) {
        debugPrint("❌ Erreur Réseau Produits: $e");
      }
    }

    // 3. Fusion avec file d'attente (Actions locales)
    List<dynamic> products = List.from(resultData['products'] ?? []);
    for (var task in _globalQueue) {
      if (task['type'] == 'ADD_PRODUCT') {
        if (!products.any((p) => p['name'] == task['data']['name'])) {
          products.insert(0, {...task['data'], 'is_local': true});
        }
      }
    }
    
    // 4. Application des images locales
    try {
      final localImgs = json.decode(prefs.getString('local_images_map') ?? '{}');
      for(var p in products) {
         if(localImgs.containsKey(p['id'].toString())) {
            p['base_image_path'] = localImgs[p['id'].toString()];
         }
      }
    } catch(e) {}

    resultData['products'] = products;
    return resultData;
  }

  Future<Map<String, dynamic>> getMobileProductCatalog() async {
    return getProductsWithQueue();
  }

  // --- 2. DASHBOARD (CORRIGÉ) ---
  Future<Map<String, dynamic>> fetchDashboardData({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('license_key');
    if (key == null) return {};

    try {
      // Utilise la route /data
      String url = '$_cloudUrl/data?license_key=$key';
      if (forceRefresh) url += '&_t=${DateTime.now().millisecondsSinceEpoch}';
      
      final headers = await _getHeaders();
      final response = await _getClient().get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (_) {}
    return {};
  }

  // --- 3. CLIENTS & FOURNISSEURS (CORRIGÉ) ---
  Future<List<dynamic>> getTiersList(String type, String query) async {
    return getTiersWithQueue(type, query);
  }

  Future<List<dynamic>> getTiersWithQueue(String type, String query) async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('license_key');
    
    List<dynamic> serverList = [];
    try {
      final headers = await _getHeaders();
      // Utilise la route générique /get-data/tiers
      final response = await _getClient().get(
          Uri.parse('$_cloudUrl/get-data/tiers?license_key=$key'),
          headers: headers
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        if (data is List) {
           serverList = data;
        } else if (data is Map) {
           List<dynamic> c = data['clients'] ?? [];
           List<dynamic> s = data['suppliers'] ?? [];
           serverList = [...c, ...s];
        }
      }
    } catch (_) {}

    if (query.isNotEmpty) {
      serverList = serverList.where((t) => t['name'].toString().toLowerCase().contains(query.toLowerCase())).toList();
    }

    final queueType = (type == 'clients' || type == 'client') ? 'ADD_CLIENT' : 'ADD_SUPPLIER';
    final localList = _globalQueue
        .where((task) => task['type'] == queueType)
        .map((task) => task['data'])
        .where((data) => query.isEmpty || (data['name'] ?? '').toString().toLowerCase().contains(query.toLowerCase()))
        .toList();

    return [...localList, ...serverList];
  }

  // --- 4. CHARGES (CORRIGÉ) ---
  Future<List<dynamic>> getChargesWithQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('license_key');
    
    List<dynamic> serverData = [];
    try {
      final headers = await _getHeaders();
      // Utilise /get-data/charges
      final response = await _getClient().get(
          Uri.parse('$_cloudUrl/get-data/charges?license_key=$key'),
          headers: headers
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
         final dynamic data = json.decode(response.body);
         if (data is List) serverData = data;
      }
    } catch (_) {}
    
    List<dynamic> localData = _globalQueue
        .where((e) => e['type'] == 'CHARGE')
        .map((e) => {...e['data'], 'date': e['date'], 'is_pending': true, 'id': e['temp_id']})
        .toList();

    return [...localData, ...serverData];
  }

  // --- 5. VENTES & ACHATS (CORRIGÉ) ---
  // Helper pour récupérer sales_history et purchases_history
  Future<List<dynamic>> _fetchListFromData(String dataType) async {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString('license_key');
      try {
        final headers = await _getHeaders();
        final response = await _getClient().get(
            Uri.parse('$_cloudUrl/get-data/$dataType?license_key=$key'),
            headers: headers
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
           final dynamic data = json.decode(response.body);
           if (data is List) return data;
        }
      } catch (_) {}
      return [];
  }

  Future<List<dynamic>> getSalesList({int limit = 50}) async => _fetchListFromData('sales_history');
  Future<List<dynamic>> getPurchasesList({int limit = 50}) async => _fetchListFromData('purchases_history');
  
  // Détails Vente (Recherche locale dans la liste chargée)
  Future<List<dynamic>> getSaleItems(dynamic saleId) async {
     List<dynamic> sales = await getSalesList();
     var sale = sales.firstWhere((s) => s['id'].toString() == saleId.toString(), orElse: () => null);
     return (sale != null && sale['items'] is List) ? sale['items'] : [];
  }
  
  // Détails Achat
  Future<List<dynamic>> getPurchaseItems(dynamic poId) async {
     List<dynamic> purchases = await getPurchasesList();
     var po = purchases.firstWhere((p) => p['id'].toString() == poId.toString(), orElse: () => null);
     return (po != null && po['items'] is List) ? po['items'] : [];
  }

  Future<List<dynamic>> getSalesByDay(String date) async {
     List<dynamic> all = await getSalesList();
     return all.where((s) => s['date'].toString().startsWith(date)).toList();
  }
  
  Future<List<dynamic>> getPurchasesByDay(String date) async {
     List<dynamic> all = await getPurchasesList();
     return all.where((s) => s['date'].toString().startsWith(date)).toList();
  }

  Future<List<dynamic>> getAlertDetails(String type) async => [];
  Future<Map<String, dynamic>> getTierDetails(String type, dynamic id) async => {};

  // --- HTTP CLIENT & COMMANDES ---
  http.Client _getClient() => http.Client();

  Future<bool> _sendCommandInternal(String actionType, Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('license_key');
    if (key == null) return false;
    
    try {
      final headers = await _getHeaders();
      // Utilise /send-command
      final response = await _getClient().post(
        Uri.parse('$_cloudUrl/send-command'), 
        headers: headers, 
        body: json.encode({"license_key": key, "action_type": actionType, "payload": payload})
      ).timeout(const Duration(seconds: 30));
      return (response.statusCode == 200 || response.statusCode == 201);
    } catch (_) { return false; }
  }

  Future<bool> sendQuickCharge(String label, double amount, String category) async => _sendCommandInternal('CHARGE', {"label": label, "amount": amount, "category": category});
  Future<bool> sendComplexSale(double total, List<dynamic> items, {int? clientId, String? clientName, double? amountPaid, String? paymentType, String? note}) async => _sendCommandInternal('SALE', {"total": total, "items": items, "client_id": clientId, "client_name": clientName, "amount_paid": amountPaid, "payment_type": paymentType, "note": note});
  Future<bool> sendUpdateProduct(Map<String, dynamic> data) async => _sendCommandInternal('UPDATE_PRODUCT', data);
  Future<bool> sendPartnerPayment({required int partnerId, required double amount, required String type, String? note}) async => _sendCommandInternal('PAYMENT', {"partner_id": partnerId, "amount": amount, "type": type, "note": note});
  
  Future<bool> sendAddProduct(String name, double price, double cost, double stock, String barcode, String category, {String? imageData}) async {
    return _sendCommandInternal('ADD_PRODUCT', {"name": name, "price": price, "cost": cost, "stock": stock, "barcode": barcode, "category": category, "image_data": imageData});
  }

  Future<bool> sendCommand(String actionType, Map<String, dynamic> payload) async {
    return _sendCommandInternal(actionType, payload);
  }

  // --- IMPRESSION PDF DISTANTE ---
  Future<void> printLocalTransaction(dynamic id, bool isSale, String format) async {
    if (id.toString().startsWith('TEMP') || id.toString().startsWith('SALE-')) return;
    try {
      String requestId = "REQ-${DateTime.now().millisecondsSinceEpoch}";
      final success = await _sendCommandInternal('GENERATE_PDF', {"sale_id": id, "format": format, "request_id": requestId});
      if (!success) return;

      bool pdfReady = false;
      int retry = 0;
      while (!pdfReady && retry < 20) {
        await Future.delayed(const Duration(seconds: 1));
        
        final headers = await _getHeaders();
        final resp = await _getClient().get(
            Uri.parse('$_cloudUrl/check-pdf/$requestId'),
            headers: headers
        );
        
        if (resp.statusCode == 200) {
          final d = json.decode(resp.body);
          if (d['status'] == 'ready') {
            if (d['url'] != null) {
               // Téléchargement du PDF généré par le serveur
               final urlResp = await http.get(Uri.parse("https://api.infinityapp.site${d['url']}"));
               await Printing.sharePdf(bytes: urlResp.bodyBytes, filename: 'Doc_$id.pdf');
            }
            pdfReady = true;
          }
        }
        retry++;
      }
    } catch (_) {}
  }

  // --- AUTHENTIFICATION ---
  Future<Map<String, dynamic>> verifyCredentials(String licenseKey, String pass) async {
    try {
      final response = await _getClient().get(
        Uri.parse('$_cloudUrl/data?license_key=$licenseKey'),
        headers: {
          "x-pos-user": licenseKey,
          "x-pos-pass": pass,
          "Content-Type": "application/json"
        }
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return {'success': true, 'message': 'Connexion réussie !'};
      if (response.statusCode == 401) return {'success': false, 'message': 'Mot de passe incorrect.'};
      
      return {'success': false, 'message': 'Licence introuvable ou erreur.'};
    } catch (e) { 
      return {'success': false, 'message': 'Erreur réseau'}; 
    }
  }
  
// --- IMAGES (VERSION MOBILE UNIQUEMENT) ---
  Future<bool> updateProductImage(dynamic productId, File imageFile) async {
    try {
       final prefs = await SharedPreferences.getInstance();
       Map<String, dynamic> localImages = {};
       
       // 1. Charger la liste des images locales existantes
       try { 
         localImages = json.decode(prefs.getString('local_images_map') ?? '{}'); 
       } catch(e){}
       
       // 2. Sauvegarder le chemin de la nouvelle image pour ce produit
       localImages[productId.toString()] = imageFile.path;
       
       // 3. Enregistrer dans la mémoire du téléphone
       await prefs.setString('local_images_map', json.encode(localImages));


       _dataUpdateController.add(null);
       
       return true;
    } catch(e) { 
      return false; 
    }
  }

Future<String?> fetchAiProductImage(String query, {String? barcode}) async {
    try {
  
      String q = "$query packaging algerie"; 
      
      print("🔍 Recherche Google pour : $q");


      final uri = Uri.parse("https://www.google.com/search?q=${Uri.encodeComponent(q)}&tbm=isch&tbs=isz:m");

      final headers = {
        "User-Agent": "Mozilla/5.0 (Linux; Android 11; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.105 Mobile Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
      };

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        String html = response.body;

        RegExp exp = RegExp(r'\["(http[^"]+?)",\d+,\d+\]');
        Iterable<Match> matches = exp.allMatches(html);

        for (Match m in matches) {
          String? imgUrl = m.group(1);
          

          if (imgUrl != null && 
              !imgUrl.contains("gstatic") && 
              (imgUrl.contains(".jpg") || imgUrl.contains(".png") || imgUrl.contains(".jpeg"))) {
        
            print("✅ Image Google Trouvée : $imgUrl");
            return imgUrl;
          }
        }
      }
    } catch (e) {
      print("⚠️ Erreur Google Scraping: $e");
    }

    // Fallback : Avatar si Google échoue vraiment
    String cleanName = query.split(' ').take(2).join('+');
    return "https://ui-avatars.com/api/?name=$cleanName&background=random&size=512&color=fff&bold=true&font-size=0.4";
  }
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_queueKey); 
    _globalQueue = [];
  }
}