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


class SalesPage extends StatefulWidget {
  final VoidCallback? onBack;
  const SalesPage({super.key, this.onBack});

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
  
  List<Map<String, dynamic>> _cart = [];
  int? _selectedClientId;
  String _selectedClientName = "Client Comptoir";
  
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    
    // 1. Démarrage de la synchro auto
    _api.startAutoSync();

    _loadData();

    // 2. Écoute des mises à jour
    _dataSubscription = _api.onDataUpdated.listen((_) {
       final now = DateTime.now();
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
        _api.getTiersList('clients', '')
      ]);

      final productsData = results[0] as Map<String, dynamic>;
      final clientsData = results[1] as List<dynamic>;
      
      if (mounted) {
        setState(() {
          _allProducts = productsData['products'] ?? [];
          List<dynamic> cats = productsData['categories'] ?? [];
          _categories = ['Tout', ...cats.map((e) => e.toString())];

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
      if (mounted) setState(() => _isLoading = false);
    }
  }

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

      if (_activeSmartFilter == 'fav') {
        temp = temp.where((p) => (int.tryParse(p['is_favorite']?.toString() ?? '0') ?? 0) == 1).toList();
      } else if (_activeSmartFilter == 'low') {
        temp = temp.where((p) {
          final stock = double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
          final min = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5;
          return stock <= min;
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
            Text("Choisir une variante pour ${product['name']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 15),
            ...variants.map((v) => ListTile(
              title: Text(v['sku'] ?? 'Variante'),
              trailing: Text("${v['price']} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
              subtitle: Text("Stock: ${v['stock']}"),
              onTap: () {
                Navigator.pop(context);
                Map<String, dynamic> variantProduct = Map.from(product);
                variantProduct['id'] = product['id']; 
                variantProduct['variant_id'] = v['id'];
                variantProduct['name'] = "${product['name']} (${v['sku']})";
                variantProduct['price'] = v['price'];
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
      builder: (ctx) => AddToCartSheet(
        product: product,
        onAdd: (qty, price, note) {
           _addToCart(product, qty, price, isVariant ? product['variant_id'] : null);
        },
      ),
    );
  }

  void _addToCart(dynamic product, double qty, double price, dynamic variantId) {
    setState(() {
      final index = _cart.indexWhere((item) => item['product_id'] == product['id'] && item['variant_id'] == variantId && item['price'] == price);
      
      if (index >= 0) {
        _cart[index]['qty'] += qty;
      } else {
        _cart.add({
          'product_id': product['id'],
          'name': product['name'],
          'price': price,
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
      backgroundColor: Colors.green,
    ));
  }

  void _showCheckoutSheet() {
    if (_cart.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CheckoutSheet(
        cart: _cart, 
        clients: _clients,
        selectedClientId: _selectedClientId,
        selectedClientName: _selectedClientName,
        onUpdateCart: (updatedCart) => setState(() => _cart = updatedCart),
        onCheckout: (note, clientId, clientName, paidAmount, paymentType, discount) => 
            _processSale(note, clientId, clientName, paidAmount, paymentType, discount),
      ),
    );
  }

  Future<void> _processSale(String? note, int? clientId, String clientName, double paidAmount, String paymentType, double discount) async {
    Navigator.pop(context); 
    setState(() => _isSending = true);

    // Calcul du total NET
    double brut = _cart.fold(0.0, (s, i) => s + (i['price'] * i['qty']));
    double netTotal = brut - discount;

    try {
      await _api.sendComplexSaleOptimistic(
        netTotal, 
        List.from(_cart), 
        note: note, 
        clientId: clientId, 
        clientName: clientName,
        amountPaid: paidAmount,
        paymentType: paymentType,
        discount: discount // Envoi de la remise
      );

      if (mounted) {
        setState(() => _isSending = false);
        setState(() {
          _cart.clear();
          _selectedClientId = null;
          _selectedClientName = "Client Comptoir";
          _searchController.clear();
          _activeSmartFilter = 'none';
        });
        await _loadData(silent: true); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Vente enregistrée !"), backgroundColor: Colors.green));
      }
    } catch (e) {
       if(mounted) setState(() => _isSending = false);
    }
  }

  double get _total => _cart.fold(0, (sum, item) => sum + (item['price'] * item['qty']));

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
                        Text("Nouvelle Vente", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: 0.5)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text("${_cart.length}", style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
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
                            icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
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
                          _buildSmartFilterBtn('new', 'Nouveaux', FontAwesomeIcons.wandMagicSparkles, Colors.blue, isDark),
                          _buildSmartFilterBtn('top', 'Top Ventes', FontAwesomeIcons.fire, Colors.orange, isDark),
                          _buildSmartFilterBtn('low', 'Critique', FontAwesomeIcons.triangleExclamation, Colors.red, isDark),
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
                              selectedColor: AppColors.primary,
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
                                      color: isSelected ? AppColors.primary.withOpacity(0.2) : Colors.transparent,
                                      border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.withOpacity(0.3)),
                                      borderRadius: BorderRadius.circular(15)
                                    ),
                                    child: Text(sub, style: TextStyle(fontSize: 11, color: isSelected ? AppColors.primary : Colors.grey, fontWeight: FontWeight.bold)),
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
    final price = double.tryParse(p['price'].toString()) ?? 0; // ✅ C'est bien le prix de vente
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
                        // ✅ CORRECTION ICI : Utilisation de 'price' et non 'cost'
                        Text("${price.toStringAsFixed(0)} DA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                        Text("TTC", style: TextStyle(fontSize: 9, color: Colors.grey[500])),
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

// ==========================================
// 1. MODALE AJOUT PANIER (QUANTITÉ & PRIX)
// ==========================================
class AddToCartSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final Function(double, double, String?) onAdd;

  const AddToCartSheet({super.key, required this.product, required this.onAdd});

  @override
  State<AddToCartSheet> createState() => _AddToCartSheetState();
}

class _AddToCartSheetState extends State<AddToCartSheet> {
  double _qty = 1;
  late double _selectedPrice;
  late String _selectedPriceType; // 'detail', 'semi', 'gros'
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedPrice = double.tryParse(widget.product['price'].toString()) ?? 0;
    _selectedPriceType = 'detail';
  }

  void _increment() => setState(() => _qty++);
  void _decrement() { if (_qty > 1) setState(() => _qty--); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.product;
    final pDetail = double.tryParse(p['price'].toString()) ?? 0;
    final pSemi = double.tryParse(p['price_semi']?.toString() ?? '0') ?? 0;
    final pGros = double.tryParse(p['price_whol']?.toString() ?? '0') ?? 0;

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
              Text("${(_selectedPrice * _qty).toStringAsFixed(0)} DA", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 20),
          
          // SELECTEUR TYPE PRIX
          const Text("TARIFICATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildPriceOption("Détail", pDetail, 'detail', isDark),
              if (pSemi > 0) _buildPriceOption("Semi-Gros", pSemi, 'semi', isDark),
              if (pGros > 0) _buildPriceOption("Gros", pGros, 'gros', isDark),
            ],
          ),
          const SizedBox(height: 20),

          // SELECTEUR QUANTITÉ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("QUANTITÉ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
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
                    IconButton(onPressed: _increment, icon: const Icon(Icons.add, color: AppColors.primary)),
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
                widget.onAdd(_qty, _selectedPrice, null);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 5
              ),
              child: const Text("AJOUTER AU PANIER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 10),
        ],
      ),
    );
  }

  Widget _buildPriceOption(String label, double price, String type, bool isDark) {
    final isSelected = _selectedPriceType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _selectedPriceType = type; _selectedPrice = price; }),
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
              Text("${price.toInt()}", style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? AppColors.primary : (isDark ? Colors.white : Colors.black))),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. MODALE CHECKOUT (PANIER COMPLET)
// ==========================================
class CheckoutSheet extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final List<dynamic> clients;
  final int? selectedClientId;
  final String selectedClientName;
  final Function(List<Map<String, dynamic>>) onUpdateCart;
  final Function(String?, int?, String, double, String, double) onCheckout;

  const CheckoutSheet({
    super.key, 
    required this.cart,
    required this.clients, 
    required this.onUpdateCart,
    required this.onCheckout,
    this.selectedClientId,
    required this.selectedClientName,
  });

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  late int? _selId;
  late String _selName;
  String _note = "";
  final TextEditingController _paidController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  late List<Map<String, dynamic>> _localCart;
  double _discount = 0.0;

  @override
  void initState() {
    super.initState();
    _selId = widget.selectedClientId;
    _selName = widget.selectedClientName;
    _localCart = List.from(widget.cart);
    _updateTotalAndField();
  }

  double get _grossTotal => _localCart.fold(0, (sum, item) => sum + (item['price'] * item['qty']));
  double get _netTotal => (_grossTotal - _discount).clamp(0.0, double.infinity);

  void _updateTotalAndField() {
    if (_paidController.text.isEmpty || double.tryParse(_paidController.text) == _grossTotal) {
       _paidController.text = _netTotal.toStringAsFixed(0);
    }
  }

  void _onDiscountChanged(String val) {
     setState(() {
         _discount = double.tryParse(val) ?? 0.0;
         if (_discount > _grossTotal) _discount = _grossTotal;
         _paidController.text = _netTotal.toStringAsFixed(0);
     });
  }

  void _updateQty(int index, double newQty) {
    if (newQty <= 0) return;
    setState(() {
      _localCart[index]['qty'] = newQty;
      _paidController.text = _netTotal.toStringAsFixed(0);
    });
    widget.onUpdateCart(_localCart);
  }

  void _editQtyDialog(int index) {
    TextEditingController qtyCtrl = TextEditingController(text: _localCart[index]['qty'].toString());
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier Quantité"),
        content: TextField(
          controller: qtyCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Nouvelle quantité", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              double? v = double.tryParse(qtyCtrl.text);
              if (v != null) _updateQty(index, v);
              Navigator.pop(ctx);
            }, 
            child: const Text("Valider")
          )
        ],
      )
    );
  }

  void _removeItem(int index) {
    setState(() {
      _localCart.removeAt(index);
      _paidController.text = _netTotal.toStringAsFixed(0);
    });
    widget.onUpdateCart(_localCart);
    if (_localCart.isEmpty) Navigator.pop(context);
  }

  void _validate() {
    final textAmount = _paidController.text.replaceAll(',', '.').trim();
    final paidAmount = double.tryParse(textAmount) ?? 0;
    final remaining = _netTotal - paidAmount;
    
    if (remaining > 1.0 && _selId == null) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text("⚠️ CLIENT OBLIGATOIRE pour le crédit/versement !"), 
           backgroundColor: Colors.red,
           duration: Duration(seconds: 3),
         )
       );
       return; 
    }

    String type = 'cash'; 
    if (paidAmount <= 0.1) {
       type = 'credit'; 
    } else if (remaining > 0.1) {
       type = 'partial'; 
    } else {
       type = 'cash'; 
    }

    widget.onCheckout(_note.isEmpty ? null : _note, _selId, _selName, paidAmount, type, _discount);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentPaid = double.tryParse(_paidController.text) ?? 0;
    final remaining = _netTotal - currentPaid;
    final isCredit = remaining > 0.1;

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
               Text("Panier", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
               Column(
                 crossAxisAlignment: CrossAxisAlignment.end,
                 children: [
                    if(_discount > 0)
                      Text("${_grossTotal.toStringAsFixed(0)} DA", style: const TextStyle(fontSize: 14, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                    Text("${_netTotal.toStringAsFixed(0)} DA", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary)),
                 ],
               ),
            ],
          ),
          const SizedBox(height: 15),
          
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
                        color: Colors.grey.withOpacity(0.1),
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
                      child: (imgUrl == null || imgUrl.toString().length <= 2)
                        ? const Icon(Icons.shopping_bag_outlined, color: Colors.grey, size: 20)
                        : null,
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black)),
                          Text("${item['price']} DA / ${item['unit']}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        ],
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
                    Text("${(item['price']*item['qty']).toInt()} DA", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                );
              },
            ),
          ),
          
          const Divider(height: 30),
          
          DropdownButtonFormField<int>(
            value: _selId,
            dropdownColor: isDark ? const Color(0xFF2C2C35) : Colors.white,
            decoration: InputDecoration(
              labelText: "Client",
              prefixIcon: const Icon(Icons.person),
              filled: true,
              fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
            items: [
              DropdownMenuItem<int>(value: null, child: Text("Client Comptoir", style: TextStyle(color: isDark ? Colors.white : Colors.black))),
              ...widget.clients.map((c) => DropdownMenuItem<int>(
                value: c['id'],
                child: Text(c['name'], style: TextStyle(color: isDark ? Colors.white : Colors.black)),
              ))
            ],
            onChanged: (val) => setState(() {
               _selId = val;
               _selName = val == null ? "Client Comptoir" : widget.clients.firstWhere((c) => c['id'] == val)['name'];
            }),
          ),
          const SizedBox(height: 10),

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
                     labelText: "Remise (DA)",
                     filled: true,
                     fillColor: Colors.red.withOpacity(0.1), 
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                     prefixIcon: const Icon(Icons.discount, size: 18, color: Colors.red),
                   ),
                 ),
               ),
               const SizedBox(width: 10),
               
               Expanded(
                 flex: 6,
                 child: TextField(
                   controller: _paidController,
                   keyboardType: TextInputType.number,
                   style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                   onChanged: (v) => setState(() {}),
                   decoration: InputDecoration(
                     labelText: "Montant Versé",
                     filled: true,
                     fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                   ),
                 ),
               ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(child: _buildQuickPayBtn("TOUT", Colors.green, () => setState(() => _paidController.text = _netTotal.toStringAsFixed(0)))),
              const SizedBox(width: 10),
              Expanded(child: _buildQuickPayBtn("CRÉDIT", Colors.red, () => setState(() => _paidController.text = "0"))),
            ],
          ),
          
          if (isCredit)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Text("Reste à payer (Dette) : ${NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(remaining)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 55,
            child: ElevatedButton(
              onPressed: _validate,
              style: ElevatedButton.styleFrom(backgroundColor: isCredit ? Colors.orange : AppColors.success, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: Text(isCredit ? "VALIDER CRÉDIT" : "ENCAISSER MAINTENANT", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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