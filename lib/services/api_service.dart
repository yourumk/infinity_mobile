import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart'; 
import 'package:sqflite/sqflite.dart'; // 🚀 SQLITE
import 'package:path/path.dart'; // 🚀 SQLITE

import 'package:printing/printing.dart'; 
import 'package:pdf/pdf.dart'; 

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String _baseUrl = "https://infi-nasro2.online/api";
  static const String _queueKey = "offline_command_queue_v7";
  static const String _cacheKeyCatalog = "offline_catalog_cache";
  static const String _deltasKey = "pending_deltas_v1";

  // 🟢 DIAGNOSTIC
  String? _lastError;
  String? get lastError => _lastError;
  void clearError() => _lastError = null; 

  String _humanizeError(dynamic error) {
    if (error is int) {
      if (error == 500 || error == 502 || error == 503 || error == 504) {
        return "⚙️ Le système est actuellement en maintenance ou surchargé. Réessayez dans quelques minutes.";
      }
      return "🚧 La connexion avec le serveur a été interrompue (Code: $error). Veuillez réessayer.";
    }
    final errStr = error.toString().toLowerCase();
    if (error is SocketException || errStr.contains('failed host lookup') || errStr.contains('connection refused') || errStr.contains('network is unreachable')) {
      return "📡 Oups ! Impossible de se connecter à Internet. Vérifiez votre Wi-Fi ou vos données mobiles.";
    }
    if (error is TimeoutException || errStr.contains('timeout')) {
      return "⏳ Le serveur met trop de temps à répondre. La connexion est peut-être faible, réessayez.";
    }
    if (error is FormatException || errStr.contains('format') || errStr.contains('json')) {
      return "🛠️ Un petit problème technique est survenu lors de la lecture des données. Nos équipes sont informées.";
    }
    if (error is http.ClientException || errStr.contains('clientexception') || errStr.contains('httpexception')) {
      return "🚧 La connexion avec le serveur a été interrompue. Veuillez réessayer.";
    }
    return "⚠️ Une erreur inattendue s'est produite. Si cela persiste, relancez l'application.";
  }

  // 🚀 MOTEUR DE BASE DE DONNÉES LOCALE (ZÉRO CRASH RAM)
  Database? _db;
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    String dbPath = join(await getDatabasesPath(), 'infinity_pos_mobile.db');
    return await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        // Table pour la file d'attente hors-ligne
        await db.execute('CREATE TABLE queue (id TEXT PRIMARY KEY, action TEXT, payload TEXT, retries INTEGER, timestamp TEXT)');
        // Table pour le catalogue complet
        await db.execute('CREATE TABLE cache (key TEXT PRIMARY KEY, data TEXT)');
        // Table pour les calculs de stock
        await db.execute('CREATE TABLE deltas (key TEXT PRIMARY KEY, data TEXT)');
        // 🚀 V2 : Panier persisté (survit au kill de l'app)
        await db.execute('CREATE TABLE cart_items (id INTEGER PRIMARY KEY AUTOINCREMENT, cart_type TEXT NOT NULL, data TEXT NOT NULL)');
        // 🚀 V2 : Cache tiers (clients/fournisseurs/charges) pour l'offline
        await db.execute('CREATE TABLE tiers_cache (key TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at TEXT NOT NULL)');
        // 🚀 V3 : Tournée active en cache offline (survit au mode avion)
        await db.execute('CREATE TABLE active_tour (id INTEGER PRIMARY KEY, van_id INTEGER, status TEXT, data TEXT)');
        // 🚀 V3 : Transferts en attente de réseau
        await db.execute('CREATE TABLE offline_transfers (id TEXT PRIMARY KEY, payload TEXT)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('CREATE TABLE IF NOT EXISTS cart_items (id INTEGER PRIMARY KEY AUTOINCREMENT, cart_type TEXT NOT NULL, data TEXT NOT NULL)');
          await db.execute('CREATE TABLE IF NOT EXISTS tiers_cache (key TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at TEXT NOT NULL)');
        }
        if (oldVersion < 3) {
          // 🚀 V3 : Tournée active & transferts offline
          await db.execute('CREATE TABLE IF NOT EXISTS active_tour (id INTEGER PRIMARY KEY, van_id INTEGER, status TEXT, data TEXT)');
          await db.execute('CREATE TABLE IF NOT EXISTS offline_transfers (id TEXT PRIMARY KEY, payload TEXT)');
        }
      }
    );
  }

  // =============================================================
  // 🛒 PERSISTENCE PANIER (Zéro perte si l'app est tuée)
  // =============================================================

  /// Sauvegarde le panier complet dans SQLite
  Future<void> saveCart(String cartType, List<Map<String, dynamic>> items) async {
    try {
      final db = await database;
      await db.delete('cart_items', where: 'cart_type = ?', whereArgs: [cartType]);
      if (items.isNotEmpty) {
        await db.insert('cart_items', {
          'cart_type': cartType,
          'data': json.encode(items),
        });
      }
    } catch (e) {
      debugPrint('❌ Erreur saveCart: $e');
    }
  }

  /// Restaure le panier depuis SQLite au démarrage
  Future<List<Map<String, dynamic>>> loadCart(String cartType) async {
    try {
      final db = await database;
      final rows = await db.query('cart_items', where: 'cart_type = ?', whereArgs: [cartType]);
      if (rows.isNotEmpty) {
        final List<dynamic> decoded = json.decode(rows.first['data'] as String);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('❌ Erreur loadCart: $e');
    }
    return [];
  }

  /// Vide le panier après validation de la vente/achat
  Future<void> clearCart(String cartType) async {
    try {
      final db = await database;
      await db.delete('cart_items', where: 'cart_type = ?', whereArgs: [cartType]);
    } catch (e) {
      debugPrint('❌ Erreur clearCart: $e');
    }
  }

  // =============================================================
  // 📦 CACHE TIERS OFFLINE (Clients/Fournisseurs/Charges)
  // =============================================================

  /// Sauvegarde une liste de tiers dans SQLite
  Future<void> _saveTiersCache(String key, List<dynamic> data) async {
    try {
      final db = await database;
      await db.insert('tiers_cache', {
        'key': key,
        'data': json.encode(data),
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('❌ Erreur _saveTiersCache: $e');
    }
  }

  /// Charge une liste de tiers depuis SQLite (fallback offline)
  Future<List<dynamic>> _loadTiersCache(String key) async {
    try {
      final db = await database;
      final rows = await db.query('tiers_cache', where: 'key = ?', whereArgs: [key]);
      if (rows.isNotEmpty) {
        return json.decode(rows.first['data'] as String);
      }
    } catch (e) {
      debugPrint('❌ Erreur _loadTiersCache: $e');
    }
    return [];
  }
  
  static String? getCleanImageUrl(dynamic rawPath) {
    if (rawPath == null || rawPath.toString().trim().isEmpty || rawPath.toString() == 'null') return null;
    String path = rawPath.toString();
    
    if (path.startsWith('http')) return path;
    if (path.startsWith('data:')) return null; 
    
    String fileName = path.replaceAll('\\', '/').split('/').last;
    return 'https://infi-nasro2.online/api/mobile_images/$fileName';
  }

  List<Map<String, dynamic>> _commandQueue = [];
  List<Map<String, dynamic>> get currentQueue => List.unmodifiable(_commandQueue);
  
  void _notifyDataUpdated() {
    _dataUpdateController.add(null);
  }
  
  Future<void> syncQueueNow() async {
    if (_commandQueue.isEmpty) return;
    print("🔄 Synchronisation forcée de ${_commandQueue.length} éléments...");
    await _processQueue(); 
    _notifyDataUpdated();
  }

  Map<String, Map<String, dynamic>> _pendingDeltas = {}; 

  DateTime _lastCommandTime = DateTime.fromMillisecondsSinceEpoch(0);
  List<dynamic> _cachedClients = [];
  List<dynamic> _cachedSuppliers = [];
  List<dynamic> _cachedCharges = [];
  Timer? _syncTimer;
  int _syncCounter = 0; 
  int _currentBackoff = 3; // 🚀 Temps d'attente de base (3s)
  final int _maxBackoff = 60; // 🚀 Temps d'attente maximum (60s)

  final StreamController<void> _dataUpdateController = StreamController<void>.broadcast();
  Stream<void> get onDataUpdated => _dataUpdateController.stream;

  // 🛠️ FIX SELECTOR & STATE : Le Moteur de Réactivité (Event Bus)
  final StreamController<int?> _warehouseChangeController = StreamController<int?>.broadcast();
  Stream<int?> get onWarehouseChanged => _warehouseChangeController.stream;

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    String licenseKey = prefs.getString('license_key') ?? "";
    
    // 🚀 FIX CRITIQUE MOBILE : Utilisation de get() au lieu de getString() 
    // car les IDs sont souvent sauvegardés en 'int' (entiers) et ça fait crasher Flutter !
    String userRole = prefs.getString('user_role') ?? "";
    String employeeId = prefs.get('employee_id')?.toString() ?? "";
    String assignedWarehouseId = prefs.get('assigned_warehouse_id')?.toString() ?? "";
    String registerId = prefs.get('assigned_register_id')?.toString() ?? "";
    String mobileUserId = prefs.get('mobile_user_id')?.toString() ?? "";

    Map<String, String> headers = {
      "Content-Type": "application/json",
      "x-license-key": licenseKey,
    };

    // On injecte les identifiants pour que le serveur sache qui demande le stock
    if (userRole.isNotEmpty) headers["x-user-role"] = userRole;
    if (employeeId.isNotEmpty && employeeId != "null") headers["x-employee-id"] = employeeId;
    
    // 🛠️ FIX MULTI-DEPOT MOBILE : Logique d'injection warehouse
    // Priorité 1 : assigned_warehouse_id (forcé par le POS, accès restreint)
    // Priorité 2 : selected_warehouse_id (choisi manuellement par l'admin via l'app)
    bool globalWh = prefs.getBool('global_warehouse') ?? false;
    bool globalReg = prefs.getBool('global_register') ?? false;

    if (!globalWh && assignedWarehouseId.isNotEmpty && assignedWarehouseId != "null") {
      // Accès restreint : on envoie le dépôt assigné
      headers["x-warehouse-id"] = assignedWarehouseId;
    } else if (globalWh) {
      // Accès global : on envoie le dépôt sélectionné manuellement (si défini)
      String selectedWh = prefs.get('selected_warehouse_id')?.toString() ?? "";
      if (selectedWh.isNotEmpty && selectedWh != "null") {
        headers["x-warehouse-id"] = selectedWh;
      }
      // Si selectedWh est vide → aucun header envoyé → vue globale (tous les dépôts)
    }

    if (!globalReg && registerId.isNotEmpty && registerId != "null") headers["x-register-id"] = registerId;
    
    if (mobileUserId.isNotEmpty && mobileUserId != "null") headers["x-mobile-user-id"] = mobileUserId;

    return headers;
  }

  // 🛠️ FIX MULTI-DEPOT MOBILE : Méthode unifiée pour changer de dépôt
  /// [warehouseId] = null pour revenir à la vue globale (tous les dépôts)
  Future<void> switchWarehouse(int? warehouseId) async {
    final prefs = await SharedPreferences.getInstance();
    if (warehouseId != null) {
      await prefs.setInt('selected_warehouse_id', warehouseId);
    } else {
      await prefs.remove('selected_warehouse_id');
    }
    // Purge le cache pour forcer le rechargement des données du nouveau dépôt
    await clearCache();
    // Notification aux listeners (pages actives)
    _dataUpdateController.add(null);
    // 🛠️ FIX SELECTOR & STATE : Diffuser l'événement de changement
    _warehouseChangeController.add(warehouseId);
    debugPrint('🏢 [SWITCH] Dépôt changé → ${warehouseId ?? "Vue Globale"}');
  }

  Future<void> syncCompanySettings() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/mobile/settings'),
        headers: await _getHeaders()
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final prefs = await SharedPreferences.getInstance();
        if (data['company'] != null) {
          await prefs.setString('company_info_cache', json.encode(data['company']));
        }
        if (data['posOptions'] != null) {
          await prefs.setString('pos_options_cache', json.encode(data['posOptions']));
        }
        // 🖨️ Configuration Ticket Thermique Mobile
        if (data['thermalConfig'] != null) {
          await prefs.setString('thermal_config_cache', json.encode(data['thermalConfig']));
        }
        // 🧑‍💼 Vendeur connecté
        if (data['vendor'] != null) {
          await prefs.setString('vendor_info_cache', json.encode(data['vendor']));
        }
        // 🖼️ Cache du logo localement (URL pour téléchargement ultérieur)
        final logoUrl = data['company']?['logo_url']?.toString();
        if (logoUrl != null && logoUrl.isNotEmpty) {
          final currentLogoUrl = prefs.getString('company_logo_url');
          if (currentLogoUrl != logoUrl) {
            await prefs.setString('company_logo_url', logoUrl);
            // Déclencher le téléchargement du logo en arrière-plan
            _downloadAndCacheLogo(logoUrl);
          }
        }
        final signatureBase64 = data['company']?['signature_base64']?.toString();
        if (signatureBase64 != null && signatureBase64.isNotEmpty) {
           await prefs.setString('company_signature_b64', signatureBase64);
        }
      }
    } catch (e) {
      debugPrint("Erreur de synchronisation des paramètres: $e");
    }
  }

  /// 🖼️ Télécharge le logo et le sauvegarde en cache local
  Future<void> _downloadAndCacheLogo(String logoUrl) async {
    try {
      final response = await http.get(Uri.parse(logoUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        final base64Logo = base64Encode(response.bodyBytes);
        await prefs.setString('company_logo_cached_b64', base64Logo);
        debugPrint('✅ [LOGO] Logo téléchargé et mis en cache (${response.bodyBytes.length} bytes)');
      }
    } catch (e) {
      debugPrint('⚠️ [LOGO] Échec du téléchargement du logo: $e');
    }
  }

  // =========================================================
  // 🏢 MODIFIER INFOS ENTREPRISE DEPUIS LE MOBILE
  // =========================================================
  Future<bool> updateCompanyInfo(Map<String, dynamic> fields) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/mobile/company'),
        headers: await _getHeaders(),
        body: json.encode(fields),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Mettre à jour le cache local immédiatement
        final prefs = await SharedPreferences.getInstance();
        Map<String, dynamic> cached = {};
        try {
          if (prefs.containsKey('company_info_cache')) {
            cached = json.decode(prefs.getString('company_info_cache')!);
          }
        } catch (_) {}
        cached.addAll(fields);
        await prefs.setString('company_info_cache', json.encode(cached));
        debugPrint('✅ [COMPANY] Infos entreprise mises à jour');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [COMPANY] Erreur mise à jour: $e');
      return false;
    }
  }

  // =========================================================
  // 🖼️ UPLOAD LOGO ENTREPRISE DEPUIS LE MOBILE
  // =========================================================
  Future<String?> uploadCompanyLogo(String base64Data) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/mobile/upload-logo'),
        headers: await _getHeaders(),
        body: json.encode({'logo_base64': base64Data}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final logoUrl = data['logo_url']?.toString();
        if (logoUrl != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('company_logo_url', logoUrl);
          await prefs.setString('company_logo_cached_b64', base64Data.replaceAll(RegExp(r'^data:image/\w+;base64,'), ''));
          // Mettre à jour aussi le company_info_cache
          Map<String, dynamic> cached = {};
          try {
            if (prefs.containsKey('company_info_cache')) {
              cached = json.decode(prefs.getString('company_info_cache')!);
            }
          } catch (_) {}
          cached['logo_url'] = logoUrl;
          await prefs.setString('company_info_cache', json.encode(cached));
        }
        debugPrint('✅ [LOGO] Logo uploadé avec succès: $logoUrl');
        return logoUrl;
      }
      return null;
    } catch (e) {
      debugPrint('❌ [LOGO] Erreur upload: $e');
      return null;
    }
  }

  // =========================================================
  // 🖨️ SAUVEGARDER CONFIGURATION THERMIQUE MOBILE (LOCAL)
  // =========================================================
  Future<void> saveThermalConfig(Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('thermal_config_cache', json.encode(config));
  }

  Future<Map<String, dynamic>> getThermalConfig() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (prefs.containsKey('thermal_config_cache')) {
        return json.decode(prefs.getString('thermal_config_cache')!);
      }
    } catch (_) {}
    // Config par défaut
    return {
      'show_logo': true,
      'show_barcode': false,
      'footer_msg': 'Merci de votre visite !',
      'columns': {'qty': true, 'price': true, 'total': true, 'ref': false, 'tva': false},
      'fonts': {'header': 16, 'body': 12, 'totals': 14},
      'blocs_company': {'name': true, 'activity': true, 'address': true, 'phone': true, 'rc': true, 'nif': true, 'nis': true, 'art': true},
      'blocs_client': {'name': true, 'address': false, 'phone': false, 'nif': false, 'rc': false},
    };
  }

  Future<Map<String, dynamic>> getProductsWithQueue() async {
    final result = await getMobileProductCatalog();

    // 🛠️ FIX CHANTIER 2 : Si chauffeur hors-ligne, filtrer les produits
    // selon le stock réel du fourgon (table active_tour en SQLite)
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? '';
      if (role == 'chauffeur') {
        final db = await database;
        final rows = await db.query('active_tour', limit: 1);
        if (rows.isNotEmpty) {
          final tourData = jsonDecode(rows.first['data'] as String);
          final stockItems = (tourData['stock_items'] as List<dynamic>?) ?? [];
          if (stockItems.isNotEmpty) {
            // Construire un index rapide : product_id → stock dans fourgon
            final Map<String, double> vanStock = {};
            for (final item in stockItems) {
              final pid = item['product_id']?.toString() ?? '';
              if (pid.isNotEmpty) {
                vanStock[pid] = double.tryParse(item['stock']?.toString() ?? '0') ?? 0.0;
              }
            }
            // Ne garder que les produits présents dans le fourgon, avec leur stock réel
            final filtered = (result['products'] as List<dynamic>).where((p) {
              final pid = p['id']?.toString() ?? '';
              if (vanStock.containsKey(pid)) {
                p['stock'] = vanStock[pid]; // Overwrite avec le stock du fourgon
                return true;
              }
              return false;
            }).toList();
            result['products'] = filtered;
            debugPrint("🚛 [Offline] Catalogue filtré: ${filtered.length} produits du fourgon");
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ getProductsWithQueue filtrage chauffeur: $e");
    }

    return result;
  }

  // 🚀 LECTURE RAPIDE DEPUIS SQLITE
  Future<Map<String, dynamic>> getMobileProductCatalog() async {
    final db = await database;
    Map<String, dynamic> result = {'products': [], 'categories': [], 'sub_categories': []};

    Future<Map<String, dynamic>?> readCache() async {
      final res = await db.query('cache', where: 'key = ?', whereArgs: [_cacheKeyCatalog]);
      if (res.isNotEmpty) return json.decode(res.first['data'] as String);
      return null;
    }

    if (DateTime.now().difference(_lastCommandTime).inSeconds < 2) {
        final cached = await readCache();
        if (cached != null) return cached;
    }

    try {
        final headers = await _getHeaders();
        debugPrint("📡 [API] GET /products (licence: ${headers['x-license-key']?.substring(0, (headers['x-license-key']?.length ?? 0).clamp(0, 8))}...)");
        final response = await http.get(
          Uri.parse('$_baseUrl/products'), 
          headers: headers
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
           final List<dynamic> rawList = json.decode(response.body);
           await _loadDeltas();

           List<dynamic> cleanList = rawList.map((p) {
             String id = (p['id'] ?? p['local_id']).toString();
             double cloudStock = double.tryParse((p['stock'] ?? p['base_stock'])?.toString() ?? '0') ?? 0.0;
             double vatPercent = double.tryParse((p['vat_percent'] ?? p['tva'] ?? p['vat'])?.toString() ?? '0') ?? 0.0;

             double rawPrice = double.tryParse(p['price']?.toString() ?? '0') ?? 0.0;
             double rawSemi = double.tryParse(p['price_semi']?.toString() ?? '0') ?? 0.0;
             double rawWhol = double.tryParse(p['price_whol']?.toString() ?? '0') ?? 0.0;
             
             double htPrice = vatPercent > 0 ? (rawPrice / (1 + (vatPercent / 100))) : rawPrice;
             double htSemi = vatPercent > 0 ? (rawSemi / (1 + (vatPercent / 100))) : rawSemi;
             double htWhol = vatPercent > 0 ? (rawWhol / (1 + (vatPercent / 100))) : rawWhol;
             double htCost = double.tryParse(p['cost']?.toString() ?? '0') ?? 0.0;

             if (_pendingDeltas.containsKey(id)) {
                 double expectedCloudStock = double.tryParse(_pendingDeltas[id]!['expected_cloud_stock'].toString()) ?? 0.0;
                 double localDelta = double.tryParse(_pendingDeltas[id]!['delta'].toString()) ?? 0.0;

                 if ((cloudStock - expectedCloudStock).abs() > 0.001) {
                     _pendingDeltas.remove(id); 
                 } else {
                     cloudStock = cloudStock + localDelta; 
                 }
             }

             List<dynamic> cleanVariants = [];
             if (p['variants'] != null && p['variants'] is List) {
                 cleanVariants = (p['variants'] as List).map((v) {
                     double rawV = double.tryParse(v['price']?.toString() ?? '0') ?? 0.0;
                     double vHt = vatPercent > 0 ? (rawV / (1 + (vatPercent / 100))) : rawV;
                     double cHt = double.tryParse(v['cost']?.toString() ?? '0') ?? 0.0;
                     return { ...v, 'price': vHt, 'cost': cHt };
                 }).toList();
             }
             return {
               'id': id,
               'name': p['name'] ?? 'Sans Nom',
               'ref': p['ref'] ?? p['reference'] ?? '',
               'barcode': p['barcode']?.toString() ?? p['code_barre']?.toString() ?? p['bar_code']?.toString() ?? '',
               'price': htPrice,
               'cost': htCost,   
               'vat_percent': vatPercent, 
               'price_semi': htSemi,
               'price_whol': htWhol,
               'stock': cloudStock, 
               'min_stock': double.tryParse((p['min_stock'] ?? p['min_stock_alert'])?.toString() ?? '5') ?? 5.0,
               'packing': double.tryParse((p['packing'] ?? p['unit_per_package'])?.toString() ?? '1') ?? 1.0,
               'unit': p['unit'] ?? p['stock_unit'] ?? 'U',
               'category': p['category'] ?? p['family'] ?? 'Divers',
               'sub_category': p['sub_category'] ?? p['sub_family'] ?? '',
               'base_image_path': p['base_image_path'],
               'variants': cleanVariants,
               'locations': p['locations_list'] ?? p['locations'] ?? [],
               'barcodes': p['barcodes_list'] ?? p['barcodes'] ?? [] 
             };
           }).toList();

           await _saveDeltas(); 

           result['products'] = cleanList;

           Set<String> cats = {'Tout'};
           Set<String> subs = {'Tout'};
           for(var p in cleanList) {
             if(p['category']!=null && p['category'].toString().isNotEmpty) cats.add(p['category'].toString());
             if(p['sub_category']!=null && p['sub_category'].toString().isNotEmpty) subs.add(p['sub_category'].toString());
           }
           result['categories'] = cats.toList();
           result['sub_categories'] = subs.toList();
           
           // 🚀 Écriture dans SQLite
           await db.insert('cache', {'key': _cacheKeyCatalog, 'data': json.encode(result)}, conflictAlgorithm: ConflictAlgorithm.replace);

        } else {
           _lastError = "Erreur serveur (${response.statusCode}).";
           final cached = await readCache();
           if (cached != null) return cached;
        }
    } catch (e) { 
        _lastError = "Connexion impossible : $e";
        final cached = await readCache();
        if (cached != null) return cached;
    }

    return result;
  }

  Future<List<dynamic>> getProducts() async {
      final res = await getMobileProductCatalog();
      return res['products'] ?? [];
  }

  Future<void> startAutoSync() async {
    await _loadQueue();
    await _loadDeltas();
    if (_syncTimer != null && _syncTimer!.isActive) return;

    _scheduleNextSync();
  }

  // 🚀 MOTEUR EXPONENTIAL BACKOFF
  void _scheduleNextSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(Duration(seconds: _currentBackoff), () async {
      _syncCounter++;
      bool hasInternet = await _checkConnectivity();
      
      if (hasInternet) {
        if (_commandQueue.isNotEmpty) {
          bool networkOk = await _processQueue();
          if (networkOk) {
            _currentBackoff = 3; // Réseau stable = on repart à 3 secondes
          } else {
            // Serveur instable ou micro-coupure : On double le temps d'attente
            _currentBackoff = min(_currentBackoff * 2, _maxBackoff);
            debugPrint("⚠️ Backoff Réseau : Prochain essai dans $_currentBackoff s.");
          }
        } else {
          _currentBackoff = 3; 
          if (_syncCounter % 3 == 0) {
            await getMobileProductCatalog();
            _dataUpdateController.add(null); 
          }
        }
      } else {
        // Pas de 4G : On espace les tentatives pour sauver la batterie !
        _currentBackoff = min(_currentBackoff * 2, _maxBackoff);
      }
      
      _scheduleNextSync(); // On relance la boucle
    });
  }

  Future<bool> _checkConnectivity() async {
    try {
      final result = await http.head(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 2));
      return result.statusCode == 200;
    } catch (_) { return false; }
  }

  // 🚀 SAUVEGARDE SQLITE (Zéro Crash Mémoire)
  Future<void> _loadQueue() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('queue', orderBy: 'timestamp ASC');
    _commandQueue = maps.map((e) => {
      'id': e['id'],
      'action': e['action'],
      'payload': json.decode(e['payload'] as String),
      'retries': e['retries'],
      'timestamp': e['timestamp'],
    }).toList();
  }

  Future<void> _saveQueue() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('queue');
      for (var task in _commandQueue) {
        await txn.insert('queue', {
          'id': task['id'],
          'action': task['action'],
          'payload': json.encode(task['payload']),
          'retries': task['retries'] ?? 0,
          'timestamp': task['timestamp'],
        });
      }
    });
  }

  Future<void> _loadDeltas() async {
    final db = await database;
    final res = await db.query('deltas', where: 'key = ?', whereArgs: [_deltasKey]);
    if (res.isNotEmpty) {
      try {
        Map<String, dynamic> decoded = json.decode(res.first['data'] as String);
        _pendingDeltas = decoded.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)));
      } catch (e) {}
    }
  }

  Future<void> _saveDeltas() async {
    final db = await database;
    await db.insert('deltas', {'key': _deltasKey, 'data': json.encode(_pendingDeltas)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 🛠️ FIX CRITIQUE : Mettre à jour le stock du fourgon (active_tour) après chaque vente/retour
  Future<void> _updateActiveTourStock(List<dynamic> saleItems, {bool isSale = true, bool isReturn = false}) async {
    try {
      final db = await database;
      final rows = await db.query('active_tour', limit: 1);
      if (rows.isEmpty) return;

      final tourData = jsonDecode(rows.first['data'] as String);
      final stockItems = (tourData['stock_items'] as List<dynamic>?) ?? [];
      if (stockItems.isEmpty) return;

      for (var saleItem in saleItems) {
        final pid = (saleItem['product_id'] ?? saleItem['id'])?.toString() ?? '';
        if (pid.isEmpty) continue;
        final qty = double.tryParse((saleItem['quantity'] ?? saleItem['qty'] ?? 1).toString()) ?? 0.0;
        // Vente = stock descend, Retour = stock remonte
        final delta = (isSale && !isReturn) ? -qty : qty;

        final idx = stockItems.indexWhere((s) => s['product_id']?.toString() == pid);
        if (idx >= 0) {
          double currentStock = double.tryParse(stockItems[idx]['stock']?.toString() ?? '0') ?? 0.0;
          stockItems[idx]['stock'] = (currentStock + delta).clamp(0, double.infinity);
        }
      }

      tourData['stock_items'] = stockItems;
      await db.update('active_tour', {'data': jsonEncode(tourData)}, where: 'id = ?', whereArgs: [rows.first['id']]);
      debugPrint("🚛 [FIX] Stock fourgon mis à jour dans active_tour");
    } catch (e) {
      debugPrint("⚠️ _updateActiveTourStock: $e");
    }
  }

  void _addToQueue(String action, Map<String, dynamic> payload) {
    if (!payload.containsKey('id') && !payload.containsKey('temp_id')) {
       payload['temp_id'] = "CMD-${DateTime.now().millisecondsSinceEpoch}";
    }
    final task = {
      'id': "TASK-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999)}",
      'action': action,
      'payload': payload,
      'timestamp': DateTime.now().toIso8601String()
    };
    _commandQueue.add(task);
    _saveQueue();
    _dataUpdateController.add(null);
    _processQueue(); 
  }

  bool _isProcessingQueue = false;

  // 🚀 Renvoie un Booléen pour alimenter l'Exponential Backoff
  Future<bool> _processQueue() async {
    if (_isProcessingQueue) return true;
    if (_commandQueue.isEmpty) return true;
    
    _isProcessingQueue = true;
    bool networkOk = true; 

    try {
      List<Map<String, dynamic>> snapshot = List.from(_commandQueue);
      List<String> processedIds = [];
for (var task in snapshot) {
        task['retries'] = (task['retries'] ?? 0) + 1;
        
        bool success = await _sendCommandInternal(task['action'], task['payload'], taskId: task['id']);
        
        if (success) {
            processedIds.add(task['id']);
        } else {
            // 🟢 SÉCURITÉ ABSOLUE : On ne supprime JAMAIS une vente !
            // On attend que le réseau ou le serveur revienne, peu importe le nombre d'essais.
            networkOk = false; 
            if (task['retries'] > 10) {
               debugPrint("⚠️ Vente en attente de réseau (Tentative ${task['retries']})...");
            }
            break; 
        }
      }

      if (processedIds.isNotEmpty) {
        _commandQueue.removeWhere((t) => processedIds.contains(t['id']));
        await _saveQueue();
        
        _cachedClients.clear();
        _cachedSuppliers.clear();
        
        await getMobileProductCatalog(); 
        _dataUpdateController.add(null); 
      }
    } finally {
      _isProcessingQueue = false;
    }
    return networkOk;
  }

// 🚀 FIX IDEMPOTENCE : On passe l'ID de la tâche (taskId) pour bloquer les doubles ventes
  Future<bool> _sendCommandInternal(String action, Map<String, dynamic> payload, {String? taskId}) async {
    try {
      String endpoint = '/command';
      Map<String, dynamic> body = { "action": action, "payload": payload, "task_id": taskId };

      switch(action) {
        case 'ADD_CHARGE': 
          endpoint = '/mobile/charges/add'; 
          body = payload;
          break;
        case 'PAYMENT': 
          endpoint = '/mobile/payments/add'; 
          body = payload;
          break;
        case 'DECLARE_LOSS': 
          endpoint = '/mobile/stock/loss'; 
          body = payload;
          break;
        case 'OPEN_SESSION': 
          endpoint = '/mobile/cash/open'; 
          body = payload;
          break;
        case 'CLOSE_SESSION': 
          endpoint = '/mobile/cash/close'; 
          body = payload;
          break;
        case 'CREATE_TRANSFER': 
          endpoint = '/mobile/transfers/create'; 
          body = payload;
          break;
        case 'RECEIVE_TRANSFER': 
          endpoint = '/mobile/transfers/receive'; 
          body = payload;
          break;
        case 'START_TOUR': 
          endpoint = '/mobile/tours/start'; 
          body = payload;
          break;
        case 'CLOSE_TOUR': 
          endpoint = '/mobile/tours/close'; 
          body = payload;
          break;
        case 'START_PENDING_TOUR': 
          endpoint = '/mobile/tours/start-pending'; 
          body = payload;
          break;
        case 'CHECK_IN_TOUR': 
          endpoint = '/mobile/tours/stops/${payload['stop_id']}/check-in'; 
          body = payload;
          break;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: await _getHeaders(),
        body: json.encode(body)
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 201) {
        _lastError = _humanizeError(response.statusCode);
      }
      return (response.statusCode == 200 || response.statusCode == 201);
    } catch (e) {
      debugPrint("❌ [API] _sendCommandInternal EXCEPTION: $e");
      _lastError = _humanizeError(e);
      return false; 
    }
  }

  // 🚀 MISE A JOUR INSTANTANÉE SQLite
  Future<void> _updateLocalCacheOptimistically({
    Map<String, dynamic>? updatedProduct, 
    bool isSale = false, 
    List<dynamic>? saleItems,
    bool isPurchase = false,        
    List<dynamic>? purchaseItems    
  }) async {
    try {
      await _loadDeltas();
      final db = await database;
      final res = await db.query('cache', where: 'key = ?', whereArgs: [_cacheKeyCatalog]);
      if (res.isEmpty) return;
      
      Map<String, dynamic> cache = json.decode(res.first['data'] as String);
      List<dynamic> products = cache['products'] ?? [];
      List<dynamic>? itemsToProcess = isSale ? saleItems : (isPurchase ? purchaseItems : null);

      if (itemsToProcess != null) {
        for (var item in itemsToProcess) {
          String targetId = item['product_id']?.toString() ?? item['id']?.toString() ?? "";
          int idx = products.indexWhere((p) => p['id'].toString() == targetId);
          if (idx >= 0) {
            double currentStock = double.tryParse(products[idx]['stock'].toString()) ?? 0.0;
            double qty = double.tryParse((item['quantity'] ?? item['qty'] ?? 1).toString()) ?? 0.0;
            double delta = isSale ? -qty : qty; 
            if (!_pendingDeltas.containsKey(targetId)) {
                _pendingDeltas[targetId] = {
                    'expected_cloud_stock': currentStock, 
                    'delta': 0.0
                };
            }
            _pendingDeltas[targetId]!['delta'] = (_pendingDeltas[targetId]!['delta'] as double) + delta;
            products[idx]['stock'] = currentStock + delta; 
          }
        }
        await _saveDeltas();
      } else if (updatedProduct != null) {
        int idx = products.indexWhere((p) => p['id'].toString() == updatedProduct['id'].toString());
        if (idx >= 0) {
          products[idx] = {...products[idx], ...updatedProduct}; 
        } else {
          products.insert(0, updatedProduct); 
        }
      }

      cache['products'] = products;
      await db.insert('cache', {'key': _cacheKeyCatalog, 'data': json.encode(cache)}, conflictAlgorithm: ConflictAlgorithm.replace);
      _dataUpdateController.add(null); 
    } catch (e) {
      debugPrint("Erreur Cache Instantané SQLite: $e");
    }
  }


  Future<void> saveProduct({
    String? id, required String name, required double price, required double cost,
    double stock = 0, String? barcode, String? reference, String category = "Divers",
    String subCategory = "", double minStock = 5, double packing = 1,
    double priceSemi = 0, double priceWhol = 0, String unit = "U",
    double vatPercent = 19.0
  }) async {
    String finalId = id ?? "TEMP-${DateTime.now().millisecondsSinceEpoch}";
      
      final payload = {
          "id": finalId, 
          "name": name, 
          "price": price, 
          "base_price_retail_ttc": price, 
          "cost": cost, 
          "base_purchase_price": cost,    
          "stock": stock, 
          "base_stock": stock,
          "barcode": barcode, 
          "ref": reference, 
          "base_reference": reference, 
          "category": category, 
          "family": category, 
          "sub_category": subCategory, 
          "sub_family": subCategory, 
          "min_stock": minStock, 
          "min_stock_alert": minStock, 
          "packing": packing, 
          "unit_per_package": packing,    
          "price_semi": priceSemi, 
          "price_semi_wholesale_ttc": priceSemi,
          "price_whol": priceWhol, 
          "price_wholesale_ttc": priceWhol,
          "unit": unit, 
          "stock_unit": unit,
          "vat_percent": vatPercent, 
          "is_vat_applicable": vatPercent > 0 ? 1 : 0
      };

      await _updateLocalCacheOptimistically(updatedProduct: payload);
      _lastCommandTime = DateTime.now(); 
      final action = (!finalId.startsWith("TEMP")) ? 'UPDATE_PRODUCT' : 'ADD_PRODUCT';
      _addToQueue(action, payload);
  }

   Future<void> createSale({required double total, required List<Map<String, dynamic>> items, int? clientId, String? clientName, double amountPaid = 0, String paymentType = "cash", String note = "", double tva = 0, double timbre = 0, double discount = 0, double ht = 0, bool isReturn = false, int? saleId}) async {
    final prefs = await SharedPreferences.getInstance();
    bool enableTva = prefs.getBool('enable_tva') ?? false;
    
    // Récupération des IDs logistiques du mobile
    int? assignedRegId = prefs.getInt('assigned_register_id');
    int? assignedWhId = prefs.getInt('assigned_warehouse_id');
    int? empId = prefs.getInt('employee_id');
    int? posUserId = prefs.getInt('pos_user_id');
    int? mobileUserId = int.tryParse(prefs.get('mobile_user_id')?.toString() ?? '');
    String userRole = prefs.getString('user_role') ?? '';

    // 🚛 FIX CHANTIER 1 : Récupérer le van_tour_id actif pour les chauffeurs
    int? vanTourId = prefs.getInt('active_van_tour_id');
    int? vanId = prefs.getInt('active_van_id');

    // 🚛 FIX CHANTIER 1 : Si chauffeur, le warehouse_id de la vente = le van_id du fourgon
    int? effectiveWhId = (userRole == 'chauffeur' && vanId != null) ? vanId : assignedWhId;

    final cleanItems = items.map((e) {
      double vRate = enableTva ? (double.tryParse(e['vat_percent'].toString()) ?? 0.0) : 0.0;
      double pHT = double.tryParse(e['price'].toString()) ?? 0.0;
      double cHT = double.tryParse(e['cost'].toString()) ?? 0.0;
      double q = double.tryParse((e['qty'] ?? e['quantity'] ?? 1).toString()) ?? 1.0;

      double pFinal = (enableTva && vRate > 0) ? pHT * (1 + (vRate / 100)) : pHT;
      double cFinal = cHT; 

      return {
        ...e,
        'product_id': e['product_id'],
        'variant_id': e['variant_id'],
        'qty': q,
        'quantity': q,
        'price': pFinal,
        'price_at_sale': pFinal,
        'cost': cFinal,
        'purchase_price_at_sale': cFinal,
        'vat_percent': vRate,
        'discount': 0.0,
      };
    }).toList();

   final payload = {
      "total_amount": total,
      "total_ttc": total, 
      "amount_paid": amountPaid,
      "paid_amount": amountPaid,
      "items": cleanItems,
      "client_id": clientId,
      "client_name": clientName,
      "payment_type": paymentType,
      "note": note,
      "date": DateTime.now().toIso8601String(),
      "total_vat": enableTva ? tva : 0,
      "timbre": timbre,
      "total_ht": ht,
      "vat_enabled": enableTva ? 1 : 0,
      "discount_mode": "amount",
      "discount_value": discount,
      "vat_percent": enableTva ? (tva > 0 ? 19.0 : 0.0) : 0.0,
      "is_return": isReturn ? 1 : 0,

      // Ajout des IDs de session
      "register_id": assignedRegId,
      "warehouse_id": effectiveWhId,
      "employee_id": empId,
      "user_id": posUserId,
      "mobile_user_id": mobileUserId,

      // 🚛 FIX CHANTIER 1 : Van tour ID pour déduction stock fourgon côté backend
      "van_tour_id": vanTourId,

      if (saleId != null) "sale_id": saleId, // ✏️ ÉDITION : UPDATE au lieu d'INSERT
    };
    await _updateLocalCacheOptimistically(isSale: true, saleItems: items);

    // 🛠️ FIX CRITIQUE STOCK CHAUFFEUR : Décrémenter aussi le stock du fourgon dans active_tour
    if (userRole == 'chauffeur') {
      await _updateActiveTourStock(items, isSale: true, isReturn: isReturn);
    }

    _lastCommandTime = DateTime.now(); 
    _addToQueue(saleId != null ? "UPDATE_SALE" : "CREATE_SALE", payload);
  }

  Future<void> sendComplexSaleOptimistic(double t, List i, {String? note, int? clientId, String? clientName, double? amountPaid, String? paymentType, double? discount, double tva = 0, double timbre = 0, double ht = 0, bool isReturn = false, int? saleId}) async {
      List<Map<String, dynamic>> cleanItems = i.map((e) => Map<String, dynamic>.from(e)).toList();
      await createSale(total: t, items: cleanItems, clientId: clientId, clientName: clientName, amountPaid: amountPaid??0, paymentType: paymentType??'cash', note: note??'', tva: tva, timbre: timbre, discount: discount??0, ht: ht, isReturn: isReturn, saleId: saleId);
  }

 Future<void> sendComplexPurchase(double total, List<dynamic> items, {String? note, int? supplierId, String? supplierName, double? amountPaid, String? paymentType, double tva = 0, double timbre = 0, double ht = 0, double discount = 0, bool isReturn = false, int? poId}) async {
    final prefs = await SharedPreferences.getInstance();
    bool enableTva = prefs.getBool('enable_tva') ?? false;

  final cleanItems = items.map((e) {
      double vRate = enableTva ? (double.tryParse(e['vat_percent'].toString()) ?? 0.0) : 0.0;
      double cHT = double.tryParse(e['cost'].toString()) ?? 0.0;
      double qty = double.tryParse(e['qty'].toString()) ?? 1.0;

      return {
        ...Map<String, dynamic>.from(e),
        'unit_price': cHT,
        'vat': vRate,
        'total_line': cHT * qty
      };
    }).toList();

   final payload = {
      "total_amount": total,
      "items": cleanItems,
      "supplier_id": supplierId,
      "amount_paid": amountPaid,
      "paid_amount": amountPaid,
      "payment_type": paymentType,
      "note": note,
      "date": DateTime.now().toIso8601String(),
      "total_vat": enableTva ? tva : 0,
      "timbre": timbre,
      "total_ht": ht,
      "vat_enabled": enableTva ? 1 : 0,
      "discount": discount,
      "is_return": isReturn ? 1 : 0,

      if (poId != null) "po_id": poId,   // ✏️ ÉDITION : UPDATE au lieu d'INSERT
    };
    await _updateLocalCacheOptimistically(isPurchase: true, purchaseItems: items);
    _lastCommandTime = DateTime.now(); 
    _addToQueue(poId != null ? 'UPDATE_PURCHASE' : 'CREATE_PURCHASE', payload);
  }

  Future<void> createTier(String type, Map<String, dynamic> data) async {
    final action = (type.contains('client')) ? 'ADD_CLIENT' : 'ADD_SUPPLIER';
    final newTier = {
      'id': 'TEMP', 
      'name': data['name'], 
      'phone': data['phone'] ?? '', 
      'balance': 0,
      'price_tier': 'retail',
      'credit_limit': 0.0
    };
    if (type.contains('client')) _cachedClients.insert(0, newTier);
    else _cachedSuppliers.insert(0, newTier);
    _lastCommandTime = DateTime.now(); 
    _addToQueue(action, {
      ...data, 
      'type': type,
      'price_tier': 'retail',
      'credit_limit': 0.0
    });
  }

  Future<void> createTierOptimistic(String type, Map<String, dynamic> data) async => createTier(type, data);

  Future<void> sendPartnerPaymentOptimistic({required dynamic partnerId, required double amount, required String type, String? note}) async {
    int pId = int.tryParse(partnerId.toString()) ?? 0;
    
    if (type == 'client' || type == 'CLIENT') {
      int idx = _cachedClients.indexWhere((c) => c['id'].toString() == pId.toString());
      if (idx >= 0) {
        double current = double.tryParse(_cachedClients[idx]['balance'].toString()) ?? 0;
        _cachedClients[idx]['balance'] = current - amount;
      }
    } else {
      int idx = _cachedSuppliers.indexWhere((s) => s['id'].toString() == pId.toString());
      if (idx >= 0) {
        double current = double.tryParse(_cachedSuppliers[idx]['balance'].toString()) ?? 0;
        _cachedSuppliers[idx]['balance'] = current - amount;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final int? registerId = prefs.getInt('assigned_register_id');
    
    _lastCommandTime = DateTime.now();
    _addToQueue('PAYMENT', { 'partner_id': pId, 'amount': amount, 'type': type, 'note': note ?? '', 'register_id': registerId });
  }

  Future<void> addChargeOptimistic(String l, double a, String c) async {
    _cachedCharges.insert(0, {'id': 'TEMP', 'label': l, 'amount': a, 'category': c, 'date_fr': 'À l\'instant'});
    _lastCommandTime = DateTime.now(); 
    final prefs = await SharedPreferences.getInstance();
    final int? registerId = prefs.getInt('assigned_register_id');
    _addToQueue('ADD_CHARGE', { 'label': l, 'amount': a, 'category': c, 'register_id': registerId });
  }

  Future<List<dynamic>> getTiersWithQueue(String type, String query) async {
      return getTiersList(type, query);
  }

  Future<Map<String, dynamic>> fetchDashboardData({bool forceRefresh = false}) async {
     try {
       final headers = await _getHeaders();
       final resp = await http.get(Uri.parse('$_baseUrl/dashboard'), headers: headers).timeout(const Duration(seconds: 15));
       if (resp.statusCode == 200) {
         _lastError = null; // 🟢 Connexion OK = on efface l'erreur
         return json.decode(resp.body);
       }
       debugPrint("⚠️ [API] /dashboard HTTP ${resp.statusCode}");
       _lastError = _humanizeError(resp.statusCode);
     } catch(e){
       debugPrint("❌ [API] /dashboard EXCEPTION: $e");
       _lastError = _humanizeError(e);
     }
     return {};
  }
  
  Future<List<dynamic>> getSalesList({int limit = 50}) async => _fetchList('/sales');
  Future<List<dynamic>> getChargesWithQueue() async => _fetchList('/charges');
  Future<List<dynamic>> getPurchasesList({int limit = 50}) async => _fetchList('/purchases');

 // --- MULTI-CAISSE (CASH MANAGER) ---
  Future<List<dynamic>> getRegisters() async => _fetchList('/registers');
  Future<List<dynamic>> getCashSessions() async => _fetchList('/cash_sessions');
  Future<List<dynamic>> getRegisterOperations() async => _fetchList('/register_operations');
  Future<List<dynamic>> getRegisterFullHistory(int regId) async => _fetchList('/registers/$regId/history'); // 🟢 NOUVELLE ROUTE !

  Future<void> openCashSessionOptimistic(int registerId, double initialFloat, String note) async {
    _lastCommandTime = DateTime.now();
    _addToQueue('OPEN_SESSION', {
      'register_id': registerId,
      'initial_float': initialFloat,
      'open_note': note,
      'open_time': DateTime.now().toIso8601String()
    });
  }

 Future<void> closeCashSessionOptimistic(int sessionId, int registerId, double closingTotal, double difference, String note) async {
    _lastCommandTime = DateTime.now();
    _addToQueue('CLOSE_SESSION', {
      'session_id': sessionId,
      'register_id': registerId, // 🟢 INDISPENSABLE POUR METTRE À JOUR LE SOLDE SUR LE PC
      'closing_total': closingTotal,
      'difference': difference,
      'close_note': note,
      'close_time': DateTime.now().toIso8601String()
    });
  }

 Future<void> addRegisterOperationOptimistic(int registerId, String type, double amount, String note) async {
    _lastCommandTime = DateTime.now();
    _addToQueue('REGISTER_OPERATION', {
      'register_id': registerId,
      'type': type,
      'amount': amount,
      'note': note,
      'date': DateTime.now().toIso8601String()
    });
  }

  Future<void> addRegisterTransferOptimistic(int fromRegisterId, int toRegisterId, double amount, String note) async {
    _lastCommandTime = DateTime.now();
    _addToQueue('REGISTER_TRANSFER', {
      'from_register_id': fromRegisterId,
      'to_register_id': toRegisterId,
      'amount': amount,
      'note': note,
      'date': DateTime.now().toIso8601String()
    });
  }
  // -----------------------------------
  
  Future<List<dynamic>> getSalesByDay(String date) async {
     List<dynamic> all = await getSalesList();
     return all.where((s) => s['date'].toString().startsWith(date)).toList();
  }

  Future<List<dynamic>> getSaleItems(dynamic saleId) async => _fetchList('/sales/$saleId/items');
  Future<List<dynamic>> getPurchaseItems(dynamic poId) async => _fetchList('/purchases/$poId/items');

  Future<List<dynamic>> getTiersList(String type, String query) async {
      final endpoint = (type.toLowerCase().contains('client')) ? '/clients' : '/suppliers';
      List<dynamic> list = await _fetchList(endpoint);
      if (query.isNotEmpty) return list.where((t) => t['name'].toString().toLowerCase().contains(query.toLowerCase())).toList();
      return list;
  }

  Future<Map<String, dynamic>> getTierDetails(String type, dynamic id) async {
    final endpoint = (type == 'client') ? '/clients/$id' : '/suppliers/$id';
    try {
      final response = await http.get(Uri.parse('$_baseUrl$endpoint'), headers: await _getHeaders()).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (e) {}
    return {}; 
  }

 Future<List<dynamic>> _fetchList(String endpoint) async {
    // 🚀 FIX SYNC MOBILE : On retourne le cache SEULEMENT si aucune action n'a eu lieu depuis 2 secondes
    // Et on force la requête réseau si on demande les Ventes (pour avoir les dernières)
    if (DateTime.now().difference(_lastCommandTime).inSeconds < 2 && !endpoint.contains('/sales')) {
      if (endpoint.contains('/clients') && _cachedClients.isNotEmpty) return _cachedClients;
      if (endpoint.contains('/suppliers') && _cachedSuppliers.isNotEmpty) return _cachedSuppliers;
      if (endpoint.contains('/charges') && _cachedCharges.isNotEmpty) return _cachedCharges;
    }
    try {
      final resp = await http.get(Uri.parse('$_baseUrl$endpoint'), headers: await _getHeaders()).timeout(const Duration(seconds: 15)); 
      if (resp.statusCode == 200) {
        final decodedData = json.decode(resp.body);
        if (decodedData is List) {
          final list = List<dynamic>.from(decodedData);
          // 🚀 CACHE RAM + SQLite (Offline-First)
          if (endpoint.contains('/clients')) {
            _cachedClients = List.from(list);
            _saveTiersCache('clients', list);
          }
          if (endpoint.contains('/suppliers')) {
            _cachedSuppliers = List.from(list);
            _saveTiersCache('suppliers', list);
          }
          if (endpoint.contains('/charges')) {
            _cachedCharges = List.from(list);
            _saveTiersCache('charges', list);
          }
          debugPrint("✅ [API] $endpoint → ${list.length} éléments");
          return list;
        }
      } else {
        debugPrint("⚠️ [API] $endpoint HTTP ${resp.statusCode}: ${resp.body.substring(0, (resp.body.length).clamp(0, 200))}");
        _lastError = _humanizeError(resp.statusCode);
      }
    } catch(e) {
      debugPrint("❌ [API] $endpoint EXCEPTION: $e");
      _lastError = _humanizeError(e);
    }
    // 🚀 FALLBACK OFFLINE : Si le réseau échoue, on charge depuis SQLite
    if (endpoint.contains('/clients') && _cachedClients.isEmpty) {
      _cachedClients = await _loadTiersCache('clients');
      if (_cachedClients.isNotEmpty) return _cachedClients;
    }
    if (endpoint.contains('/suppliers') && _cachedSuppliers.isEmpty) {
      _cachedSuppliers = await _loadTiersCache('suppliers');
      if (_cachedSuppliers.isNotEmpty) return _cachedSuppliers;
    }
    if (endpoint.contains('/charges') && _cachedCharges.isEmpty) {
      _cachedCharges = await _loadTiersCache('charges');
      if (_cachedCharges.isNotEmpty) return _cachedCharges;
    }
    return [];
  }

  Future<void> addProductOptimistic(Map<String, dynamic> raw) async {
    await saveProduct(
      name: raw['name'], price: double.parse(raw['price'].toString()), 
      cost: double.parse(raw['cost'].toString()), stock: double.parse(raw['stock'].toString()),
      barcode: raw['barcode'], category: raw['category']
    );
  }

  Future<void> updateProductOptimistic(Map<String, dynamic> data) async {
     await saveProduct(
         id: data['id'].toString(), name: data['name'], price: double.parse(data['price'].toString()), cost: double.parse(data['cost'].toString()),
         stock: double.parse(data['stock'].toString())
     );
  }

  Future<void> printLocalTransaction(dynamic id, bool isSale, String format) async {
     _addToQueue('PRINT', { 'id': id, 'is_sale': isSale, 'format': format });
  }

  Future<bool> updateProductImage(dynamic productId, File imageFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload-image'));
      request.headers.addAll(await _getHeaders());
      
      request.fields['product_id'] = productId.toString();
      
      String fileName = 'prod_${DateTime.now().millisecondsSinceEpoch}.jpg';
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path, filename: fileName)
      );

      var response = await request.send().timeout(const Duration(seconds: 20));
      var responseData = await response.stream.bytesToString();
      var jsonResponse = json.decode(responseData);

      if (response.statusCode == 200 && jsonResponse['success'] == true) {
        final String newUrl = jsonResponse['url']; 
        await _updateLocalCacheOptimistically(updatedProduct: { "id": productId, "base_image_path": newUrl });
        
        // 🟢 CORRECTION : Ajouter un ordre de mise à jour pour que le PC reçoive l'image
        _addToQueue('UPDATE_PRODUCT', {'id': productId, 'base_image_path': newUrl});
        
        return true;
      }
    } catch (e) {
      debugPrint("Erreur upload image: $e");
    }
    return false;
  }

  Future<String?> fetchAiProductImage(String query, {String? barcode}) async {
    try {
      final uri = Uri.parse("https://www.google.com/search?q=${Uri.encodeComponent(query + ' packaging')}&tbm=isch");
      final headers = { "User-Agent": "Mozilla/5.0" };
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
         RegExp exp = RegExp(r'\["(http[^"]+?)",\d+,\d+\]');
         Match? match = exp.firstMatch(response.body);
         return match?.group(1);
      }
    } catch (_){}
    return "https://ui-avatars.com/api/?name=$query";
  }
  
  Future<Map<String, dynamic>> verifyCredentials(String licenseKey, String username, String pass) async {
    try {
       final resp = await http.post(
         Uri.parse('$_baseUrl/mobile/login'), 
         headers: { "Content-Type": "application/json", "x-license-key": licenseKey }, // The interceptor expects x-license-key for tenant resolution
         body: json.encode({ "username": username, "password": pass })
       ).timeout(const Duration(seconds: 25));
       
       if(resp.statusCode == 200) {
          final data = json.decode(resp.body);
          if (data['success'] == true) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('license_key', licenseKey); // For API backwards compatibility
            await prefs.setString('api_user', username);
            await prefs.setString('api_pass', pass);
            await prefs.setBool('is_activated', true);
            
            // 🟢 Sauvegarde des infos de l'utilisateur mobile
            await prefs.setString('user_role', data['role'] ?? '');
            await prefs.setString('username', data['username'] ?? username);
            await prefs.setString('user_full_name', data['user']?['full_name'] ?? data['username'] ?? username);
            await prefs.setString('user_permissions', json.encode(data['permissions'] ?? []));

            
            int? _parseIntSecure(dynamic val) {
              if (val == null) return null;
              if (val is int) return val;
              return int.tryParse(val.toString());
            }

            // 🟢 Sauvegarde des IDs logistiques
            final mUid = _parseIntSecure(data['id']);
            if (mUid != null) await prefs.setInt('mobile_user_id', mUid);
            else await prefs.remove('mobile_user_id');

            final eId = _parseIntSecure(data['employee_id']);
            if (eId != null) await prefs.setInt('employee_id', eId);
            else await prefs.remove('employee_id');

            final pUid = _parseIntSecure(data['user_id']);
            if (pUid != null) await prefs.setInt('pos_user_id', pUid);
            else await prefs.remove('pos_user_id');
            
            final rId = _parseIntSecure(data['register_id']);
            if (rId != null) await prefs.setInt('assigned_register_id', rId);
            else await prefs.remove('assigned_register_id');
            
            final wId = _parseIntSecure(data['warehouse_id']);
            if (wId != null) await prefs.setInt('assigned_warehouse_id', wId);
            else await prefs.remove('assigned_warehouse_id');
            
            // 🟢 GESTION ACCÈS GLOBAL
            if (data['has_global_warehouse_access'] == true || data['has_global_warehouse_access'] == '1') await prefs.setBool('global_warehouse', true);
            else await prefs.remove('global_warehouse');
            
            if (data['has_global_register_access'] == true || data['has_global_register_access'] == '1') await prefs.setBool('global_register', true);
            else await prefs.remove('global_register');
            
            return {'success': true, 'message': 'Connexion réussie'};
          }
          return {'success': false, 'message': data['message'] ?? 'Erreur inconnue'};
      } else if (resp.statusCode == 401 || resp.statusCode == 403 || resp.statusCode == 404) {
          try {
             final errData = json.decode(resp.body);
             return {'success': false, 'message': errData['error'] ?? errData['message'] ?? '🔐 Identifiants incorrects ou accès refusé'};
          } catch (_) {
             return {'success': false, 'message': '🔐 Identifiants incorrects ou accès refusé'};
          }
       }
       return {'success': false, 'message': _humanizeError(resp.statusCode)};
    } catch(e) { 
        debugPrint("🚨 ERREUR CRITIQUE LOGIN: $e");
        return {'success': false, 'message': _humanizeError(e)}; 
    }
  }

  // 🛠️ FIX MULTI-DEPOT MOBILE : Purge enrichie (tiers_cache ajouté pour le switch dépôt)
  Future<void> clearCache() async {
    final db = await database;
    await db.delete('queue');
    await db.delete('cache');
    await db.delete('tiers_cache');
    await db.delete('deltas');
    _commandQueue.clear();
    _pendingDeltas.clear();
  }
Future<void> sendAddProduct(String n, double p, double c, double s, String b, String cat, {String? imageData, double vatPercent = 19.0}) async {
     await saveProduct(name: n, price: p, cost: c, stock: s, barcode: b, category: cat, vatPercent: vatPercent);
  }
  
  Future<void> sendStockUpdate(dynamic productId, double quantity, String type) async {
      _addToQueue('UPDATE_PRODUCT', {'id': productId, 'base_stock': quantity});
  }

  // ============================================
  // 🔄 MODIFICATION DE TICKET EXISTANT (UPDATE_SALE)
  // ============================================
  /// Met à jour une vente existante sur le backend.
  /// Le backend (updateExistingSale) annule l'ancien stock, supprime les anciens items,
  /// puis re-crée les nouveaux items et déduit le stock.
  Future<void> updateSale({
    required int saleId,
    required double total,
    required List<Map<String, dynamic>> items,
    int? clientId,
    String? clientName,
    double amountPaid = 0,
    String paymentType = "cash",
    String note = "",
    double tva = 0,
    double timbre = 0,
    double discount = 0,
    double ht = 0,
    bool isReturn = false,
  }) async {
    // Normalise les items pour le format attendu par updateExistingSale
    // Backend attend: { product_id, variant_id, quantity, unit_price }
   final cleanItems = items.map((e) {
      double q = double.tryParse((e['qty'] ?? e['quantity'] ?? 1).toString()) ?? 1.0;
      double p = double.tryParse((e['price'] ?? e['unit_price'] ?? 0).toString()) ?? 0.0;
      double c = double.tryParse((e['cost'] ?? 0).toString()) ?? 0.0;
      double vRate = double.tryParse((e['vat_percent'] ?? 0).toString()) ?? 0.0;

      return {
        'product_id': e['product_id'],
        'variant_id': e['variant_id'],
        'name': e['name'] ?? 'Article Inconnu',
        'qty': q,
        'quantity': q,
        'unit_price': p,
        'price': p,
        'price_at_sale': p,
        'cost': c,
        'purchase_price_at_sale': c,
        'vat_percent': vRate,
      };
    }).toList();

    final payload = {
      "sale_id": saleId,
      "total_amount": total,
      "items": cleanItems,
      "client_id": clientId,
      "amount_paid": amountPaid,
      "payment_type": paymentType,
      "note": note,
      "total_vat": tva,
      "timbre": timbre,
      "total_ht": ht,
      "vat_enabled": tva > 0 ? 1 : 0,
      "discount": { "mode": "amount", "value": discount },
      "is_return": isReturn ? 1 : 0,
    };

    _lastCommandTime = DateTime.now();
    _addToQueue("UPDATE_SALE", payload);
  }

  Future<void> updatePurchase({
    required int poId,
    required double total,
    required List<Map<String, dynamic>> items,
    int? supplierId,
    String? supplierName,
    double amountPaid = 0,
    String paymentType = "cash",
    String note = "",
    double tva = 0,
    double timbre = 0,
    double discount = 0,
    double ht = 0,
    bool isReturn = false,
  }) async {
    final cleanItems = items.map((e) {
      double q = double.tryParse((e['qty'] ?? e['quantity'] ?? 1).toString()) ?? 1.0;
      double p = double.tryParse((e['price'] ?? e['unit_price'] ?? 0).toString()) ?? 0.0;
      double c = double.tryParse((e['cost'] ?? 0).toString()) ?? 0.0;
      double vRate = double.tryParse((e['vat_percent'] ?? 0).toString()) ?? 0.0;

      return {
        'product_id': e['product_id'],
        'variant_id': e['variant_id'],
        'quantity': q,
        'qty': q,
        'unit_price': p,
        'price': p,
        'cost': c,
        'vat_percent': vRate,
      };
    }).toList();

    final payload = {
      "po_id": poId,
      "total_amount": total,
      "items": cleanItems,
      "supplier_id": supplierId,
      "amount_paid": amountPaid,
      "payment_type": paymentType,
      "note": note,
      "total_vat": tva,
      "timbre": timbre,
      "total_ht": ht,
      "vat_enabled": tva > 0 ? 1 : 0,
      "discount": discount,
      "is_return": isReturn ? 1 : 0,
    };

    _lastCommandTime = DateTime.now();
    _addToQueue("UPDATE_PURCHASE", payload);
  }

  // ============================================
  // 📉 DÉCLARATION DE PERTE DE STOCK (DECLARE_LOSS)
  // ============================================
  /// Déclare une perte de stock (casse, péremption, vol, etc.)
  /// Le backend (declareStockLoss) déduit le stock et crée une charge si financialImpact=true.
  Future<void> declareStockLoss({
    required int productId,
    int? variantId,
    required double qty,
    required String reason,
    bool financialImpact = true,

  }) async {
    // 🛠️ FIX AUDIT MASTER : Récupérer le vrai user_id et warehouse_id au lieu de valeurs en dur
    final prefs = await SharedPreferences.getInstance();
    final int userId = prefs.getInt('employee_id') ?? 1;
    final int? whId = prefs.getInt('assigned_warehouse_id');

    // Mise à jour optimiste du cache local (déduit le stock)
    await _updateLocalCacheOptimistically(
      isSale: true,
      saleItems: [{'product_id': productId, 'variant_id': variantId, 'qty': qty}],
    );

    _lastCommandTime = DateTime.now();
    _addToQueue("DECLARE_LOSS", {
      'product_id': productId,
      'variant_id': variantId,
      'qty': qty,
      'reason': reason,
      'user_id': userId,
      'financial_impact': financialImpact,
      'warehouse_id': whId,
    });
  }

  // ============================================
  // 🖨️ GESTION DES IMPRIMANTES SAUVEGARDÉES
  // ============================================

  /// Récupère l'imprimante sauvegardée pour un format donné ('Ticket' ou 'A4')
  Future<Printer?> getSavedPrinter(String format) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('printer_${format}_name');
    final url = prefs.getString('printer_${format}_url');
    if (name == null || name.isEmpty) return null;
    return Printer(url: url ?? '', name: name);
  }

  /// Sauvegarde (ou supprime si null) une imprimante pour un format donné
  Future<void> savePrinter(String format, Printer? printer) async {
    final prefs = await SharedPreferences.getInstance();
    if (printer == null) {
      await prefs.remove('printer_${format}_name');
      await prefs.remove('printer_${format}_url');
    } else {
      await prefs.setString('printer_${format}_name', printer.name);
      await prefs.setString('printer_${format}_url', printer.url);
    }
  }

  Future<bool> printCloudDocument(String format, String docType, dynamic id) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/print/$format/$docType/$id'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        String htmlContent = response.body;
        final String domainUrl = _baseUrl.replaceAll('/api', '');

        htmlContent = htmlContent.replaceAll('http://localhost:3000', domainUrl);
        htmlContent = htmlContent.replaceAll('http://127.0.0.1:3000', domainUrl);

        Printing.layoutPdf(
          name: '${docType}_${id}_$format.pdf',
          onLayout: (PdfPageFormat actualFormat) async {
            try {
              return await Printing.convertHtml(
                format: format == 'Ticket' ? PdfPageFormat.roll80 : (format == 'A5' ? PdfPageFormat.a5 : PdfPageFormat.a4), 
                html: htmlContent,
                baseUrl: domainUrl, 
              ).timeout(const Duration(seconds: 10)); 
            } catch (e) {
              debugPrint("Erreur lors de la conversion HTML->PDF : $e");
              throw Exception("Échec de la génération. Une image ou ressource bloque le fichier.");
            }
          },
        );
        return true;
      }
    } catch (e) {
      debugPrint("Erreur réseau/impression: $e");
    }
    return false;
  }

  Future<bool> printViaPC(String format, String docType, dynamic id, {Map<String, dynamic>? options}) async {
    try {
      final taskId = "pdf_${DateTime.now().millisecondsSinceEpoch}";
      
      final commandPayload = {
        "taskId": taskId,
        "format": format,
        "docType": docType,
        "id": id,
        "options": options ?? {}
      };

      final cmdResponse = await http.post(
        Uri.parse('$_baseUrl/command'),
        headers: await _getHeaders(),
        body: json.encode({ "action": "REQUEST_PDF_CLOUD", "payload": commandPayload })
      );

      if (cmdResponse.statusCode != 200) return false;

      for (int i = 0; i < 7; i++) {
        await Future.delayed(const Duration(seconds: 2));
        
        final pdfUrl = 'https://infi-nasro2.online/api/uploads/$taskId.pdf';
        final checkResponse = await http.get(Uri.parse('$pdfUrl?t=${DateTime.now().millisecondsSinceEpoch}')); 
        
        if (checkResponse.statusCode == 200 && checkResponse.bodyBytes.length > 1000) {
          if (format == 'Ticket') {
            final prefs = await SharedPreferences.getInstance();
            String mac = prefs.getString('mac_printer') ?? "";
            
            if (mac.isNotEmpty) {
              try {
                bool isConnected = await PrintBluetoothThermal.connectionStatus;
                if (!isConnected) {
                  await PrintBluetoothThermal.connect(macPrinterAddress: mac);
                }

                isConnected = await PrintBluetoothThermal.connectionStatus;
                
                if (isConnected) {
                  final profile = await CapabilityProfile.load();
                  final generator = Generator(PaperSize.mm80, profile);
                  List<int> bytes = [];

                  await for (var page in Printing.raster(checkResponse.bodyBytes, dpi: 200)) {
                    final pngData = await page.toPng();
                    final decodedImage = img.decodeImage(pngData);
                    
                    if (decodedImage != null) {
                      final resized = img.copyResize(decodedImage, width: 576);
                      bytes += generator.imageRaster(resized);
                    }
                  }
                  
                  bytes += generator.feed(2); 
                  bytes += generator.cut();   

                  await PrintBluetoothThermal.writeBytes(bytes);
                  return true; 
                }
              } catch (e) {
                debugPrint("Erreur lors de l'impression Bluetooth: $e");
              }
            }
          }

          Printing.layoutPdf(
            name: '${docType}_${id}_$format.pdf',
            onLayout: (PdfPageFormat _) async => checkResponse.bodyBytes,
          );
          
          return true;
        }
      }
      
      return false;
      
    } catch (e) {
      debugPrint("Erreur impression via PC: $e");
      return false;
    }
  }

  // ============================================
  // 📍 TRACKING GPS
  // ============================================
  Future<void> sendGpsPosition(double lat, double lng) async {
    // Envoi silencieux via la file d'attente
    _addToQueue("UPDATE_GPS", {
      'latitude': lat,
      'longitude': lng,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Envoi GPS direct (temps réel, sans file d'attente) pour sync forcée
  Future<bool> sendGpsPositionDirect(double lat, double lng) async {
    // 🛠️ FIX CHANTIER 5 : Protection contre les positions null/NaN
    if (lat == 0.0 && lng == 0.0) {
      debugPrint("GPS_DIRECT: Position (0,0) ignorée (pas de fix GPS)");
      return false;
    }
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) {
      debugPrint("GPS_DIRECT: Position NaN/Infinite ignorée");
      return false;
    }
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$_baseUrl/mobile/gps/update'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'latitude': lat,
          'longitude': lng,
          // 🛠️ FIX CHANTIER 5 : Timestamp ISO 8601 précis (UTC)
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint("GPS_DIRECT: Erreur envoi - $e");
      _lastError = _humanizeError(e);
      return false;
    }
  }

  // ============================================
  // 🚛 LOGISTIQUE MOBILE
  // ============================================

  /// Récupère la tournée active du chauffeur connecté
  Future<Map<String, dynamic>> getActiveTour() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('$_baseUrl/mobile/tours/active'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['tour'] != null) {
          final tour = data['tour'];
          // 🚛 FIX CHANTIER 1 : Sauvegarder le van_tour_id et van_id pour createSale()
          final prefs = await SharedPreferences.getInstance();
          if (tour['tour_id'] != null) {
            await prefs.setInt('active_van_tour_id', tour['tour_id'] is int ? tour['tour_id'] : int.tryParse(tour['tour_id'].toString()) ?? 0);
          }
          if (tour['van_id'] != null) {
            await prefs.setInt('active_van_id', tour['van_id'] is int ? tour['van_id'] : int.tryParse(tour['van_id'].toString()) ?? 0);
          }
          // 🚀 V3 : Cache offline de la tournée
          try {
            final db = await database;
            await db.insert('active_tour', {
              'id': tour['tour_id'] ?? 0,
              'van_id': tour['van_id'] ?? 0,
              'status': tour['status'] ?? '',
              'data': jsonEncode(tour),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          } catch (_) {}
          return tour;
        }
      }
      // Fallback offline : lire depuis SQLite
      try {
        final db = await database;
        final rows = await db.query('active_tour', limit: 1);
        if (rows.isNotEmpty) {
          return jsonDecode(rows.first['data'] as String);
        }
      } catch (_) {}
      return {};
    } catch (e) {
      _lastError = "Erreur tournée: $e";
      debugPrint("LOGISTIQUE: Erreur getActiveTour - $e");
      // Fallback offline
      try {
        final db = await database;
        final rows = await db.query('active_tour', limit: 1);
        if (rows.isNotEmpty) {
          return jsonDecode(rows.first['data'] as String);
        }
      } catch (_) {}
      return {};
    }
  }

  /// 🛡️ Récupère le rôle de l'utilisateur connecté (admin, chauffeur, vendeur...)
  Future<String> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role') ?? '';
  }

  /// 🚛 ADMIN : Liste TOUTES les tournées actives (map-data pour données enrichies)
  Future<List<Map<String, dynamic>>> getAllActiveTours() async {
    try {
      final headers = await _getHeaders();
      // 🟢 Utiliser map-data au lieu de fleet-status pour avoir stock, ventes, transferts, GPS
      final res = await http.get(
        Uri.parse('$_baseUrl/mobile/admin/map-data'),
        headers: headers,
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['vans'] != null) {
          return List<Map<String, dynamic>>.from(data['vans']);
        }
      }
      return [];
    } catch (e) {
      debugPrint("FLEET: Erreur getAllActiveTours - $e");
      return [];
    }
  }

  /// ⏳ CHANTIER 4 : Démarrer une tournée en attente (pending → loading)
  Future<Map<String, dynamic>> startPendingTour(int tourId) async {
    _lastCommandTime = DateTime.now();
    _addToQueue('START_PENDING_TOUR', {'tour_id': tourId});
    return {'success': true, 'message': 'Tournée en attente démarrée (hors ligne)'};
  }

  /// Récupère la liste des transferts inter-dépôts avec filtres optionnels
  Future<List<dynamic>> getPendingTransfers({String? status, String? search, String? dateFrom, String? dateTo}) async {
    try {
      final headers = await _getHeaders();
      final params = <String, String>{};
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (dateFrom != null) params['date_from'] = dateFrom;
      if (dateTo != null) params['date_to'] = dateTo;

      final uri = Uri.parse('$_baseUrl/mobile/transfers').replace(queryParameters: params.isNotEmpty ? params : null);
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          return data['transfers'] ?? [];
        }
      }
      return [];
    } catch (e) {
      _lastError = "Erreur transferts: $e";
      debugPrint("LOGISTIQUE: Erreur getPendingTransfers - $e");
      return [];
    }
  }

  /// Récupère le détail d'un transfert avec ses articles
  Future<Map<String, dynamic>> getTransferDetails(dynamic id) async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('$_baseUrl/mobile/transfers/$id'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          return data['transfer'] ?? {};
        }
      }
      return {};
    } catch (e) {
      _lastError = "Erreur détails transfert: $e";
      debugPrint("LOGISTIQUE: Erreur getTransferDetails - $e");
      return {};
    }
  }

  /// Valide la réception d'un transfert. missingItems = [{product_id, variant_id, qty}]
  Future<bool> receiveTransfer(dynamic id, List<Map<String, dynamic>> missingItems) async {
    final List<Map<String, dynamic>> cleanItems = [];
    for (final i in missingItems) {
      cleanItems.add({
        'product_id': i['product_id'],
        'variant_id': i['variant_id'],
        'qty': i['qty'] ?? i['quantity'] ?? 1,
      });
    }
    _lastCommandTime = DateTime.now();
    _addToQueue('RECEIVE_TRANSFER', {
      'transfer_id': id,
      'missing_items': cleanItems,
      'received_at': DateTime.now().toIso8601String(),
    });
    return true;
  }

  /// 🗺️ Récupère les données riches pour la carte Live Tracking
  Future<Map<String, dynamic>> getMapData() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('$_baseUrl/mobile/admin/map-data'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          return {
            'vans': data['vans'] ?? [],
            'warehouses': data['warehouses'] ?? [],
            // 🛠️ FIX TRACKING PERMANENT : Transmettre les utilisateurs libres
            'free_users': data['free_users'] ?? [],
          };
        }
      }
      return {'vans': [], 'warehouses': [], 'free_users': []};
    } catch (e) {
      _lastError = "Erreur map data: $e";
      debugPrint("LOGISTIQUE: Erreur getMapData - $e");
      return {'vans': [], 'warehouses': [], 'free_users': []};
    }
  }

  // =========================================================
  // 🚚 LOGISTIQUE: NOUVELLES METHODES (TOURNÉES & TRANSFERTS)
  // =========================================================

  Future<Map<String, dynamic>> getLogisticsResources() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$_baseUrl/mobile/logistics/resources'), headers: headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) return data;
      }
      return {'vans': [], 'warehouses': []};
    } catch (e) {
      debugPrint("API: getLogisticsResources error - $e");
      return {'vans': [], 'warehouses': []};
    }
  }

  Future<Map<String, dynamic>> startTour(int vanId, double startKm) async {
    _lastCommandTime = DateTime.now();
    _addToQueue('START_TOUR', {'van_id': vanId, 'start_km': startKm});
    return {'success': true, 'message': 'Tournée démarrée (hors ligne)'};
  }

  Future<Map<String, dynamic>> closeTour(int tourId, double endKm, String notes) async {
    _lastCommandTime = DateTime.now();
    _addToQueue('CLOSE_TOUR', {'tour_id': tourId, 'end_km': endKm, 'notes': notes});
    return {'success': true, 'message': 'Tournée clôturée (hors ligne)'};
  }

  Future<Map<String, dynamic>> createTransfer(int toWh, List<Map<String, dynamic>> items) async {
    final List<Map<String, dynamic>> cleanItems = [];
    for (final i in items) {
      cleanItems.add({
        'product_id': i['product_id'],
        'variant_id': i['variant_id'],
        'qty': i['qty'] ?? i['quantity'] ?? 1,
      });
    }
    _lastCommandTime = DateTime.now();
    _addToQueue('CREATE_TRANSFER', {'to_wh': toWh, 'items': cleanItems});
    return {'success': true, 'message': 'Transfert créé (hors ligne)'};
  }

  Future<Map<String, dynamic>> getWarehouseDetails(int id) async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('$_baseUrl/mobile/admin/warehouses/$id'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          return data;
        }
      }
      return {'stock_items': [], 'total_qty': 0, 'total_value': 0};
    } catch (e) {
      debugPrint("API: Erreur getWarehouseDetails - $e");
      return {'stock_items': [], 'total_qty': 0, 'total_value': 0};
    }
  }

  // =========================================================
  // 🗺️ VMS — PROGRAMME DE TOURNÉE (Arrêts Clients)
  // =========================================================

  /// Récupère les arrêts planifiés de la tournée active du chauffeur
  Future<List<Map<String, dynamic>>> fetchTourStops() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('$_baseUrl/mobile/tours/stops'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['stops'] != null) {
          return List<Map<String, dynamic>>.from(data['stops']);
        }
      }
      return [];
    } catch (e) {
      debugPrint("VMS: Erreur fetchTourStops - $e");
      return [];
    }
  }

  /// Marque un arrêt comme visité (check-in) avec coordonnées GPS
  Future<Map<String, dynamic>> checkInStop(int stopId, {double? lat, double? lng, String? note}) async {
    _lastCommandTime = DateTime.now();
    _addToQueue('CHECK_IN_TOUR', {
      'stop_id': stopId,
      'latitude': lat,
      'longitude': lng,
      'note': note,
    });
    return {'success': true, 'message': 'Arrêt validé (hors ligne)'};
  }
}