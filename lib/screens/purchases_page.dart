import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:ai_barcode_scanner/ai_barcode_scanner.dart'; 

import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

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
  
  List<Map<String, dynamic>> _cart = [];
  
  // Variables pour le checkout
  int? _selectedSupplierId;
  String _selectedSupplierName = "Fournisseur Divers";
  
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _debounce;

 @override
  void initState() {
    super.initState();
    
    // ✅ ON LANCE LE MOTEUR DE SYNCHRO ICI
    _api.startAutoSync(); 

    _loadData();

    // --- AUTO SYNCHRONISATION ---
    _dataSubscription = _api.onDataUpdated.listen((_) {
       final now = DateTime.now();
       // Anti-rebond de 2 secondes pour éviter de rafraîchir trop souvent
       if (_lastRefreshTime == null || now.difference(_lastRefreshTime!).inSeconds > 2) {
         _lastRefreshTime = now;
         if (mounted) _loadData(silent: true);
       }
    });
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
          _categories = ['Tout', ...cats.map((e) => e.toString())];

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

  // --- SCANNER HELPER ---
  Future<void> _scanBarcode() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AiBarcodeScanner(
          onDetect: (BarcodeCapture capture) {
            final String? scannedValue = capture.barcodes.first.rawValue;
            if (scannedValue != null) {
              Navigator.of(context).pop();
              setState(() {
                _searchController.text = scannedValue;
                _applyFilters(); 
              });
            }
          },
          controller: MobileScannerController(
            detectionSpeed: DetectionSpeed.noDuplicates,
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
      _currentSubCategories = ['Tout', ...subSet.toList()];
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
        
        final matchesText = query.isEmpty || name.contains(query) || ref.contains(query) || barcode.contains(query);
        
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

      // Filtres intelligents
      if (_activeSmartFilter == 'fav') {
        temp = temp.where((p) => (int.tryParse(p['is_favorite']?.toString() ?? '0') ?? 0) == 1).toList();
      } else if (_activeSmartFilter == 'low') {
        temp = temp.where((p) {
          final stock = double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
          final min = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5;
          return stock <= min;
        }).toList();
      }

      // Tri
      if (_activeSmartFilter == 'top') {
         temp.sort((a, b) => (double.tryParse(b['total_sold'].toString()) ?? 0).compareTo(double.tryParse(a['total_sold'].toString()) ?? 0));
      } else if (_activeSmartFilter == 'new') {
         temp.sort((a, b) => (int.tryParse(b['id'].toString()) ?? 0).compareTo(int.tryParse(a['id'].toString()) ?? 0));
      } else {
         temp.sort((a, b) => (a['name'] ?? '').toString().compareTo(b['name'] ?? ''));
      }

      setState(() {
        _filteredProducts = temp;
      });
    });
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
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Theme.of(context).canvasColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(25))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Variante pour ${product['name']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 15),
            ...variants.map((v) => ListTile(
              title: Text(v['sku'] ?? 'Variante'),
              trailing: Text("Coût: ${v['cost'] ?? product['cost']} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              subtitle: Text("Stock actuel: ${v['stock']}"),
              onTap: () {
                Navigator.pop(context);
                Map<String, dynamic> variantProduct = Map.from(product);
                variantProduct['id'] = product['id']; 
                variantProduct['variant_id'] = v['id'];
                variantProduct['name'] = "${product['name']} (${v['sku']})";
                variantProduct['cost'] = v['cost'] ?? product['cost'];
                variantProduct['stock'] = v['stock'];
                _showProductConfigurator(variantProduct, isVariant: true);
              },
            ))
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
        onAdd: (qty, cost) {
           _addToCart(product, qty, cost, isVariant ? product['variant_id'] : null);
        },
      ),
    );
  }

  void _addToCart(dynamic product, double qty, double cost, dynamic variantId) {
    setState(() {
      final index = _cart.indexWhere((item) => item['product_id'] == product['id'] && item['variant_id'] == variantId && item['cost'] == cost);
      
      if (index >= 0) {
        _cart[index]['qty'] += qty;
      } else {
        _cart.add({
          'product_id': product['id'],
          'name': product['name'],
          'cost': cost,
          'qty': qty,
          'variant_id': variantId,
          'unit': product['unit'] ?? 'u',
          'image': product['base_image_path'],
        });
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("${qty.toStringAsFixed(0)} x ${product['name']} ajouté!"), 
      duration: const Duration(milliseconds: 800),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.orange,
    ));
  }

  // --- CHECKOUT & VALIDATION ---
  void _showCheckoutSheet() {
    if (_cart.isEmpty) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PurchaseCheckoutSheet(
        cart: _cart, 
        suppliers: _suppliers,
        selectedSupId: _selectedSupplierId,
        selectedSupName: _selectedSupplierName == "Fournisseur Divers" ? null : _selectedSupplierName, 
        
        onUpdateCart: (updatedCart) => setState(() => _cart = updatedCart),
        
        // CALLBACK POUR CRÉER UN FOURNISSEUR (Logiciel PC Sync)
        onCreateSupplier: (name, phone) async {
           // 1. On l'ajoute localement tout de suite (Optimistic UI)
           final tempId = -1 * DateTime.now().millisecondsSinceEpoch;
           final newSup = {'id': tempId, 'name': name, 'phone': phone, 'balance': 0};
           
           setState(() {
             _suppliers.add(newSup);
             _selectedSupplierId = tempId;
             _selectedSupplierName = name;
           });

           // 2. On envoie la commande au serveur via l'ApiService
           await _api.createTier('supplier', newSup);
        },

        onConfirm: (note, supId, supName, paidAmount, paymentType) {
             setState(() {
                 _selectedSupplierId = supId;
                 _selectedSupplierName = supName;
             });
             _processPurchase(note, supId, supName, paidAmount, paymentType);
        },
      ),
    );
  }

Future<void> _processPurchase(String? note, int? supId, String supName, double paidAmount, String paymentType) async {
    Navigator.pop(context); // Fermer le sheet
    
    setState(() => _isSending = true);

    try {

    await _api.sendComplexPurchase(
  _total, 
  List.from(_cart), // ✅ SOLUTION : Copie indépendante
  note: note, 
  supplierId: supId, 
  supplierName: supName,
  amountPaid: paidAmount,
  paymentType: paymentType
);

      // 2. Mise à jour immédiate de l'interface
      if (mounted) {
        setState(() {
          _isSending = false;
          // Vider le panier
          _cart.clear();
          // Réinitialiser les sélections
          _selectedSupplierId = null;
          _selectedSupplierName = "Fournisseur Divers";
          _searchController.clear();
          _activeSmartFilter = 'none';
        });
        
        // 3. Rafraîchir les données (pour voir le stock augmenter tout de suite)
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

  double get _total => _cart.fold(0, (sum, item) => sum + (item['cost'] * item['qty']));

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
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
                        Text("Nouvel Achat", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: 0.5)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text("${_cart.length}", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    // BARRE DE RECHERCHE + SCANNER
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
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                  : _filteredProducts.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 10), const Text("Aucun produit", style: TextStyle(color: Colors.grey))]))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(15, 15, 15, 120), 
                        physics: const BouncingScrollPhysics(),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (ctx, i) => _buildProductCard(_filteredProducts[i], isDark),
                      ),
              ),
            ],
          ),
          if (_cart.isNotEmpty)
            Positioned(
              bottom: 20, left: 20, right: 20,
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
    final minStock = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5;
    final isLow = stock <= minStock;
    final packing = double.tryParse(p['packing']?.toString() ?? '1') ?? 1;
    final unit = p['unit'] ?? 'u';
    final hasVariants = (p['variants'] is List && (p['variants'] as List).isNotEmpty);
    final imgUrl = p['base_image_path'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _onProductTap(p),
        child: GlassCard(
          isDark: isDark,
          padding: const EdgeInsets.all(12),
          borderRadius: 20,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 70,
                  decoration: BoxDecoration(
                    color: isLow ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.05), 
                    borderRadius: BorderRadius.circular(15),
                    image: (imgUrl != null && imgUrl.toString().length > 2)
                        ? DecorationImage(
                            image: (imgUrl.toString().startsWith('http')) 
                                ? NetworkImage(imgUrl) 
                                : FileImage(File(imgUrl)) as ImageProvider,
                            fit: BoxFit.cover
                          )
                        : null
                  ),
                  child: (imgUrl == null || imgUrl.toString().length <= 2)
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
                          Text("${p['category'] ?? ''}", style: TextStyle(color: Colors.grey[500], fontSize: 11)),
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
                        Text("Coût (PMP)", style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                      ],
                    ),
                    Container(
                      width: 35, height: 35,
                      decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.add, color: Colors.white, size: 20),
                    )
                  ],
                )
              ],
            ),
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

// ==============================================================================
// SOUS-WIDGETS (CONFIGURATEUR DE QUANTITÉ)
// ==============================================================================
class AddToSupplySheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final Function(double, double) onAdd; 

  const AddToSupplySheet({super.key, required this.product, required this.onAdd});

  @override
  State<AddToSupplySheet> createState() => _AddToSupplySheetState();
}

class _AddToSupplySheetState extends State<AddToSupplySheet> {
  double _qty = 1;
  late double _currentCost;
  final TextEditingController _costCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentCost = double.tryParse(widget.product['cost'].toString()) ?? 0;
    _costCtrl.text = _currentCost.toStringAsFixed(0);
  }

  void _increment() => setState(() => _qty++);
  void _decrement() { if (_qty > 1) setState(() => _qty--); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.product;
    final totalLine = _currentCost * _qty;

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
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
              Text("${totalLine.toStringAsFixed(0)} DA", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 20),
          
          const Text("PRIX D'ACHAT UNITAIRE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
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
            onChanged: (v) => setState(() => _currentCost = double.tryParse(v) ?? 0),
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("QUANTITÉ À ENTRER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              Container(
                decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                child: Row(
                  children: [
                    IconButton(onPressed: _decrement, icon: const Icon(Icons.remove)),
                    Container(
                      width: 60,
                      alignment: Alignment.center,
                      child: Text("${_qty.toInt()}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    ),
                    IconButton(onPressed: _increment, icon: const Icon(Icons.add, color: Colors.orange)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 20),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onAdd(_qty, _currentCost);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 5
              ),
              child: const Text("AJOUTER AU BON", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 10),
        ],
      ),
    );
  }
}

// ==============================================================================
// SOUS-WIDGETS (CHECKOUT)
// ==============================================================================
class PurchaseCheckoutSheet extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final List<dynamic> suppliers;
  final int? selectedSupId;
  final String? selectedSupName; 
  final Function(List<Map<String, dynamic>>) onUpdateCart;
  final Function(String?, int?, String, double, String) onConfirm;
  final Function(String, String) onCreateSupplier; // CALLBACK NOUVEAU FOURNISSEUR

  const PurchaseCheckoutSheet({
    super.key, 
    required this.cart,
    required this.suppliers, 
    required this.onUpdateCart,
    required this.onConfirm,
    required this.onCreateSupplier, // Ajouté
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

  double get _total => _localCart.fold(0, (sum, item) => sum + (item['cost'] * item['qty']));

  @override
  void initState() {
    super.initState();
    _selId = widget.selectedSupId;
    _selName = widget.selectedSupName ?? "";
    _localCart = List.from(widget.cart);
    _updateTotalAndField();
  }

  void _updateTotalAndField() {
    if (_paidController.text.isEmpty || double.tryParse(_paidController.text) == _total) {
       _paidController.text = _total.toStringAsFixed(0);
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
  
  // --- Boites de dialogue ---
  void _editQtyDialog(int index) {
    TextEditingController qtyCtrl = TextEditingController(text: _localCart[index]['qty'].toString());
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier Quantité"),
        content: TextField(
            controller: qtyCtrl, keyboardType: TextInputType.number, autofocus: true, 
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Quantité", prefixIcon: Icon(Icons.numbers))
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () { 
                double? v = double.tryParse(qtyCtrl.text); 
                if(v != null) _updateQty(index, v); 
                Navigator.pop(ctx); 
            }, 
            child: const Text("Valider")
          )
        ],
      )
    );
  }

  void _editPriceDialog(int index) {
    TextEditingController priceCtrl = TextEditingController(text: _localCart[index]['cost'].toString());
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier Prix Achat"),
        content: TextField(
            controller: priceCtrl, keyboardType: TextInputType.number, autofocus: true, 
            decoration: const InputDecoration(labelText: "Nouveau Prix (DA)", border: OutlineInputBorder(), suffixText: "DA")
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
              
              // 1. Préparer les données
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              
              // 2. Appel du callback parent pour mise à jour immédiate
              widget.onCreateSupplier(name, phone);
              
              // 3. Fermer tout de suite
              Navigator.pop(ctx);
              
              // 4. Petit feedback visuel rapide
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
    // Lecture propre du montant saisi
    final textAmount = _paidController.text.replaceAll(',', '.').trim();
    final paidAmount = double.tryParse(textAmount) ?? 0;
    
    // Calcul du reste à payer avec tolérance de 0.1 pour les arrondis
    final remaining = _total - paidAmount;

    // --- SÉCURITÉ OBLIGATOIRE ---
    // Si il reste une dette (> 0.1 DA) ET que aucun fournisseur n'est sélectionné (_selId est null)
    if (remaining > 0.1 && _selId == null) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text("⚠️ FOURNISSEUR OBLIGATOIRE pour un achat à crédit !"), 
           backgroundColor: Colors.red,
           duration: Duration(seconds: 3),
         )
       );
       return; // ON ARRÊTE TOUT ICI. L'achat ne part pas.
    }

    String type = 'cash'; 

    if (paidAmount <= 0.1) {
       type = 'credit'; // Tout est à crédit
    } else if (remaining > 0.1) {
       type = 'partial'; // Payé partiellement
    } else {
       type = 'cash'; // Tout payé
    }

    // Si tout est bon, on envoie
    widget.onConfirm(_note.isEmpty ? null : _note, _selId, _selName, paidAmount, type);
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paidInput = double.tryParse(_paidController.text) ?? 0;
    final remaining = _total - paidInput;
    final isDebt = remaining > 0.1; 

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Text("Réception Stock", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
               Text(NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(_total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 15),
          
          // LISTE DES ARTICLES
          Expanded(
            child: ListView.separated(
              itemCount: _localCart.length,
              separatorBuilder: (_,__) => const Divider(height: 20),
              itemBuilder: (ctx, i) {
                final item = _localCart[i];
                final imgUrl = item['image'];
                return Row(
                  children: [
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _removeItem(i)),
                    
                    Container(
                      width: 45, height: 45,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        image: (imgUrl != null && imgUrl.toString().length > 2)
                          ? DecorationImage(
                              image: (imgUrl.toString().startsWith('http')) 
                                ? NetworkImage(imgUrl) 
                                : FileImage(File(imgUrl)) as ImageProvider,
                            fit: BoxFit.cover
                            )
                          : null
                      ),
                      child: (imgUrl == null || imgUrl.toString().length <= 2) ? const Icon(Icons.inventory_2_outlined, color: Colors.orange, size: 20) : null,
                    ),

                    Expanded(
                      child: GestureDetector(
                        onTap: () => _editPriceDialog(i),
                        child: Container(
                          color: Colors.transparent,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black), overflow: TextOverflow.ellipsis, maxLines: 1),
                              Row(children: [
                                Text("Coût: ${item['cost']} DA", style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 5), const Icon(Icons.edit, size: 12, color: Colors.grey)
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ),

                    GestureDetector(
                      onTap: () => _editQtyDialog(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                        child: Text("x${item['qty']}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Text("${(item['cost']*item['qty']).toInt()} DA", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                );
              },
            ),
          ),
          
          const Divider(height: 30),
          
          // --- SÉLECTION FOURNISSEUR ---
          Row(
            children: [
                Expanded(
                    child: DropdownButtonFormField<int>(
                        value: _selId,
                        dropdownColor: isDark ? const Color(0xFF2C2C35) : Colors.white,
                        decoration: InputDecoration(
                            labelText: "Fournisseur *",
                            prefixIcon: const Icon(Icons.business),
                            filled: true,
                            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10)
                        ),
                        hint: Text("Sélectionner...", style: TextStyle(color: Colors.grey[500])),
                        items: widget.suppliers.map((s) => DropdownMenuItem<int>(
                             value: s['id'],
                             child: Text(s['name'], style: TextStyle(color: isDark ? Colors.white : Colors.black), overflow: TextOverflow.ellipsis),
                           )).toList(),
                        onChanged: (val) => setState(() {
                           if(val != null) {
                               _selId = val;
                               final found = widget.suppliers.firstWhere((s) => s['id'] == val, orElse: () => {'name': 'Inconnu'});
                               _selName = found['name'];
                           }
                        }),
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

          // --- MONTANT PAYÉ ---
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
              _buildQuickPayBtn("TOUT", Colors.green, () => setState(() => _paidController.text = _total.toStringAsFixed(0))),
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
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 10),
        ],
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
}