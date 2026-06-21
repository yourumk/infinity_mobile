import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/cart_item_card.dart';
import '../widgets/searchable_select_modal.dart';
import 'offline_queue_page.dart';
import 'activation_page.dart'; // 🟢 Pour la redirection expulsion
import 'app_locked_page.dart'; // 🟡 Pour la suspension temporaire
import 'dart:convert';

class SalesPage extends StatefulWidget {
  final VoidCallback? onBack;
  final int? initialClientId;
  final String? initialClientName;
  const SalesPage({super.key, this.onBack, this.initialClientId, this.initialClientName});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription? _dataSubscription;
  DateTime? _lastRefreshTime;

  List<dynamic> _allProducts = [];
  List<dynamic> _filteredProducts = [];
  List<String> _categories = ['Tout'];
  List<String> _subCategories = [];
  List<String> _currentSubCategories = [];

  List<dynamic> _clients = [];

  String _selectedCategory = 'Tout';
  String _selectedSubCategory = 'Tout';
  String _activeSmartFilter = 'none';
  String _stockFilter = 'Tout';

  List<Map<String, dynamic>> _cart = [];
  int? _selectedClientId;
  String _selectedClientName = "Client Comptoir";

  bool _isLoading = true;
  bool _isCheckoutOpen = false; // 🟢 FIX: Empêche d'ouvrir deux paniers superposés
  Timer? _debounce;

  bool _enableTva = false;
  bool _enableTimbre = false;
  bool _allowNegativeStock = false; // 📦 Stock négatif autorisé ou non

  @override
  void initState() {
    super.initState();
    _selectedClientId = widget.initialClientId;
    if (widget.initialClientName != null) {
      _selectedClientName = widget.initialClientName!;
    }
    _loadSettings();
    _restoreCart(); // 🚀 Restaurer le panier depuis SQLite
    _api.startAutoSync();
    _loadData();
    _dataSubscription = _api.onDataUpdated.listen((_) {
      final now = DateTime.now();
      if (_lastRefreshTime == null || now.difference(_lastRefreshTime!).inSeconds > 2) {
        _lastRefreshTime = now;
        if (mounted) _loadData(silent: true);
      }
    });
  }

  Future<void> _restoreCart() async {
    final saved = await _api.loadCart('sales');
    if (saved.isNotEmpty && mounted) {
      setState(() => _cart = saved);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _enableTva = prefs.getBool('enable_tva') ?? false;
        _enableTimbre = prefs.getBool('enable_timbre') ?? false;
        _allowNegativeStock = prefs.getBool('allow_negative_stock') ?? false;
      });
    }
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _api.getProductsWithQueue(),
        _api.getTiersList('clients', '')
      ]);

      final productsData = results[0] as Map<String, dynamic>;
      final clientsData = results[1] as List<dynamic>;

      if (mounted) {
        setState(() {
          _allProducts = productsData['products'] ?? [];
      
      // 🟢 TÂCHE 3 : Nettoyer le panier des produits fantômes
      _cart.removeWhere((cartItem) {
        final qty = double.tryParse(cartItem['qty']?.toString() ?? '0') ?? 0.0;
        if (qty <= 0) return true;
        final exists = _allProducts.any((p) => p['id'].toString() == cartItem['product_id'].toString());
        return !exists;
      });
      _api.saveCart('sales', _cart);
      
      _filteredProducts = List.from(_allProducts);
      List<dynamic> cats = productsData['categories'] ?? [];
var uniqueCats = cats.map((e) => e.toString())
    .where((c) => c.toLowerCase() != 'tout')
    .toSet()
    .toList();
_categories = ['Tout', ...uniqueCats];

          Set<String> subCatsSet = {};
          for(var p in _allProducts) {
             if(p['sub_category'] != null && p['sub_category'].toString().isNotEmpty) {
               subCatsSet.add(p['sub_category'].toString());
             }
          }
          _subCategories = subCatsSet.toList();
          _clients = clientsData;
          _isLoading = false;
          _updateSubCategoryList();
          _applyFilters();
        });
      }
    } catch (e) {
      // 🟢 EXPULSION EN DIRECT : Le compte a été touché par l'admin !
      if (e.toString().contains('AUTH_INVALID')) {
        _forceLogout();
        return;
      }
      // 🟡 VERROUILLAGE TEMPORAIRE
      if (e.toString().contains('AUTH_LOCKED')) {
        _forceLock();
        return;
      }
      if (mounted) {
        setState(() => _isLoading = false);
        if (!silent) {
          final apiError = _api.lastError;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("⚠️ ${apiError ?? 'Erreur chargement ventes: $e'}"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ));
        }
      }
    }
  }

Future<void> _scanBarcode() async {
    bool isScanned = false; 
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text("Scanner un produit", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            centerTitle: true,
          ),
          extendBodyBehindAppBar: true,
          body: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(
                onDetect: (capture) {
                  if (isScanned) return; 
                  final String? scannedValue = capture.barcodes.first.rawValue;
                  if (scannedValue != null) {
                    isScanned = true;
                    Navigator.of(context).pop();
                    setState(() {
                      _searchController.text = scannedValue;
                      _applyFilters();
                    });
                  }
                },
              ),
              Container(
                width: 280,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange, width: 4),
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              Positioned(
                bottom: 80,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner, color: Colors.white),
                      SizedBox(width: 10),
                      Text("Centrez le code-barres", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
  void _updateSubCategoryList() {
    if (_selectedCategory == 'Tout') {
      _currentSubCategories = [];
    } else {
      Set<String> subSet = {};
      final productsInCat = _allProducts.where((p) => (p['category'] ?? '').toString() == _selectedCategory);
      for (var p in productsInCat) {
        if (p['sub_category'] != null && p['sub_category'].toString().isNotEmpty) {
          subSet.add(p['sub_category'].toString());
        }
      }
     var filteredSubSet = subSet.where((s) => s.toLowerCase() != 'tout').toList();
_currentSubCategories = ['Tout', ...filteredSubSet];
    }
    if (!_currentSubCategories.contains(_selectedSubCategory)) {
      _selectedSubCategory = 'Tout';
    }
  }

  // 🟢 FIX: Calcule le stock effectif en tenant compte des variantes
  double _getEffectiveStock(dynamic p) {
    final variants = p['variants'];
    if (variants != null && variants is List && variants.isNotEmpty) {
      double total = 0;
      for (var v in variants) {
        total += double.tryParse(v['stock']?.toString() ?? '0') ?? 0;
      }
      return total;
    }
    return double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      List<dynamic> temp = _allProducts.where((p) {
       final name = (p['name'] ?? '').toString().toLowerCase();
      final ref = (p['ref'] ?? '').toString().toLowerCase();
      final barcode = (p['barcode'] ?? '').toString().toLowerCase();
      
      // 🟢 RECHERCHE MULTI-CODES ET VARIANTES
      List<dynamic> barcodesList = p['barcodes'] ?? [];
      bool matchesBarcode = barcode.contains(query) || 
                            barcodesList.any((b) => b.toString().toLowerCase().contains(query));

      if (!matchesBarcode && p['variants'] != null) {
          for (var v in p['variants']) {
              if ((v['barcode'] ?? '').toString().toLowerCase().contains(query) || 
                  (v['sku'] ?? '').toString().toLowerCase().contains(query)) {
                  matchesBarcode = true;
                  break;
              }
          }
      }
        final matchesText = query.isEmpty || name.contains(query) || ref.contains(query) || matchesBarcode;

        bool matchesCategory = true;
        if (_selectedCategory != 'Tout') {
             final pCat = (p['category'] ?? p['category_name'] ?? '').toString();
             matchesCategory = pCat == _selectedCategory;
        }
        bool matchesSubCategory = true;
        if (_selectedSubCategory != 'Tout' && _currentSubCategories.isNotEmpty) {
           final pSub = (p['sub_category'] ?? '').toString();
           matchesSubCategory = pSub == _selectedSubCategory;
        }
        return matchesText && matchesCategory && matchesSubCategory;
      }).toList();

      if (_activeSmartFilter == 'fav') {
        temp = temp.where((p) => (int.tryParse(p['is_favorite']?.toString() ?? '0') ?? 0) == 1).toList();
      } else if (_activeSmartFilter == 'low') {
        temp = temp.where((p) {
          final stock = _getEffectiveStock(p);
          final min = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5;
          return stock <= min;
        }).toList();
      }

      if (_stockFilter != 'Tout') {
        temp = temp.where((p) {
          final stock = _getEffectiveStock(p);
          final min = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5;
          if (_stockFilter == 'En Stock') return stock > 0;
          if (_stockFilter == 'Stock Bas') return stock > 0 && stock <= min;
          if (_stockFilter == 'Rupture') return stock <= 0;
          return true;
        }).toList();
      }

      if (_activeSmartFilter == 'top') {
        temp.sort((a, b) {
          final soldA = double.tryParse(a['total_sold']?.toString() ?? '0') ?? 0;
          final soldB = double.tryParse(b['total_sold']?.toString() ?? '0') ?? 0;
          return soldB.compareTo(soldA);
        });
      } else if (_activeSmartFilter == 'new') {
        temp.sort((a, b) {
          final idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
          final idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
          return idB.compareTo(idA);
        });
      } else {
         temp.sort((a, b) => (a['name'] ?? '').toString().compareTo(b['name'] ?? ''));
      }
      setState(() => _filteredProducts = temp);
    });
  }

  double _getQtyInCart(int productId) {
    final item = _cart.firstWhere(
      (element) => element['product_id'] == productId && element['variant_id'] == null, 
      orElse: () => {},
    );
    return item.isNotEmpty ? (item['qty'] as double) : 0.0;
  }

  void _quickUpdateCart(dynamic product, double delta) {
    final int pId = int.tryParse(product['id'].toString()) ?? 0;
    final double price = double.tryParse(product['price'].toString()) ?? 0.0; 
    final double cost = double.tryParse(product['cost'].toString()) ?? 0.0; // 🟢 FIX CRITIQUE: Récupérer le coût
    
    setState(() {
      final index = _cart.indexWhere((item) => 
          item['product_id'] == pId && 
          item['variant_id'] == null &&
          item['price'] == price
      );
      
      if (index >= 0) {
        double newQty = _cart[index]['qty'] + delta;
        if (newQty <= 0) {
          _cart.removeAt(index);
        } else {
          _cart[index]['qty'] = newQty;
        }
      } else if (delta > 0) {
      _cart.add({
          'product_id': pId,
          'name': product['name'],
          'price': price,
          'cost': cost, // 🟢 FIX CRITIQUE: Injecter le coût pour que le bénéfice soit juste !
          'qty': delta,
          'variant_id': null,
          'unit': product['unit'] ?? 'u',
          'image': product['base_image_path'],
          'vat_percent': double.tryParse(product['vat_percent']?.toString() ?? '0') ?? 0.0,
        });
         HapticFeedback.mediumImpact();
      }
    });
    _api.saveCart('sales', _cart); 
  }

  void _onProductTap(dynamic product) {
    HapticFeedback.lightImpact();
    List variants = product['variants'] ?? [];
    if (variants.isNotEmpty) {
      _showVariantSelector(product, variants);
    } else {
      _showProductConfigurator(product);
    }
  }

void _showVariantSelector(dynamic product, List variants) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewPadding.bottom + 20),
          decoration: BoxDecoration(color: Theme.of(context).canvasColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(25))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Poignée de glissement
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 15), decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
              Text("Choisir une variante pour ${product['name']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
              const SizedBox(height: 15),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: variants.map((v) {
                      String optLabel = v['sku'] ?? 'Variante';
                      try {
                        if (v['options'] != null) {
                          Map<String, dynamic> opts = v['options'] is String ? jsonDecode(v['options']) : v['options'];
                          if (opts.isNotEmpty) {
                            optLabel = opts.entries.map((e) => "${e.key}: ${e.value}").join(' | ');
                          }
                        }
                      } catch(e) {}

                      final vStock = double.tryParse(v['stock']?.toString() ?? '0') ?? 0;
                      final isLowV = vStock <= 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isLowV ? Colors.red.withOpacity(0.3) : Colors.grey.withOpacity(0.15)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.style, color: Colors.orange, size: 20),
                          ),
                          title: Text(optLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("${v['price']} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14)),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isLowV ? Colors.red.withOpacity(0.15) : Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text("Qté: ${vStock.toInt()}", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLowV ? Colors.red : Colors.green)),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Map<String, dynamic> variantProduct = Map.from(product);
                            variantProduct['id'] = product['id']; 
                            variantProduct['variant_id'] = v['id'];
                            variantProduct['name'] = "${product['name']} ($optLabel)";
                            variantProduct['price'] = v['price'];
                            variantProduct['stock'] = v['stock'];
                            _showProductConfigurator(variantProduct, isVariant: true);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              )
            ],
          ),
        ),
      )
    );
  }

 void _showProductConfigurator(dynamic product, {bool isVariant = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddToCartSheet(
        product: product,
        enableTva: _enableTva,
        allowNegativeStock: _allowNegativeStock,
        onAdd: (qty, price, note) {
           _addToCart(product, qty, price, isVariant ? product['variant_id'] : null);
        },
      ),
    );
  }

  void _addToCart(dynamic product, double qty, double price, dynamic variantId) {
    final int pId = int.tryParse(product['id'].toString()) ?? 0;
    final double cost = double.tryParse(product['cost'].toString()) ?? 0.0; // 🟢 FIX CRITIQUE: Récupérer le coût

    setState(() {
      final index = _cart.indexWhere((item) => 
          item['product_id'] == pId && 
          item['variant_id'] == variantId &&
          item['price'] == price
      );
      
      if (index >= 0) {
        _cart[index]['qty'] += qty;
      } else {
       _cart.add({
          'product_id': pId,
          'name': product['name'],
          'price': price,
          'cost': cost, // 🟢 FIX CRITIQUE: Injecter le coût
          'qty': qty,
          'variant_id': variantId,
          'unit': product['unit'] ?? 'u',
          'image': product['base_image_path'],
          'vat_percent': double.tryParse(product['vat_percent']?.toString() ?? '0') ?? 0.0,
        });
      }
    });
    _api.saveCart('sales', _cart);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("${qty.toStringAsFixed(0)} x ${product['name']} ajouté!"), 
      duration: const Duration(milliseconds: 800),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.green,
    ));
  }

  void _showCheckoutSheet() async {
    if (_cart.isEmpty) return;
    if (_isCheckoutOpen) return; // 🟢 FIX: Vérouille contre l'ouverture multiple
    _isCheckoutOpen = true;

    // 🔐 CHANTIER 4 : Vérifier que la session de caisse est ouverte AVANT de permettre le paiement
    try {
      final prefs = await SharedPreferences.getInstance();
      final assignedRegId = prefs.getInt('assigned_register_id');

      if (assignedRegId != null) {
        final registers = await _api.getRegisters();
        final myReg = registers.firstWhere(
          (r) => r['id'].toString() == assignedRegId.toString(),
          orElse: () => {},
        );

        if (myReg.isNotEmpty) {
          // Vérifier si la caisse requiert une session ET si la session est fermée
          final hasSession = myReg['has_session'] ?? 1;
          final activeSessionId = myReg['active_session_id'];

          if (hasSession == 1 && activeSessionId == null) {
            if (!mounted) {
              _isCheckoutOpen = false;
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text("Opération refusée. Veuillez ouvrir votre session de caisse dans le menu Multi-Caisse.")),
                  ],
                ),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
            _isCheckoutOpen = false;
            return; // ❌ BLOQUÉ : Session fermée
          }
        }
      }
    } catch (e) {
      // En cas d'erreur réseau, on laisse passer (mode offline)
      debugPrint("⚠️ Vérification session caisse échouée (mode offline) : $e");
    }

    if (!mounted) {
      _isCheckoutOpen = false;
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CheckoutSheet(
        cart: _cart, 
        clients: _clients,
        selectedClientId: _selectedClientId,
        selectedClientName: _selectedClientName,
        onUpdateCart: (updatedCart) {
          setState(() => _cart = updatedCart);
          _api.saveCart('sales', updatedCart); // 🚀 Persist panier
        },
                  onConfirm: (note, clientId, clientName, paidAmount, paymentType, discount, tva, timbre, ht, isReturn) =>
                      _processSale(note, clientId, clientName, paidAmount, paymentType, discount, tva, timbre, ht, isReturn),
        onCreateClient: (name, phone) {}, 
      ),
    );

    _isCheckoutOpen = false; // 🟢 FIX: Libère le verrou uniquement quand on quitte le panier
  }

Future<void> _processSale(String? note, int? clientId, String clientName, double paidAmount, String paymentType, double discount, double tvaAmount, double timbreAmount, double htAmount, bool isReturn) async {
    // 1. LA VRAIE RÉPARATION : Si le panier est vide (clic multiple), on s'arrête net.
    if (_cart.isEmpty) return;

    // 2. On fige les données à envoyer
    final itemsToSend = List<Map<String, dynamic>>.from(_cart);
    
    // 3. On VIDE LE PANIER IMMÉDIATEMENT. Un 2ème clic trouvera un panier vide.
    setState(() {
      _cart.clear(); 
    });
    
    Navigator.pop(context); // On ferme la modale

    double actualTva = _enableTva ? tvaAmount : 0.0;
    double actualTimbre = _enableTimbre ? timbreAmount : 0.0;
    double netTotal = htAmount + actualTva + actualTimbre - discount; 

    try {
      await _api.sendComplexSaleOptimistic(
        netTotal, 
        itemsToSend, // On envoie la copie figée
        note: note, 
        clientId: clientId, 
        clientName: clientName,
        amountPaid: paidAmount,
        paymentType: paymentType,
        discount: discount,
        tva: actualTva,
        timbre: actualTimbre,
        ht: htAmount,
        isReturn: isReturn,
      );

      if (mounted) {
        await _api.clearCart('sales'); // Nettoie le cache SQLite
        setState(() {
          _selectedClientId = null;
          _selectedClientName = "Client Comptoir";
          _searchController.clear();
          _activeSmartFilter = 'none';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Vente enregistrée !"), backgroundColor: Colors.green));
      }
    } catch (e) {
       // En cas de crash inattendu, on restaure le panier pour ne rien perdre
       if(mounted) setState(() => _cart = itemsToSend);
    }
}
  double get _total {
    double t = 0;
    for(var i in _cart) {
      double ht = i['price'] ?? 0;
      double vat = _enableTva ? (i['vat_percent'] ?? 0) : 0;
      t += ht * (1 + (vat / 100)) * i['qty'];
    }
    return t;
  }
  void _showFilterSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Widget buildChip(String label, bool isSelected, Function(bool) onSel) {
            return FilterChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: isSelected,
              onSelected: (val) { setSheetState(() => onSel(val)); setState(() { onSel(val); _applyFilters(); }); },
              backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
              selectedColor: AppColors.primary.withOpacity(0.2),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(color: isSelected ? AppColors.primary : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? AppColors.primary : Colors.transparent)),
            );
          }

          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E2C) : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(25))),
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Filtres", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton(onPressed: () { setSheetState(() { _selectedCategory = 'Tout'; _selectedSubCategory = 'Tout'; _activeSmartFilter = 'none'; _stockFilter = 'Tout'; }); setState(() { _selectedCategory = 'Tout'; _selectedSubCategory = 'Tout'; _activeSmartFilter = 'none'; _stockFilter = 'Tout'; _applyFilters(); }); }, child: const Text("Réinitialiser", style: TextStyle(color: Colors.red)))
                ]),
                const SizedBox(height: 15),
                const Text("Catégories", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 10),
                // 🟢 Une seule ligne horizontale élégante et compacte
                SizedBox(
                  height: 38,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(children: _categories.map((c) => buildChip(c, _selectedCategory == c, (v) { if (v) { _selectedCategory = c; _updateSubCategoryList(); } })).toList()),
                  ),
                ),
                if (_currentSubCategories.isNotEmpty) ...[
                  const SizedBox(height: 15),
                  const Text("Sous-catégories", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 38,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(children: _currentSubCategories.map((s) => buildChip(s, _selectedSubCategory == s, (v) { if (v) _selectedSubCategory = s; })).toList()),
                    ),
                  ),
                ],
                const SizedBox(height: 15),
                const Text("État du Stock", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(children: ['Tout', 'En Stock', 'Stock Bas', 'Rupture'].map((st) => buildChip(st, _stockFilter == st, (v) { if (v) _stockFilter = st; })).toList()),
                  ),
                ),
                const SizedBox(height: 15),
                const Text("Filtres rapides", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(children: [
                      buildChip("Récents", _activeSmartFilter == 'new', (v) => _activeSmartFilter = v ? 'new' : 'none'),
                      buildChip("Top Ventes", _activeSmartFilter == 'top', (v) => _activeSmartFilter = v ? 'top' : 'none'),
                      buildChip("Favoris", _activeSmartFilter == 'fav', (v) => _activeSmartFilter = v ? 'fav' : 'none'),
                      buildChip("Critique", _activeSmartFilter == 'low', (v) => _activeSmartFilter = v ? 'low' : 'none'),
                    ]),
                  ),
                ),
                const SizedBox(height: 30),
                // 🟢 SafeArea : pousse automatiquement le bouton au-dessus de la barre système Android
                SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity, height: 50, 
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
                      onPressed: () => Navigator.pop(ctx), 
                      child: const Text("Appliquer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    )
                  ),
                )
              ],
            ),
          );
        }
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      extendBody: true, // <-- Corrige la bande noire en bas
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 10, 20, 20), // <-- Corrige l'encoche
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C23) : Colors.white,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () { if (widget.onBack != null) widget.onBack!(); else Navigator.pop(context); },
                          child: CircleAvatar(backgroundColor: isDark ? Colors.white10 : Colors.grey[100], child: Icon(Icons.arrow_back_ios_new, size: 18, color: isDark ? Colors.white : Colors.black)),
                        ),
                        
                        Row(
                          children: [
                            Text("Nouvelle Vente", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: 0.5)),
                            StreamBuilder<void>(
                              stream: ApiService().onDataUpdated,
                              builder: (context, snapshot) {
                                final queueCount = ApiService().currentQueue.length;
                                if (queueCount == 0) return const SizedBox.shrink(); 
                                return GestureDetector(
                                  onTap: () => showModalBottomSheet(
                                    context: context, useRootNavigator: true, isScrollControlled: true,
                                    backgroundColor: Colors.transparent, builder: (_) => OfflineQueuePage(),
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.cloud_upload, color: Colors.white, size: 12),
                                        const SizedBox(width: 4),
                                        Text('$queueCount', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            ),
                          ],
                        ),

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text("${_cart.length}", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: GlassCard(
                            isDark: isDark,
                            borderRadius: 18,
                            padding: EdgeInsets.zero,
                            child: TextField(
                              controller: _searchController,
                              onChanged: (v) => _applyFilters(),
                              style: TextStyle(color: isDark ? Colors.white : Colors.black),
                              decoration: InputDecoration(
                                hintText: "Rechercher (Nom, Réf, Code)...",
                                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
                                  onPressed: _scanBarcode,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 🟢 BOUTON FILTRE UNIQUE
                        GestureDetector(
                          onTap: _showFilterSheet,
                          child: Container(
                            height: 52, width: 52,
                            decoration: BoxDecoration(
                              color: (_selectedCategory != 'Tout' || _activeSmartFilter != 'none' || _stockFilter != 'Tout') 
                                  ? AppColors.primary 
                                  : (isDark ? Colors.white10 : Colors.white),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!),
                            ),
                            child: Icon(
                              Icons.tune, 
                              color: (_selectedCategory != 'Tout' || _activeSmartFilter != 'none' || _stockFilter != 'Tout') 
                                  ? Colors.white 
                                  : (isDark ? Colors.white70 : Colors.grey[700])
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                  : _filteredProducts.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 10), const Text("Aucun produit", style: TextStyle(color: Colors.grey))]))
                    : ListView.builder(
                        key: const ValueKey('sales_product_list'),
                        padding: const EdgeInsets.fromLTRB(15, 15, 15, 200), // 🟢 CORRECTION : Padding augmenté à 200 pour libérer l'espace sous le panier !
                        physics: const BouncingScrollPhysics(),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (ctx, i) {
                          final p = _filteredProducts[i];
                          return KeyedSubtree(
                            key: ValueKey('sale_${p['id']}'),
                            child: _buildProductCard(p, isDark),
                          );
                        },
                      ),
              ),
            ],
          ),
         if (_cart.isNotEmpty)
            Positioned(
              bottom: 12, left: 16, right: 16, // 🟢 Ajusté parfaitement tout en bas de l'écran
              child: SafeArea(
                child: GestureDetector(
                  onTap: _showCheckoutSheet,
                  child: Container(
                    height: 75,
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("${_cart.length} Articles", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Text(NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2).format(_total), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                          child: const Row(
                            children: [
                              Text("VOIR PANIER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              SizedBox(width: 8),
                              Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 18),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

Widget _buildProductCard(dynamic p, bool isDark) {
    final stock = double.tryParse(p['stock'].toString()) ?? 0;
    double htPrice = double.tryParse(p['price'].toString()) ?? 0;
    double vat = double.tryParse(p['vat_percent']?.toString() ?? '0') ?? 0;
    final price = _enableTva && vat > 0 ? htPrice * (1 + (vat / 100)) : htPrice;
    final minStock = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5;
    final isLow = stock <= minStock;
    final packing = double.tryParse(p['packing']?.toString() ?? '1') ?? 1;
    final unit = p['unit'] ?? 'u';
    final hasVariants = (p['variants'] is List && (p['variants'] as List).isNotEmpty);
    
    final int pId = int.tryParse(p['id'].toString()) ?? 0;
    
    final qtyInCart = !hasVariants ? _getQtyInCart(pId) : 0.0;
    final isInCart = qtyInCart > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _onProductTap(p),
        child: GlassCard(
          isDark: isDark,
          padding: const EdgeInsets.all(12),
          borderRadius: 20,
          borderColor: isInCart ? Colors.green.withOpacity(0.5) : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Builder(
                  builder: (context) {
                    final cleanUrl = ApiService.getCleanImageUrl(p['base_image_path']);
                    return SizedBox(
                      width: 65, height: 70,
                      child: Stack(
                        children: [
                          Container(
                            width: 65, height: 55,
                            decoration: BoxDecoration(
                              color: isLow ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.05), 
                              borderRadius: BorderRadius.circular(15),
                              image: cleanUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(cleanUrl),
                                      fit: BoxFit.cover
                                    )
                                  : null
                            ),
                            child: cleanUrl == null
                              ? Center(child: Icon(hasVariants ? FontAwesomeIcons.layerGroup : FontAwesomeIcons.dolly, color: isLow ? Colors.red : Colors.orange, size: 22))
                              : null,
                          ),
                          // 🟢 STOCK EN GROS — toujours visible
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: isLow ? Colors.red : (isDark ? const Color(0xFF2A2A3E) : Colors.white),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isLow ? Colors.red : (isDark ? Colors.white24 : Colors.grey.shade300), width: 0.5),
                              ),
                              child: Text(
                                "${stock.toInt()}",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: isLow ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(p['name'] ?? 'Inconnu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (p['ref'] != null && p['ref'].toString().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 5),
                              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                              child: Text(p['ref'], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
                            ),
                          Expanded(
                            child: Text("${p['category'] ?? ''}", style: TextStyle(color: Colors.grey[500], fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _buildBadge("Unit: $unit", Colors.blue),
                          if (packing > 1) _buildBadge("Colis: ${packing.toInt()}", Colors.purple),
                        ],
                      )
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${price.toStringAsFixed(0)} DA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                        Text(_enableTva ? "TTC" : "HT", style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                      ],
                    ),
                    const SizedBox(height: 6),
                    hasVariants 
                    ? Container(
                        width: 35, height: 35,
                        decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
                      )
                    : (isInCart 
                        ? Container(
                            height: 35,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10)
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _quickUpdateCart(p, -1),
                                  child: Container(width: 30, color: Colors.transparent, child: const Icon(Icons.remove, color: Colors.white, size: 16)),
                                ),
                                Text("${qtyInCart.toInt()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                GestureDetector(
                                  onTap: () => _quickUpdateCart(p, 1),
                                  child: Container(width: 30, color: Colors.transparent, child: const Icon(Icons.add, color: Colors.white, size: 16)),
                                ),
                              ],
                            ),
                          )
                        : GestureDetector(
                            onTap: () => _quickUpdateCart(p, 1),
                            child: Container(
                              width: 35, height: 35,
                              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.add, color: AppColors.primary, size: 24),
                            ),
                          )
                      )
                  ],
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockFilterRow(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['Tout', 'En Stock', 'Stock Bas', 'Rupture'].map((filter) {
          final isSelected = _stockFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (bool selected) {
                if (selected) {
                  setState(() {
                    _stockFilter = filter;
                    _applyFilters();
                  });
                }
              },
              backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), 
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20), 
                side: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!)
              ),
              elevation: 0,
            ),
          );
        }).toList(),
      ),
    );
  }

  // 🟢 FONCTION D'EXPULSION AUTOMATIQUE
  void _forceLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => ActivationPage(
          toggleTheme: () {},
          onThemeModeChanged: (_) {},
          onLanguageChanged: (_) {},
        )), 
        (route) => false
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⚠️ Session expirée : Votre compte a été modifié ou désactivé par l\'administrateur. Veuillez vous reconnecter.'),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 5),
      ));
    }
  }

  void _forceLock() {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (ctx) => const AppLockedPage()), 
        (route) => false
      );
    }
  }
} // 🟢 L'ACCOLADE MANQUANTE ÉTAIT ICI ! ELLE RÉPARE LES 50 ERREURS !
Widget _buildBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.3), width: 0.5)),
      child: Text(text, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }
class AddToCartSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final bool enableTva; 
  final bool allowNegativeStock; // 📦 Contrôle du stock négatif
  final Function(double, double, String?) onAdd;

  const AddToCartSheet({super.key, required this.product, required this.enableTva, this.allowNegativeStock = false, required this.onAdd});

  @override
  State<AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends State<AddToCartSheet> {
  double _qty = 1;
  late double _selectedPriceHT; 
  late String _selectedPriceType; 
  final TextEditingController _qtyController = TextEditingController();
  bool _isAdding = false; // 🟢 VERROU ANTI-CLIC FOU

  double get _vatPercent => widget.enableTva ? (double.tryParse(widget.product['vat_percent']?.toString() ?? '0') ?? 0.0) : 0.0;
  double get _multiplier => 1 + (_vatPercent / 100);

  @override
  void initState() {
    super.initState();
    _selectedPriceHT = double.tryParse(widget.product['price'].toString()) ?? 0;
    _selectedPriceType = 'detail';
    _qtyController.text = "1";
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _updateQty(double v) {
    setState(() {
      _qty = v;
      _qtyController.text = _qty % 1 == 0 ? _qty.toInt().toString() : _qty.toString();
    });
  }

  void _increment() => _updateQty(_qty + 1);
  void _decrement() { if (_qty > 1) _updateQty(_qty - 1); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.product;
    
    final pDetailHT = double.tryParse(p['price'].toString()) ?? 0;
    final pSemiHT = double.tryParse(p['price_semi']?.toString() ?? '0') ?? 0;
    final pGrosHT = double.tryParse(p['price_whol']?.toString() ?? '0') ?? 0;
    
    final displayTotal = (_selectedPriceHT * _multiplier) * _qty; 

return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView( // 🟢 CORRIGE L'OVERFLOW ROUGE 
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['name'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                        Text("Stock: ${p['stock']} ${p['unit'] ?? ''}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  Text("${displayTotal.toStringAsFixed(0)} DA", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 20),
              
              const Text("TARIFICATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildPriceOption("Détail", pDetailHT, 'detail', isDark),
                  if (pSemiHT > 0) _buildPriceOption("Semi-Gros", pSemiHT, 'semi', isDark),
                  if (pGrosHT > 0) _buildPriceOption("Gros", pGrosHT, 'gros', isDark),
                ],
              ),
              const SizedBox(height: 20),

              const Text("QUANTITÉ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 10),
              Row(
                children: [
                   Expanded(
                     child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(onPressed: _decrement, icon: const Icon(Icons.remove)),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _qtyController,
                              textAlign: TextAlign.center,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
                              decoration: const InputDecoration(border: InputBorder.none),
                              onChanged: (val) {
                                if(val.isNotEmpty) {
                                  setState(() => _qty = double.tryParse(val) ?? 1);
                                }
                              },
                            ),
                          ),
                          IconButton(onPressed: _increment, icon: const Icon(Icons.add, color: AppColors.primary)),
                        ],
                      ),
                     ),
                   ),
                   const SizedBox(width: 10),
                   _buildQuickQtyBtn(5, isDark),
                   const SizedBox(width: 5),
                   _buildQuickQtyBtn(10, isDark),
                ],
              ),
              const SizedBox(height: 20),
              
            SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    if (_isAdding) return; // 🟢 Empêche le double-clic instantané
                    
                    // 📦 VÉRIFICATION STOCK NÉGATIF
                    if (!widget.allowNegativeStock) {
                      final stock = double.tryParse(widget.product['stock']?.toString() ?? '0') ?? 0;
                      if (_qty > stock) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text("⛔ Stock insuffisant ! Disponible: ${stock.toStringAsFixed(0)} — Demandé: ${_qty.toStringAsFixed(0)}"),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 3),
                        ));
                        return;
                      }
                    }
                    
                    setState(() => _isAdding = true);
                    Navigator.pop(context);
                    widget.onAdd(_qty, _selectedPriceHT, null); 
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5
                  ),
                  child: const Text("AJOUTER AU PANIER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildQuickQtyBtn(double val, bool isDark) {
    return GestureDetector(
      onTap: () => _updateQty(_qty + val),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12)
        ),
        child: Text("+$val", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
      ),
    );
  }

  Widget _buildPriceOption(String label, double priceHT, String type, bool isDark) {
    final isSelected = _selectedPriceType == type;
    final displayPrice = priceHT * _multiplier; 
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _selectedPriceType = type; _selectedPriceHT = priceHT; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.1) : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent, width: 2)
          ),
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: isSelected ? AppColors.primary : Colors.grey)),
              Text("${displayPrice.toInt()}", style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? AppColors.primary : (isDark ? Colors.white : Colors.black))),
            ],
          ),
        ),
      ),
    );
  }
}

class CheckoutSheet extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final List<dynamic> clients;
  final int? selectedClientId;
  final String? selectedClientName; 
  final Function(List<Map<String, dynamic>>) onUpdateCart;
  final Function(String?, int?, String, double, String, double, double, double, double, bool) onConfirm; 
  final Function(String, String) onCreateClient;

  const CheckoutSheet({
    super.key, 
    required this.cart,
    required this.clients, 
    required this.onUpdateCart,
    required this.onConfirm,
    required this.onCreateClient,
    this.selectedClientId,
    this.selectedClientName,
  });

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  late int? _selId;
  late String _selName;
  double _selBalance = 0.0; // 🧠 NOUVEAU: Stocke la dette du client
  final String _note = "";
  final TextEditingController _paidController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  
  late List<Map<String, dynamic>> _localCart;
  double _discount = 0.0;
  
  bool _enableTva = false;
  bool _enableTimbre = false;
  bool _isReturn = false;
  bool _isProcessingValidation = false; // 🟢 Anti double-clic sur VALIDER


  @override
  void initState() {
    super.initState();
    _selId = widget.selectedClientId;
    _selName = widget.selectedClientName ?? "Client Comptoir";
    _localCart = List.from(widget.cart);
    _loadTaxesSettings();
    _calculateInitialBalance(); // 🟢 NOUVEAU
    _updateTotalAndField();
  }

  // 🧠 NOUVEAU : Récupère la dette initiale
  void _calculateInitialBalance() {
    if (_selId != null && widget.clients.isNotEmpty) {
      final client = widget.clients.firstWhere((c) => c['id'].toString() == _selId.toString(), orElse: () => null);
      if (client != null) {
        _selBalance = double.tryParse(client['balance']?.toString() ?? '0') ?? 0.0;
      }
    }
  }

  @override
  void dispose() {
    _paidController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _loadTaxesSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _enableTva = prefs.getBool('enable_tva') ?? false;
        _enableTimbre = prefs.getBool('enable_timbre') ?? false;
      });
      _updateTotalAndField();
    }
  }

  double get _grossTotal => _localCart.fold(0, (sum, item) => sum + ((item['price'] ?? 0.0) * (item['qty'] ?? 1.0)));
  
  double get _tvaAmount {
    if (!_enableTva) return 0.0;
    double htNet = _grossTotal - _discount;
    if (htNet <= 0) return 0.0;
    double totalVat = 0;
    for (var item in _localCart) {
      double qty = (item['qty'] ?? 1.0).toDouble();
      double priceHT = (item['price'] ?? 0.0).toDouble();
      double vatRate = (item['vat_percent'] ?? 0.0).toDouble();
      if (vatRate > 0) {
        double proportionNet = htNet / _grossTotal;
        double ligneHtNet = (priceHT * qty) * proportionNet;
        totalVat += (ligneHtNet * (vatRate / 100));
      }
    }
    return double.parse(totalVat.toStringAsFixed(2));
  }

  double get _timbreAmount {
    if (!_enableTimbre) return 0.0;
    double ttc = (_grossTotal - _discount) + _tvaAmount;
    if (ttc <= 0) return 0.0;
    double tranches = (ttc / 100).ceilToDouble();
    double t = 0;
    if (ttc <= 30000) t = tranches * 1.0;
    else if (ttc <= 100000) t = tranches * 1.5;
    else t = tranches * 2.0;
    return t.clamp(5.0, 10000.0);
  }

  double get _netTotal => (_grossTotal - _discount + _tvaAmount + _timbreAmount).clamp(0.0, double.infinity);

 void _updateTotalAndField() {
    double defaultPaid = _netTotal;
    
    // 🧠 INTELLIGENCE ABSOLUE : Si c'est un retour et que le client a une dette, 
    // la dette absorbe l'argent du retour en priorité !
    if (_isReturn && _selId != null && _selBalance > 0) {
        defaultPaid = _netTotal - _selBalance;
        if (defaultPaid < 0) defaultPaid = 0; // La dette annule complètement le remboursement cash
    }

    // On met à jour le champ seulement s'il est vide, ou s'il contenait l'ancien total exact
    if (_paidController.text.isEmpty || double.tryParse(_paidController.text) == _grossTotal || double.tryParse(_paidController.text) == _netTotal || _isReturn) {
       _paidController.text = defaultPaid.toStringAsFixed(2);
    }
    if (mounted) setState(() {});
  }

  void _onDiscountChanged(String val) {
     setState(() {
         _discount = double.tryParse(val) ?? 0.0;
         if (_discount > _grossTotal) _discount = _grossTotal;
         _paidController.text = _netTotal.toStringAsFixed(2);
     });
  }

  void _updateQty(int index, double newQty) {
    if (newQty <= 0) return;
    setState(() {
      _localCart[index]['qty'] = newQty;
      _paidController.text = _netTotal.toStringAsFixed(2);
    });
    widget.onUpdateCart(_localCart);
  }

  void _removeItem(int index) {
    setState(() {
      _localCart.removeAt(index);
      _paidController.text = _netTotal.toStringAsFixed(2);
    });
    widget.onUpdateCart(_localCart);
    if (_localCart.isEmpty) Navigator.pop(context);
  }

  // 🛠️ MODULE 5 : Édition du prix unitaire dans le panier
  void _updatePrice(int index, double newPrice) {
    setState(() {
      _localCart[index]['price'] = newPrice;
      _paidController.text = _netTotal.toStringAsFixed(2);
    });
    widget.onUpdateCart(_localCart);
  }

void _validate() {
    if (_isProcessingValidation) return; 
    
    final textAmount = _paidController.text.replaceAll(',', '.').trim();
    final paidAmount = double.tryParse(textAmount) ?? 0;
    final remaining = _netTotal - paidAmount; 

    // 🟢 SÉCURITÉ : Forcer la sélection du client en cas de RETOUR ou de CRÉDIT
    if ((remaining > 1.0 || _isReturn) && _selId == null) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text("⚠️ CLIENT OBLIGATOIRE pour un retour ou un crédit !"), 
           backgroundColor: Colors.red,
           duration: Duration(seconds: 3),
         )
       );
       return; 
    }

    String type = 'cash';
    if (remaining > 0.1) {
       type = 'credit'; 
    } else {
       type = 'cash'; 
    }

    double finalDiscount = double.tryParse(_discountController.text) ?? 0.0;

    // 🟢 Verrouillage avant l'envoi
    setState(() => _isProcessingValidation = true);
    
    widget.onConfirm(_note.isEmpty ? null : _note, _selId, _selName, paidAmount, type, finalDiscount, _tvaAmount, _timbreAmount, _grossTotal, _isReturn);
    
    // 🟢 Relâche le verrou après 2s en cas de problème
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isProcessingValidation = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentPaid = double.tryParse(_paidController.text) ?? 0;
    final remaining = _netTotal - currentPaid;
    final isCredit = remaining > 0.1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // 🟢 DRAG HANDLE
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),
            // 🟢 HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Text("Panier", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                 Row(
                   children: [
                     // 🗑️ BOUTON VIDER LE PANIER
                     IconButton(
                       icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 22),
                       tooltip: "Vider le panier",
                       onPressed: () {
                         showDialog(
                           context: context,
                           builder: (ctx) => AlertDialog(
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                             title: const Text("🗑️ Vider le panier ?"),
                             content: const Text("Tous les articles seront supprimés. Cette action est irréversible."),
                             actions: [
                               TextButton(
                                 onPressed: () => Navigator.pop(ctx),
                                 child: const Text("Annuler"),
                               ),
                               ElevatedButton(
                                 onPressed: () async {
                                   Navigator.pop(ctx);
                                   await ApiService().clearCart('sales'); // 🚀 Vider le panier SQLite
                                   setState(() => _localCart.clear());
                                   widget.onUpdateCart(_localCart);
                                   if (mounted) Navigator.pop(context); // Ferme le sheet
                                 },
                                 style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                 child: const Text("Vider", style: TextStyle(color: Colors.white)),
                               ),
                             ],
                           ),
                         );
                       },
                     ),
                     Column(
                       crossAxisAlignment: CrossAxisAlignment.end,
                       children: [
                         if(_discount > 0)
                           Text("${_grossTotal.toStringAsFixed(0)} DA", style: const TextStyle(fontSize: 14, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                         Text("${_netTotal.toStringAsFixed(2)} DA", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange)),
                       ],
                      ),
                   ],
                ),
             ],
            ),
            ),
            const SizedBox(height: 12),
  
            // 🟢 LISTE DU PANIER
            Expanded(
              child: _localCart.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_cart_outlined, size: 50, color: Colors.grey.withValues(alpha: 0.3)),
                          const SizedBox(height: 10),
                          const Text("Panier vide", style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _localCart.length,
                      itemBuilder: (ctx, i) {
                        return CartItemCard(
                          item: _localCart[i],
                          index: i,
                          isDark: isDark,
                          onUpdateQty: _updateQty,
                          onRemove: _removeItem,
                          onUpdatePrice: _updatePrice, // 🛠️ MODULE 5 : Édition prix
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
        ),
        child: SafeArea(
          bottom: true,
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🟢 LIGNE 1 : Client + Mode Retour (Fusionnés)
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: GestureDetector(
                        onTap: () => _openClientSelector(isDark),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.person, color: Colors.blue, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_selName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _selId != null ? Colors.blue : (isDark ? Colors.white : Colors.black)), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              Icon(Icons.arrow_drop_down, color: Colors.grey[500]),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _isReturn = !_isReturn),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(color: _isReturn ? Colors.red.withOpacity(0.1) : (isDark ? Colors.white10 : Colors.grey[100]), borderRadius: BorderRadius.circular(12), border: Border.all(color: _isReturn ? Colors.red : Colors.transparent)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_return, size: 16, color: _isReturn ? Colors.red : Colors.grey),
                              const SizedBox(width: 6),
                              Text("Retour", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _isReturn ? Colors.red : Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 🟢 LIGNE 2 : Remise + Montant Versé (Même ligne !)
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _discountController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                        onChanged: _onDiscountChanged,
                        decoration: InputDecoration(
                          labelText: "Remise (DA)", labelStyle: const TextStyle(fontSize: 12),
                          filled: true, fillColor: Colors.red.withOpacity(0.1),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 6,
                      child: TextField(
                        controller: _paidController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w900, fontSize: 18),
                        onChanged: (v) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: "Montant Versé (DA)", labelStyle: const TextStyle(fontSize: 12),
                          filled: true, fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.green.withOpacity(0.1),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),

                if (isCredit) ...[
                  const SizedBox(height: 6),
                  Text("⚠️ Reste à payer (Dette) : ${NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2).format(remaining)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
                const SizedBox(height: 10),

                // 🟢 LIGNE 3 : Boutons intelligents (CASH / AVOIR)
                Row(
                  children: [
                    Expanded(flex: 2, child: _buildQuickPayBtn(_isReturn ? "CASH" : "TOUT", Colors.green, () => setState(() => _paidController.text = _netTotal.toStringAsFixed(2)))),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: _buildQuickPayBtn(_isReturn ? "AVOIR" : "0 (CRÉD)", Colors.red, () => setState(() => _paidController.text = "0"))),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: SizedBox(
                        height: 45,
                       child: ElevatedButton(
                          onPressed: _validate, 
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isReturn ? (isCredit ? Colors.orange : Colors.red) : (isCredit ? Colors.orange : Colors.green), 
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: EdgeInsets.zero
                          ),
                          child: Text(
                            _isReturn 
                                ? (isCredit ? "GARDER EN AVOIR" : "REMBOURSER CASH") 
                                : (isCredit ? "CRÉDIT" : "ENCAISSER"), 
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

void _openClientSelector(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchableSelectModal(
        title: "Sélectionner un client",
        icon: Icons.person_search,
        themeColor: Colors.blue,
        items: widget.clients,
        noneLabel: "Client Comptoir (Anonyme)",
        onSelected: (selectedItem) {
          setState(() {
            if (selectedItem == null) {
              _selId = null;
              _selName = "Client Comptoir";
              _selBalance = 0.0;
            } else {
              _selId = int.tryParse(selectedItem['id'].toString());
              _selName = selectedItem['name']?.toString() ?? 'Inconnu';
              _selBalance = double.tryParse(selectedItem['balance']?.toString() ?? '0') ?? 0.0;
            }
            _updateTotalAndField(); // 🟢 ACTUALISE LE MONTANT DU RETOUR DYNAMIQUEMENT
          });
        },
      ),
    );
  }

  Widget _buildQuickPayBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 45,
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
        child: Center(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11))),
      ),
    );
  }
}