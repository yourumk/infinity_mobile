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
import '../widgets/searchable_select_modal.dart';
import 'offline_queue_page.dart';
import 'dart:convert';

class PurchasesPage extends StatefulWidget {
  final VoidCallback? onBack;

  const PurchasesPage({super.key, this.onBack});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription? _dataSubscription;
  DateTime? _lastRefreshTime;

  List<dynamic> _allProducts = [];
  List<dynamic> _filteredProducts = [];
  List<String> _categories = ['Tout'];
  List<String> _subCategories = [];
  List<String> _currentSubCategories = [];

  List<dynamic> _suppliers = [];

  String _selectedCategory = 'Tout';
  String _selectedSubCategory = 'Tout';
  String _activeSmartFilter = 'none';
  String _stockFilter = 'all'; // 🟢 TÂCHE 4 : Filtre stock (all / in_stock / low_stock / out_of_stock)

  List<Map<String, dynamic>> _cart = [];

  // Variables pour le checkout
  int? _selectedSupplierId;
  String _selectedSupplierName = "Fournisseur Divers";

  bool _isLoading = true;
  bool _isSending = false;
  Timer? _debounce;

  bool _enableTva = false;
  bool _enableTimbre = false;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _enableTva = prefs.getBool('enable_tva') ?? false;
        _enableTimbre = prefs.getBool('enable_timbre') ?? false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _restoreCart();
    _api.startAutoSync();
    
    // 🟢 FIX : Chargement forcé et prioritaire des tiers
    Future.microtask(() async {
        await _loadData();
        // Recharge spécifique des fournisseurs si vide
        if (_suppliers.isEmpty) {
            final tiers = await _api.getTiersList('suppliers', '');
            if (mounted) setState(() => _suppliers = tiers);
        }
    });

    _dataSubscription = _api.onDataUpdated.listen((_) {
      final now = DateTime.now();
      if (_lastRefreshTime == null || now.difference(_lastRefreshTime!).inSeconds > 2) {
        _lastRefreshTime = now;
        if (mounted) _loadData(silent: true);
      }
    });
  }

  Future<void> _restoreCart() async {
    final saved = await _api.loadCart('purchases');
    if (saved.isNotEmpty && mounted) {
      setState(() => _cart = saved);
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
        _api.getTiersList('suppliers', '')
      ]);

      final productsData = results[0] as Map<String, dynamic>;
      final suppliersData = results[1] as List<dynamic>;

      if (mounted) {
        setState(() {
          _allProducts = productsData['products'] ?? [];
         List<dynamic> cats = productsData['categories'] ?? [];
var uniqueCats = cats.map((e) => e.toString())
    .where((c) => c.toLowerCase() != 'tout')
    .toSet()
    .toList();
_categories = ['Tout', ...uniqueCats];

          Set<String> subSet = {};
          for(var p in _allProducts) {
             if(p['sub_category'] != null && p['sub_category'].toString().isNotEmpty) {
               subSet.add(p['sub_category'].toString());
             }
          }
          _subCategories = subSet.toList();
          _suppliers = suppliersData;
          _isLoading = false;
          _updateSubCategoryList();
          _applyFilters();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
        // 🟢 FIN DE LA CORRECTION

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
          final stock = double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
          final min = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5;
          return stock <= min;
        }).toList();
      }

      // 🟢 TÂCHE 4 : Filtre par niveau de stock
      if (_stockFilter == 'in_stock') {
        temp = temp.where((p) {
          final stock = double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
          return stock > 0;
        }).toList();
      } else if (_stockFilter == 'low_stock') {
        temp = temp.where((p) {
          final stock = double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
          final min = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5;
          return stock > 0 && stock <= min;
        }).toList();
      } else if (_stockFilter == 'out_of_stock') {
        temp = temp.where((p) {
          final stock = double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
          return stock <= 0;
        }).toList();
      }

      if (_activeSmartFilter == 'top') {
         temp.sort((a, b) => (double.tryParse(b['total_sold'].toString()) ?? 0).compareTo(double.tryParse(a['total_sold'].toString()) ?? 0));
      } else if (_activeSmartFilter == 'new') {
         temp.sort((a, b) => (int.tryParse(b['id'].toString()) ?? 0).compareTo(int.tryParse(a['id'].toString()) ?? 0));
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

    setState(() {
      final index = _cart.indexWhere((item) => item['product_id'] == pId && item['variant_id'] == null);
      
      if (index >= 0) {
        double newQty = _cart[index]['qty'] + delta;
        if (newQty <= 0) {
          _cart.removeAt(index);
        } else {
          _cart[index]['qty'] = newQty;
        }
      } else if (delta > 0) {
        final cost = double.tryParse(product['cost'].toString()) ?? 0;
      _cart.add({
          'product_id': pId,
          'name': product['name'],
          'cost': cost,
          'qty': delta,
          'variant_id': null,
          'unit': product['unit'] ?? 'u',
          'image': product['base_image_path'],
          'vat_percent': double.tryParse(product['vat_percent']?.toString() ?? '0') ?? 0.0,
        });
        HapticFeedback.mediumImpact();
      }
    });
    _api.saveCart('purchases', _cart); // 🚀 Persist panier
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
    final vat = double.tryParse(product['vat_percent']?.toString() ?? '0') ?? 0;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Theme.of(context).canvasColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(25))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Variante pour ${product['name']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
            const SizedBox(height: 15),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: variants.map((v) {
                    double vHt = double.tryParse(v['cost']?.toString() ?? product['cost'].toString()) ?? 0;
                    
                    // Décodage des options pour un bel affichage
                    String optLabel = v['sku'] ?? 'Variante';
                    try {
                      if (v['options'] != null) {
                        Map<String, dynamic> opts = v['options'] is String ? jsonDecode(v['options']) : v['options'];
                        if (opts.isNotEmpty) {
                          optLabel = opts.entries.map((e) => "${e.key}: ${e.value}").join(' | ');
                        }
                      }
                    } catch(e) {}

                    return ListTile(
                      leading: const Icon(Icons.style, color: Colors.orange),
                      title: Text(optLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Text("Coût HT: ${vHt.toStringAsFixed(0)} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                      subtitle: Text("Stock actuel: ${v['stock']}"),
                      onTap: () {
                        Navigator.pop(context);
                        Map<String, dynamic> variantProduct = Map.from(product);
                        variantProduct['id'] = product['id']; 
                        variantProduct['variant_id'] = v['id']; // CRUCIAL
                        variantProduct['name'] = "${product['name']} ($optLabel)";
                        variantProduct['cost'] = vHt;
                        variantProduct['stock'] = v['stock'];
                        _showProductConfigurator(variantProduct, isVariant: true);
                      },
                    );
                  }).toList(),
                ),
              ),
            )
          ],
        ),
      )
    );
  }

  void _showProductConfigurator(dynamic product, {bool isVariant = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddToSupplySheet(
        product: product,
        enableTva: _enableTva, // 🟢 ON PASSE LE RÉGLAGE TVA
        onAdd: (qty, cost) {
           _addToCart(product, qty, cost, isVariant ? product['variant_id'] : null);
        },
      ),
    );
  }

  void _addToCart(dynamic product, double qty, double cost, dynamic variantId) {
    final int pId = int.tryParse(product['id'].toString()) ?? 0;

    setState(() {
      final index = _cart.indexWhere((item) => item['product_id'] == pId && item['variant_id'] == variantId && item['cost'] == cost);
      
      if (index >= 0) {
        _cart[index]['qty'] += qty;
      } else {
       _cart.add({
          'product_id': pId,
          'name': product['name'],
          'cost': cost,
          'qty': qty,
          'variant_id': variantId,
          'unit': product['unit'] ?? 'u',
          'image': product['base_image_path'],
          'vat_percent': double.tryParse(product['vat_percent']?.toString() ?? '0') ?? 0.0,
        });
      }
    });
    _api.saveCart('purchases', _cart); // 🚀 Persist panier
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("${qty.toStringAsFixed(0)} x ${product['name']} ajouté!"), 
      duration: const Duration(milliseconds: 800),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.orange,
    ));
  }

  void _showCheckoutSheet() {
    if (_cart.isEmpty) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PurchaseCheckoutSheet(
        cart: _cart, 
        suppliers: _suppliers,
        // 🟢 FIX : On force le nom à null si aucun fournisseur n'est sélectionné
        selectedSupId: _selectedSupplierId,
        selectedSupName: (_selectedSupplierId == null) ? null : _selectedSupplierName, 
        onUpdateCart: (updatedCart) {
          setState(() => _cart = updatedCart);
          _api.saveCart('purchases', updatedCart); // 🚀 Persist panier
        },
        onCreateSupplier: (name, phone) async {
           final tempId = -1 * DateTime.now().millisecondsSinceEpoch;
           final newSup = {'id': tempId, 'name': name, 'phone': phone, 'balance': 0};
           setState(() {
             _suppliers.add(newSup);
             _selectedSupplierId = tempId;
             _selectedSupplierName = name;
           });
           await _api.createTier('supplier', newSup);
        },
        onConfirm: (note, supId, supName, paidAmount, paymentType, isReturn) {
             setState(() {
                 _selectedSupplierId = supId;
                 _selectedSupplierName = supName;
             });
             _processPurchase(note, supId, supName, paidAmount, paymentType, isReturn);
        },
      ),
    );
  }

  Future<void> _processPurchase(String? note, int? supId, String supName, double paidAmount, String paymentType, bool isReturn) async {
    Navigator.pop(context); 
    setState(() => _isSending = true);

    final prefs = await SharedPreferences.getInstance();
    bool enableTva = prefs.getBool('enable_tva') ?? false;
    bool enableTimbre = prefs.getBool('enable_timbre') ?? false;

    double brutHT = _cart.fold(0.0, (s, i) => s + ((i['cost'] ?? 0.0) * (i['qty'] ?? 1.0)));
    
    double tvaAmount = 0.0;
    if (enableTva) {
      for (var item in _cart) {
        double qty = (item['qty'] ?? 1.0).toDouble();
        double costHT = (item['cost'] ?? 0.0).toDouble();
        double vatRate = (item['vat_percent'] ?? 0.0).toDouble();
        if (vatRate > 0) tvaAmount += (costHT * qty) * (vatRate / 100);
      }
    }

    double timbreAmount = 0.0;
    if (enableTimbre) {
      double ttc = brutHT + tvaAmount;
      if (ttc > 0) {
        double tranches = (ttc / 100).ceilToDouble();
        if (ttc <= 30000) timbreAmount = tranches * 1.0;
        else if (ttc <= 100000) timbreAmount = tranches * 1.5;
        else timbreAmount = tranches * 2.0;
        timbreAmount = timbreAmount.clamp(5.0, 10000.0);
      }
    }

    double netTotal = brutHT + tvaAmount + timbreAmount;

    try {
      await _api.sendComplexPurchase(
        netTotal, 
        List.from(_cart),
        note: note, 
        supplierId: supId, 
        supplierName: supName,
        amountPaid: paidAmount,
        paymentType: paymentType,
        tva: tvaAmount,
        timbre: timbreAmount,
        ht: brutHT,
        discount: 0.0,
        isReturn: isReturn,
      );

      if (mounted) {
        setState(() {
          _isSending = false;
          _cart.clear();
          _selectedSupplierId = null;
          _selectedSupplierName = "Fournisseur Divers";
          _searchController.clear();
          _activeSmartFilter = 'none';
        });
        await _api.clearCart('purchases'); // 🚀 Vider le panier SQLite
        await _loadData(silent: true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Achat enregistré !"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
  }

  double get _total {
    double t = 0;
    for(var i in _cart) {
      double ht = i['cost'] ?? 0;
      double vat = _enableTva ? (i['vat_percent'] ?? 0) : 0;
      t += ht * (1 + (vat / 100)) * i['qty'];
    }
    return t;
  }

  Widget _buildSmartFilterBtn(String id, String label, IconData icon, Color color, bool isDark) {
    final bool isActive = _activeSmartFilter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeSmartFilter = isActive ? 'none' : id;
            _applyFilters();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? color : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isActive ? color : (isDark ? Colors.white10 : Colors.grey[300]!), width: 1),
            boxShadow: isActive ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : [],
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: isActive ? Colors.white : color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87))),
            ],
          ),
        ),
      ),
    );
  }

  // 🟢 TÂCHE 4 : Filtres de stock (Tout / En Stock / Stock Bas / Rupture)
  Widget _buildStockFilterRow(bool isDark) {
    final filters = [
      {'id': 'all', 'label': 'Tout', 'icon': Icons.apps, 'color': Colors.grey},
      {'id': 'in_stock', 'label': 'En Stock', 'icon': Icons.check_circle_outline, 'color': Colors.green},
      {'id': 'low_stock', 'label': 'Stock Bas', 'icon': Icons.warning_amber_rounded, 'color': Colors.orange},
      {'id': 'out_of_stock', 'label': 'Rupture', 'icon': Icons.cancel_outlined, 'color': Colors.red},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 8, 15, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: filters.map((f) {
            final isActive = _stockFilter == f['id'];
            final color = f['color'] as Color;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(f['icon'] as IconData, size: 14, color: isActive ? Colors.white : color),
                    const SizedBox(width: 6),
                    Text(f['label'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87))),
                  ],
                ),
                selected: isActive,
                onSelected: (selected) {
                  setState(() {
                    _stockFilter = selected ? (f['id'] as String) : 'all';
                    _applyFilters();
                  });
                },
                selectedColor: color,
                backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: isActive ? color : (isDark ? Colors.white10 : Colors.grey[300]!)),
                ),
                elevation: 0,
                pressElevation: 0,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 10, 20, 20),
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
                          // 🟢 FIX : On utilise d'abord la fonction de retour sécurisée si elle existe
                          onTap: () {
                            if (widget.onBack != null) {
                              widget.onBack!();
                            } else {
                              Navigator.pop(context);
                            }
                          },
                          child: CircleAvatar(
                            backgroundColor: isDark ? Colors.white10 : Colors.grey[100],
                            child: Icon(Icons.arrow_back_ios_new, size: 18, color: isDark ? Colors.white : Colors.black),
                          ),
                        ),
                        
                        Row(
                          children: [
                            Text("Nouvel Achat", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: 0.5)),
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
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1), 
                            borderRadius: BorderRadius.circular(20)
                          ),
                          child: Text(
                            "${_cart.length}",
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    GlassCard(
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
                            icon: const Icon(Icons.qr_code_scanner, color: Colors.orange),
                            onPressed: _scanBarcode,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildSmartFilterBtn('new', 'Récents', FontAwesomeIcons.clock, Colors.blue, isDark),
                          _buildSmartFilterBtn('low', 'Stock Bas', FontAwesomeIcons.triangleExclamation, Colors.red, isDark),
                          _buildSmartFilterBtn('top', 'Top Ventes', FontAwesomeIcons.fire, Colors.orange, isDark),
                          _buildSmartFilterBtn('fav', 'Favoris', FontAwesomeIcons.heart, Colors.pink, isDark),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: _categories.map((cat) {
                          final isSelected = _selectedCategory == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(cat),
                              selected: isSelected,
                              onSelected: (bool selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedCategory = cat;
                                    _updateSubCategoryList();
                                    _applyFilters();
                                  });
                                }
                              },
                              backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                              selectedColor: Colors.orange,
                              labelStyle: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                              checkmarkColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!)),
                              elevation: 0,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (_currentSubCategories.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: _currentSubCategories.map((sub) {
                              final isSelected = _selectedSubCategory == sub;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () {
                                     setState(() { _selectedSubCategory = sub; _applyFilters(); });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.orange.withOpacity(0.2) : Colors.transparent,
                                      border: Border.all(color: isSelected ? Colors.orange : Colors.grey.withOpacity(0.3)),
                                      borderRadius: BorderRadius.circular(15)
                                    ),
                                    child: Text(sub, style: TextStyle(fontSize: 11, color: isSelected ? Colors.orange : Colors.grey, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                  ],
                            ),
                          ),
                        ),
                      _buildStockFilterRow(isDark),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                  : _filteredProducts.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 10), const Text("Aucun produit", style: TextStyle(color: Colors.grey))]))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(15, 15, 15, 200), // 🟢 TÂCHE 2: Augmenté pour éviter chevauchement panier 
                        physics: const BouncingScrollPhysics(),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (ctx, i) => _buildProductCard(_filteredProducts[i], isDark),
                      ),
              ),
            ],
          ),
          if (_cart.isNotEmpty)
            Positioned(
              bottom: 105, left: 20, right: 20,
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
                            Text(NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(_total), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                          child: const Row(
                            children: [
                              Text("CONFIRMER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              SizedBox(width: 8),
                              Icon(Icons.check_circle, color: Colors.white, size: 18),
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
    final cost = double.tryParse(p['cost'].toString()) ?? 0; 
    double vat = double.tryParse(p['vat_percent']?.toString() ?? '0') ?? 0;
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
          borderColor: isInCart ? Colors.orange.withOpacity(0.5) : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Builder(
                  builder: (context) {
                    final cleanUrl = ApiService.getCleanImageUrl(p['base_image_path']);
                    return Container(
                      width: 70,
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
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(hasVariants ? FontAwesomeIcons.layerGroup : FontAwesomeIcons.dolly, color: isLow ? Colors.red : Colors.orange, size: 24),
                              if(stock > 0) ...[
                                const SizedBox(height: 5),
                                Text("${stock.toInt()}", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLow ? Colors.red : Colors.grey))
                              ]
                            ],
                          )
                        : null,
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
                          // 🟢 CORRECTION OVERFLOW HORIZONTAL (Expanded)
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
                        Text("${cost.toStringAsFixed(0)} DA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                        Text("Coût (HT)", style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                      ],
                    ),
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
                              color: Colors.orange,
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
                              child: const Icon(Icons.add, color: Colors.orange, size: 24),
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

  Widget _buildBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.3), width: 0.5)),
      child: Text(text, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class AddToSupplySheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final bool enableTva; // 🟢 AJOUT TVA
  final Function(double, double) onAdd; 

  const AddToSupplySheet({super.key, required this.product, required this.enableTva, required this.onAdd});

  @override
  State<AddToSupplySheet> createState() => _AddToSupplySheetState();
}

class _AddToSupplySheetState extends State<AddToSupplySheet> {
  double _qty = 1;
  late double _displayCost;
  late double _vatPercent;
  final TextEditingController _costCtrl = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();

 @override
  void initState() {
    super.initState();
    _displayCost = double.tryParse(widget.product['cost'].toString()) ?? 0;
    _vatPercent = double.tryParse(widget.product['vat_percent']?.toString() ?? '0') ?? 0.0;
    
    _costCtrl.text = _displayCost.toStringAsFixed(2);
    _qtyController.text = "1";
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
    final totalLine = _displayCost * _qty;

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
                  Text("${totalLine.toStringAsFixed(2)} DA", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange)),
                ],
              ),
              const SizedBox(height: 20),
              
              const Text("PRIX D'ACHAT UNITAIRE (HT)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 10),
              TextField(
                controller: _costCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                  suffixText: "DA"
                ),
                onChanged: (v) => setState(() => _displayCost = double.tryParse(v) ?? 0),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("QUANTITÉ À ENTRER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                ],
              ),
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
                          IconButton(onPressed: _increment, icon: const Icon(Icons.add, color: Colors.orange)),
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
                    Navigator.pop(context);
                    widget.onAdd(_qty, _displayCost);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5
                  ),
                  child: const Text("AJOUTER AU BON", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12)
        ),
        child: Text("+$val", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
      ),
    );
  }
}

class PurchaseCheckoutSheet extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final List<dynamic> suppliers;
  final int? selectedSupId;
  final String? selectedSupName; 
  final Function(List<Map<String, dynamic>>) onUpdateCart;
  final Function(String?, int?, String, double, String, bool) onConfirm;
  final Function(String, String) onCreateSupplier;

  const PurchaseCheckoutSheet({
    super.key, 
    required this.cart,
    required this.suppliers, 
    required this.onUpdateCart,
    required this.onConfirm,
    required this.onCreateSupplier,
    this.selectedSupId,
    this.selectedSupName,
  });

  @override
  State<PurchaseCheckoutSheet> createState() => _PurchaseCheckoutSheetState();
}

class _PurchaseCheckoutSheetState extends State<PurchaseCheckoutSheet> {
  late int? _selId;
  late String _selName;
  String _note = "";
  final TextEditingController _paidController = TextEditingController();
  late List<Map<String, dynamic>> _localCart;

  bool _enableTva = false;
  bool _enableTimbre = false;
  bool _isReturn = false;

  @override
  void initState() {
    super.initState();
    _selId = widget.selectedSupId;
    _selName = widget.selectedSupName ?? "";
    _localCart = List.from(widget.cart);
    _loadTaxesSettings();
    _updateTotalAndField();
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

  double get _grossTotal => _localCart.fold(0, (sum, item) => sum + ((item['cost'] ?? 0.0) * (item['qty'] ?? 1.0)));
  
  double get _tvaAmount {
    if (!_enableTva) return 0.0;
    double totalVat = 0;
    for (var item in _localCart) {
      double qty = (item['qty'] ?? 1.0).toDouble();
      double costHT = (item['cost'] ?? 0.0).toDouble();
      double vatRate = (item['vat_percent'] ?? 0.0).toDouble();
      if (vatRate > 0) {
        totalVat += (costHT * qty) * (vatRate / 100);
      }
    }
    return double.parse(totalVat.toStringAsFixed(2));
  }

  double get _timbreAmount {
    if (!_enableTimbre) return 0.0;
    double ttcTotal = _grossTotal + _tvaAmount; 
    if (ttcTotal <= 0) return 0.0;
    
    double t = 0;
    double tranches = (ttcTotal / 100).ceilToDouble();
    if (ttcTotal <= 30000) { t = tranches * 1.0; } 
    else if (ttcTotal <= 100000) { t = tranches * 1.5; } 
    else { t = tranches * 2.0; }
    
    return t.clamp(5.0, 10000.0);
  }

  double get _total => double.parse((_grossTotal + _tvaAmount + _timbreAmount).toStringAsFixed(2));

void _updateTotalAndField() {
    if (_paidController.text.isEmpty || double.tryParse(_paidController.text) == _total) {
       _paidController.text = _total.toStringAsFixed(2); // 🟢 EXACTITUDE DES DÉCIMALES
    }
    if (mounted) setState(() {});
  }

  void _updateQty(int index, double newQty) {
    if (newQty <= 0) return;
    setState(() {
      _localCart[index]['qty'] = newQty;
    });
    widget.onUpdateCart(_localCart);
    _updateTotalAndField();
  }

  void _updatePrice(int index, double newPrice) {
    setState(() {
      _localCart[index]['cost'] = newPrice;
    });
    widget.onUpdateCart(_localCart);
    _updateTotalAndField();
  }

  void _removeItem(int index) {
    setState(() {
      _localCart.removeAt(index);
    });
    widget.onUpdateCart(_localCart);
    _updateTotalAndField();
    if (_localCart.isEmpty) Navigator.pop(context);
  }
  
 void _editPriceDialog(int index) {
    final item = _localCart[index];
    final costHT = item['cost'] ?? 0.0;

    TextEditingController priceCtrl = TextEditingController(text: costHT.toStringAsFixed(2));
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier Prix (HT)"),
        content: TextField(
            controller: priceCtrl, keyboardType: TextInputType.number, autofocus: true, 
            decoration: const InputDecoration(labelText: "Nouveau Prix HT (DA)", border: OutlineInputBorder(), suffixText: "DA")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () { 
                double? v = double.tryParse(priceCtrl.text); 
                if(v != null) _updatePrice(index, v); 
                Navigator.pop(ctx); 
            }, 
            child: const Text("Valider")
          )
        ],
      )
    );
  }

  void _showAddSupplierDialog() {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController phoneCtrl = TextEditingController();
    
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Nouveau Fournisseur"),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              TextFormField(
                controller: nameCtrl, 
                decoration: const InputDecoration(labelText: "Nom *", icon: Icon(Icons.business)),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().isEmpty) ? "Nom obligatoire" : null,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl, 
                keyboardType: TextInputType.phone, 
                decoration: const InputDecoration(labelText: "Téléphone", icon: Icon(Icons.phone))
              ),
            ]
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              widget.onCreateSupplier(name, phone);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Fournisseur '$name' créé !"), backgroundColor: Colors.green, duration: const Duration(seconds: 1))
              );
            }, 
            child: const Text("Créer", style: TextStyle(color: Colors.white))
          )
        ],
      )
    );
  }

  void _validate() {
    final textAmount = _paidController.text.replaceAll(',', '.').trim();
    final paidAmount = double.tryParse(textAmount) ?? 0;
    final remaining = _total - paidAmount;

   // 🟢 FIX : Fournisseur devient obligatoire pour TOUT achat
    if (_selId == null) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text("⚠️ Veuillez sélectionner un fournisseur valide."), 
           backgroundColor: Colors.red,
         )
       );
       return;
    }

    String type = 'cash'; 

    if (paidAmount <= 0.1) {
       type = 'credit'; 
    } else {
       type = 'cash'; 
    }

    // 🟢 FIX : On transmet _isReturn, et on s'assure que paidAmount est positif
    widget.onConfirm(_note.isEmpty ? null : _note, _selId, _selName, paidAmount, type, _isReturn);
  }

  void _showClearCartDialog() {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: Theme.of(context).brightness == Brightness.dark 
              ? const Color(0xFF1E1E2C).withOpacity(0.85) 
              : Colors.white.withOpacity(0.85),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.white.withOpacity(0.2))),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text("Vider le panier", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: const Text("Voulez-vous vraiment vider le panier d'achats ?", style: TextStyle(fontSize: 15)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text("Annuler", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await ApiService().clearCart('purchases'); // 🚀 Vider le panier SQLite
                setState(() {
                  _localCart.clear();
                  _paidController.text = "0";
                });
                widget.onUpdateCart(_localCart);
                Navigator.pop(context);
              },
              child: const Text("Vider", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paidInput = double.tryParse(_paidController.text) ?? 0;
    final remaining = _total - paidInput;
    final isDebt = remaining > 0.1; 

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SwitchListTile(
                title: Text("Mode Retour", style: TextStyle(fontWeight: FontWeight.bold, color: _isReturn ? Colors.red : (isDark ? Colors.white : Colors.black))),
                subtitle: Text(_isReturn ? "Cette opération est un retour fournisseur" : "Achat standard", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                value: _isReturn,
                activeColor: Colors.red,
                onChanged: (val) => setState(() => _isReturn = val),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text("Réception Stock", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                   Row(
                     children: [
                       IconButton(
                         icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red, size: 28),
                         tooltip: "Vider le panier",
                         onPressed: _showClearCartDialog,
                       ),
                       const SizedBox(width: 8),
                       Text(NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(_total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange)),
                     ],
                   ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _localCart.length,
                separatorBuilder: (_,__) => const Divider(height: 20),
                itemBuilder: (ctx, i) {
                  final item = _localCart[i];
                  return Dismissible(
                    key: Key("${item['product_id']}_${item['variant_id']}"),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _removeItem(i),
                    child: Row(
                      children: [
                        Builder(
                          builder: (context) {
                            final cleanUrl = ApiService.getCleanImageUrl(item['image']);
                            return Container(
                              width: 45, height: 45,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                image: cleanUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(cleanUrl),
                                      fit: BoxFit.cover
                                    )
                                  : null
                              ),
                              child: cleanUrl == null 
                                ? const Icon(Icons.inventory_2_outlined, color: Colors.orange, size: 20) 
                                : null,
                            );
                          }
                        ),

                        Expanded(
                          child: GestureDetector(
                            onTap: () => _editPriceDialog(i),
                            child: Container(
                              color: Colors.transparent,
                             child: Builder(
                                builder: (context) {
                                  final costHT = item['cost'] ?? 0.0;
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black), overflow: TextOverflow.ellipsis, maxLines: 1),
                                      Row(children: [
                                        Text("Coût HT: ${costHT.toStringAsFixed(2)} DA", style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                                        const SizedBox(width: 5), const Icon(Icons.edit, size: 12, color: Colors.grey)
                                      ]),
                                    ],
                                  );
                                }
                              ),
                            ),
                          ),
                        ),

                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8)
                          ),
                          child: Row(
                            children: [
                               InkWell(
                                 onTap: () => _updateQty(i, item['qty'] - 1),
                                 child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.remove, size: 16)),
                               ),
                               Text("${item['qty'].toInt()}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                               InkWell(
                                 onTap: () => _updateQty(i, item['qty'] + 1),
                                 child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.add, size: 16, color: Colors.orange)),
                               ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 15),
                        Builder(
                          builder: (context) {
                            final costHT = item['cost'] ?? 0.0;
                            return Text("${(costHT * item['qty']).toStringAsFixed(2)} DA", style: const TextStyle(fontWeight: FontWeight.bold));
                          }
                        ),
                      ],
                    ),
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
            padding: EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openSupplierSelector(isDark),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                          child: Row(
                            children: [
                              const Icon(Icons.business, color: Colors.blue, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Fournisseur", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                    const SizedBox(height: 2),
                                    Text(_selName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _selId != null ? Colors.blue : (isDark ? Colors.white : Colors.black))),
                                  ],
                                ),
                              ),
                              // 💰 VERSEMENT RAPIDE FOURNISSEUR
                              if (_selId != null)
                                GestureDetector(
                                  onTap: () => _showQuickSupplierPaymentDialog(isDark),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.payments_outlined, color: Colors.white, size: 14),
                                        SizedBox(width: 4),
                                        Text("Versement", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ),
                              Icon(Icons.arrow_drop_down, color: Colors.grey[500]),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                        height: 55, width: 55,
                        decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(15)),
                        child: IconButton(
                            icon: const Icon(Icons.person_add, color: Colors.white),
                            onPressed: _showAddSupplierDialog, 
                        ),
                    )
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _paidController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                        onChanged: (v) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: "Montant Payé",
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildQuickPayBtn("TOUT", Colors.green, () => setState(() => _paidController.text = _total.toStringAsFixed(2))),
                    const SizedBox(width: 5),
                    _buildQuickPayBtn("CRÉDIT", Colors.red, () => setState(() => _paidController.text = "0")),
                  ],
                ),
                if (isDebt)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text("Reste à payer (Dette) : ${NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(remaining)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (v) => _note = v,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    labelText: "Note (ex: N° Bon Livraison)",
                    prefixIcon: const Icon(Icons.note_alt_outlined),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 55,
                  child: ElevatedButton(
                    onPressed: _validate,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    child: Text(isDebt ? "VALIDER AVEC DETTE" : "CONFIRMER ACHAT", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSupplierSelector(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchableSelectModal(
        title: "Sélectionner un fournisseur",
        icon: Icons.domain,
        themeColor: Colors.blue,
        items: widget.suppliers,
        noneLabel: "Fournisseur Divers",
        onSelected: (selectedItem) {
          setState(() {
            if (selectedItem == null) {
              _selId = null;
              _selName = "Fournisseur Divers";
            } else {
              _selId = int.tryParse(selectedItem['id'].toString());
              _selName = selectedItem['name']?.toString() ?? 'Inconnu';
            }
          });
        },
      ),
    );
  }

  Widget _buildQuickPayBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(15)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
      ),
    );
  }

  // 💰 VERSEMENT RAPIDE FOURNISSEUR depuis la page d'achat
  void _showQuickSupplierPaymentDialog(bool isDark) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final api = ApiService();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.payments_outlined, color: Color(0xFF3B82F6), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Versement Fournisseur", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                  Text(_selName, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: "Montant (DA)",
                prefixIcon: const Icon(Icons.attach_money, color: Color(0xFF3B82F6)),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: "Note (optionnel)",
                prefixIcon: const Icon(Icons.note_alt_outlined, color: Colors.grey),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Annuler", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;

              await api.sendPartnerPaymentOptimistic(
                partnerId: _selId,
                amount: amount,
                type: 'supplier',
                note: noteCtrl.text.isEmpty ? 'Versement fournisseur' : noteCtrl.text,
              );

              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("✅ Versement de ${amount.toStringAsFixed(0)} DA envoyé à $_selName"),
                  backgroundColor: const Color(0xFF3B82F6),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ));
              }
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text("Confirmer", style: TextStyle(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}