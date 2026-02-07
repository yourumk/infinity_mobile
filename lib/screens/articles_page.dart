import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:ai_barcode_scanner/ai_barcode_scanner.dart'; 

import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  
  // GESTION DU RAFRAÎCHISSEMENT AUTOMATIQUE
  StreamSubscription? _dataSubscription;

  List<dynamic> _allProducts = [];
  List<dynamic> _filteredProducts = [];
  List<String> _categories = ['Tout'];
  List<String> _subCategories = []; 
  List<String> _currentSubCategories = []; 
  
  String _selectedCategory = 'Tout';
  String _selectedSubCategory = 'Tout';
  String _activeSmartFilter = 'none';
  bool _isLoading = true;

@override
  void initState() {
    super.initState();
    
    // ✅ 1. On s'assure que la synchro tourne
    _api.startAutoSync(); 

    // 2. Premier chargement
    _fetchCatalog();
    
    // 3. ABONNEMENT AUX MISES À JOUR (AUTO-REFRESH)
    _dataSubscription = _api.onDataUpdated.listen((_) {
      if (mounted) {
        // "silent: true" pour ne pas bloquer l'écran
        _fetchCatalog(silent: true);
      }
    });
  }
  @override
  void dispose() {
    // IMPORTANT : On coupe l'écoute quand on quitte la page
    _dataSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCatalog({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final data = await _api.getProductsWithQueue();
      if (mounted) {
        setState(() {
          _allProducts = data['products'] ?? [];
          List<dynamic> catsFromPc = data['categories'] ?? [];
          _categories = ['Tout', ...catsFromPc.map((e) => e.toString())];

          Set<String> subSet = {};
          List<dynamic> subsFromPc = data['sub_categories'] ?? [];
          for(var p in _allProducts) {
             if(p['sub_category'] != null && p['sub_category'].toString().isNotEmpty) {
               subSet.add(p['sub_category'].toString());
             }
          }
          for(var s in subsFromPc) subSet.add(s.toString());
          _subCategories = subSet.toList();
          
          _isLoading = false;
          _updateSubCategoryList();
          _applyFilters();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scanBarcode(TextEditingController controller, {bool autoSearch = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AiBarcodeScanner(
          onDetect: (BarcodeCapture capture) {
            final String? scannedValue = capture.barcodes.first.rawValue;
            if (scannedValue != null) {
              Navigator.of(context).pop();
              setState(() {
                controller.text = scannedValue;
                if (autoSearch) _applyFilters();
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
      temp.sort((a, b) => (double.tryParse(b['total_sold'].toString()) ?? 0).compareTo(double.tryParse(a['total_sold'].toString()) ?? 0));
    } else if (_activeSmartFilter == 'new') {
      temp.sort((a, b) => (int.tryParse(b['id'].toString()) ?? 0).compareTo(int.tryParse(a['id'].toString()) ?? 0));
    } else {
      temp.sort((a, b) => (a['name'] ?? '').toString().compareTo(b['name'] ?? ''));
    }

    setState(() => _filteredProducts = temp);
  }

  Future<void> _startMagicImageFill() async {
    final missing = _allProducts.where((p) {
      final id = int.tryParse(p['id'].toString()) ?? -1;
      if (id <= 0) return false;
      String? img = p['base_image_path']?.toString();
      if (img == null || img == 'null' || img.trim().isEmpty) return true; 
      if (img.startsWith('file://') || img.startsWith('http')) return false; 
      return true;
    }).toList();

    if (missing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✨ Tous vos produits ont déjà une photo !"), backgroundColor: Colors.green));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Générateur Photos IA"),
        content: Text("J'ai trouvé ${missing.length} produits sans image.\n\nLancer la recherche automatique ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: const Text("Lancer", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );

    if (confirm != true) return;

    if (!mounted) return;
    final progressCtrl = StreamController<int>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StreamBuilder<int>(
        stream: progressCtrl.stream,
        initialData: 0,
        builder: (ctx, snap) {
          final current = snap.data ?? 0;
          final percent = (missing.isEmpty) ? 0.0 : (current / missing.length);
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Recherche IA en cours...", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                LinearProgressIndicator(value: percent, color: Colors.deepPurple, backgroundColor: Colors.deepPurple.withOpacity(0.1)),
                const SizedBox(height: 10),
                Text("$current / ${missing.length}"),
              ],
            ),
          );
        },
      )
    );

    int success = 0;
    int errors = 0;

    for (int i = 0; i < missing.length; i++) {
      progressCtrl.add(i + 1);
      final p = missing[i];
      try {
        final query = "${p['name']} ${p['category'] ?? ''} produit";
        final url = await _api.fetchAiProductImage(query);
        if (url != null) {
          final resp = await http.get(Uri.parse(url));
          if (resp.statusCode == 200) {
            final dir = await getTemporaryDirectory();
            final file = File('${dir.path}/ai_${p['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await file.writeAsBytes(resp.bodyBytes);
            final ok = await _api.updateProductImage(p['id'], file);
            if (ok) success++; else errors++;
          }
        }
      } catch (e) { errors++; }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    Navigator.pop(context); 
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Terminé ! $success ajouts."), backgroundColor: success > 0 ? Colors.green : Colors.orange));
    _fetchCatalog(); 
  }

  void _showAddProductSheet() {
    final catsForAdd = _categories.where((c) => c != 'Tout').toList();
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddProductModal(
        api: _api,
        existingCategories: catsForAdd,
        existingSubCategories: _subCategories,
        onSuccess: () { _fetchCatalog(silent: false); },
      ),
    );
  }

void _openProductSheet(Map<String, dynamic> product) {
    final catsForAdd = _categories.where((c) => c != 'Tout').toList();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductDetailsSheet(
        product: product,
        existingCategories: catsForAdd,
        existingSubCategories: _subCategories,
        onStockUpdate: (id, qty) async {
          await _api.sendStockUpdate(id, qty, 'SET');
          _fetchCatalog(silent: true);
        },
        onProductUpdate: (updatedData) {
          _api.updateProductOptimistic(updatedData);
          _fetchCatalog(silent: true); 
        },
      ),
    );
  }

  Widget _buildSmartFilterBtn(String id, String label, IconData icon, Color color, bool isDark) {
    final bool isActive = _activeSmartFilter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () { setState(() { _activeSmartFilter = isActive ? 'none' : id; _applyFilters(); }); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87))),
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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("INVENTAIRE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent, letterSpacing: 1.5)),
                          Text("Produits", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                        ],
                      ),
                      
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _startMagicImageFill,
                            child: Container(
                              width: 45, height: 45,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(color: Colors.deepPurple, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.deepPurple.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]),
                              child: const Icon(FontAwesomeIcons.wandMagicSparkles, color: Colors.white, size: 20),
                            ),
                          ),
                          GestureDetector(
                            onTap: _showAddProductSheet,
                            child: Container(
                              width: 45, height: 45,
                              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]),
                              child: const Icon(Icons.add, color: Colors.white, size: 24),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  Container(
                    height: 50,
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF1C1C1E) : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!)),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => _applyFilters(),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        hintText: "Chercher (Nom, Réf, Code)...",
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
                          onPressed: () => _scanBarcode(_searchController, autoSearch: true),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () { setState(() { _selectedCategory = cat; _updateSubCategoryList(); _applyFilters(); }); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF2D2D44) : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: isSelected ? Colors.transparent : (isDark ? Colors.white10 : Colors.grey[400]!)),
                        ),
                        child: Text(cat, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            
            if (_currentSubCategories.isNotEmpty) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: _currentSubCategories.map((sub) {
                    final isSelected = _selectedSubCategory == sub;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () { setState(() { _selectedSubCategory = sub; _applyFilters(); }); },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.withOpacity(0.3)),
                          ),
                          child: Text(sub, style: TextStyle(fontSize: 11, color: isSelected ? AppColors.primary : Colors.grey, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 10),
            
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    onRefresh: () async {
                      await _fetchCatalog(silent: false);
                    },
                    color: AppColors.primary,
                    child: _filteredProducts.isEmpty 
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.search_off, size: 50, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 10), Text("Aucun article trouvé", style: TextStyle(color: Colors.grey[500]))]))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 80),
                          physics: const BouncingScrollPhysics(),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (ctx, i) {
                            final p = Map<String, dynamic>.from(_filteredProducts[i] as Map);
                            final stock = double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
                            final price = double.tryParse(p['price']?.toString() ?? '0') ?? 0;
                            final minStock = double.tryParse(p['min_stock']?.toString() ?? '5') ?? 5;
                            final isFav = (int.tryParse(p['is_favorite']?.toString() ?? '0') ?? 0) == 1;
                            final isLow = stock <= minStock;
                            final totalSold = int.tryParse(p['total_sold']?.toString() ?? '0') ?? 0;
                            final imgUrl = p['base_image_path'];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GestureDetector(
                                onTap: () => _openProductSheet(p),
                                child: GlassCard(
                                  isDark: isDark,
                                  padding: const EdgeInsets.all(12),
                                  borderRadius: 18,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 55, height: 55,
                                        decoration: BoxDecoration(
                                          color: isLow ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1), 
                                          borderRadius: BorderRadius.circular(15),
                                          image: (imgUrl != null && imgUrl.toString().length > 2)
                                            ? DecorationImage(
                                                image: (imgUrl.toString().startsWith('http')) 
                                                  ? NetworkImage(imgUrl) as ImageProvider 
                                                  : FileImage(File(imgUrl)),              
                                              fit: BoxFit.cover
                                            ) 
                                            : null
                                        ),
                                        child: (imgUrl == null || imgUrl.toString().length <= 2) 
                                          ? Icon(isLow ? FontAwesomeIcons.triangleExclamation : FontAwesomeIcons.boxOpen, color: isLow ? Colors.red : Colors.blue, size: 22)
                                          : null,
                                      ),
                                      const SizedBox(width: 15),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(child: Text(p['name'] ?? 'Inconnu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                                if (isFav) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.favorite, color: Colors.pink, size: 16))
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                                Text("${p['category'] ?? 'Divers'}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                                if (p['sub_category'] != null) Text(" > ${p['sub_category']}", style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                                                if (totalSold > 50) ...[const SizedBox(width: 5), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: const Text("Top", style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold)))]
                                            ])
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text("${price.toStringAsFixed(0)} DA", style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 16)),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(color: isLow ? Colors.red : (isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]), borderRadius: BorderRadius.circular(6), border: Border.all(color: isLow ? Colors.red : Colors.transparent)),
                                            child: Text("Qté: ${stock.toInt()}", style: TextStyle(fontSize: 11, color: isLow ? Colors.white : (isDark ? Colors.white70 : Colors.black54), fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddProductModal extends StatefulWidget {
  final ApiService api;
  final VoidCallback onSuccess;
  final List<String> existingCategories;
  final List<String> existingSubCategories;

  const AddProductModal({
    super.key, 
    required this.api, 
    required this.onSuccess, 
    required this.existingCategories, 
    required this.existingSubCategories
  });

  @override
  State<AddProductModal> createState() => _AddProductModalState();
}

class _AddProductModalState extends State<AddProductModal> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;

  final _nameCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _catCtrl = TextEditingController();
  final _subCatCtrl = TextEditingController();
  final _costCtrl = TextEditingController();       
  final _priceCtrl = TextEditingController();      
  final _priceSemiCtrl = TextEditingController();  
  final _priceWholCtrl = TextEditingController();  
  final _stockCtrl = TextEditingController();
  final _minStockCtrl = TextEditingController(text: '5');
  final _unitCtrl = TextEditingController(text: 'u');
  final _packingCtrl = TextEditingController(text: '1');
  
  DateTime? _expirationDate;
  final _warehouseCtrl = TextEditingController();
  final _aisleCtrl = TextEditingController();
  final _shelfCtrl = TextEditingController();

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    if (widget.existingCategories.isNotEmpty) {
      _catCtrl.text = widget.existingCategories.first;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _refCtrl.dispose();
    _barcodeCtrl.dispose();
    _catCtrl.dispose();
    _subCatCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _priceSemiCtrl.dispose();
    _priceWholCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    _unitCtrl.dispose();
    _packingCtrl.dispose();
    _warehouseCtrl.dispose();
    _aisleCtrl.dispose();
    _shelfCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source, imageQuality: 70);
      if (picked != null) {
        setState(() => _imageFile = File(picked.path));
      }
    } catch (e) {
      debugPrint("Erreur photo: $e");
    }
  }

  Future<void> _scan(TextEditingController ctrl) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AiBarcodeScanner(
          onDetect: (BarcodeCapture capture) {
            final String? scannedValue = capture.barcodes.first.rawValue;
            if (scannedValue != null) {
              Navigator.of(context).pop();
              setState(() {
                 ctrl.text = scannedValue;
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // On prépare la liste des emplacements
    List<Map<String, dynamic>> locations = [];
    if (_warehouseCtrl.text.isNotEmpty || _aisleCtrl.text.isNotEmpty) {
      locations.add({'warehouse': _warehouseCtrl.text, 'aisle': _aisleCtrl.text, 'shelf': _shelfCtrl.text});
    }

    // 1. GÉNÉRATION DE L'ID TEMPORAIRE ICI (Pour lier l'image au produit)
    final String tempId = "TEMP-${DateTime.now().millisecondsSinceEpoch}";

    // 2. On prépare l'objet avec cet ID
    final newProduct = {
      "id": tempId, // <--- IMPORTANT : On force l'ID
      "name": _nameCtrl.text.trim(),
      "price": double.tryParse(_priceCtrl.text) ?? 0,
      "cost": double.tryParse(_costCtrl.text) ?? 0,
      "stock": double.tryParse(_stockCtrl.text) ?? 0,
      "barcode": _barcodeCtrl.text.trim(),
      "ref": _refCtrl.text.trim(),
      "category": _catCtrl.text.trim(),
      "sub_category": _subCatCtrl.text.trim(),
      "price_semi": double.tryParse(_priceSemiCtrl.text) ?? 0,
      "price_whol": double.tryParse(_priceWholCtrl.text) ?? 0,
      "unit": _unitCtrl.text.trim(),
      "packing": double.tryParse(_packingCtrl.text) ?? 1,
      "min_stock": double.tryParse(_minStockCtrl.text) ?? 5,
      "expiration_date": _expirationDate?.toIso8601String().split('T')[0],
      "locations": locations,
      "characteristics": [],
      "variants": []
    };

    // 3. Ajout Instantané (Optimiste)
    widget.api.addProductOptimistic(newProduct);
    
    // 4. Gestion Image locale (On utilise le tempId créé plus haut)
    if (_imageFile != null) {
      // On lie l'image au bon ID temporaire
      ApiService().updateProductImage(tempId, _imageFile!); 
    }

    // 5. Fermeture immédiate
    if (mounted) {
      Navigator.pop(context); // Ferme le modal
      widget.onSuccess(); // Rafraîchit la liste derrière
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Produit ajouté !"), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E2C) : Colors.white;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.90,
        decoration: BoxDecoration(color: bgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(25))),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Nouvel Article", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primary,
              tabs: const [Tab(text: "Général"), Tab(text: "Tarifs"), Tab(text: "Stock"), Tab(text: "Divers")],
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildGeneralTab(isDark),
                    _buildPricesTab(isDark),
                    _buildStockTab(isDark),
                    _buildAdvancedTab(isDark),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: const Text("SAUVEGARDER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralTab(bool isDark) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Center(
        child: GestureDetector(
          onTap: () {
            showModalBottomSheet(context: context, builder: (ctx) => SafeArea(
              child: Wrap(children: [
                ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Prendre une photo'), onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); }),
                ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choisir depuis la galerie'), onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); }),
              ]),
            ));
          },
          child: Container(
            width: 120, height: 120,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              image: _imageFile != null ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover) : null
            ),
            child: _imageFile == null 
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_a_photo, size: 30, color: Colors.grey), SizedBox(height: 5), Text("Ajouter Photo", style: TextStyle(fontSize: 10, color: Colors.grey))]) 
              : null,
          ),
        ),
      ),
      _buildInput("Désignation *", Icons.article, _nameCtrl, isDark),
      Row(children: [
        Expanded(child: _buildInput("Code Barre", Icons.qr_code, _barcodeCtrl, isDark, withScan: true)), 
        const SizedBox(width: 15), 
        Expanded(child: _buildInput("Référence", Icons.tag, _refCtrl, isDark))
      ]),
      _buildInput("Catégorie", Icons.category, _catCtrl, isDark, suggestions: widget.existingCategories),
      _buildInput("Sous-Catégorie", Icons.subdirectory_arrow_right, _subCatCtrl, isDark, suggestions: widget.existingSubCategories),
    ]);
  }

  Widget _buildPricesTab(bool isDark) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      _buildInput("Prix Achat (HT)", Icons.money_off, _costCtrl, isDark, isNum: true),
      _buildInput("Prix Détail (TTC)", Icons.person, _priceCtrl, isDark, isNum: true),
      Row(children: [Expanded(child: _buildInput("P. Semi-Gros", Icons.store, _priceSemiCtrl, isDark, isNum: true)), const SizedBox(width: 15), Expanded(child: _buildInput("P. Gros", Icons.local_shipping, _priceWholCtrl, isDark, isNum: true))]),
    ]);
  }

  Widget _buildStockTab(bool isDark) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [Expanded(child: _buildInput("Stock Initial", Icons.inventory_2, _stockCtrl, isDark, isNum: true)), const SizedBox(width: 15), Expanded(child: _buildInput("Alerte Min", Icons.warning, _minStockCtrl, isDark, isNum: true))]),
      Row(children: [Expanded(child: _buildInput("Unité (ex: kg, L)", Icons.scale, _unitCtrl, isDark)), const SizedBox(width: 15), Expanded(child: _buildInput("Colisage", Icons.grid_view, _packingCtrl, isDark, isNum: true))]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text("EXPIRATION", style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700], fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
        ListTile(
          title: Text(_expirationDate == null ? "Aucune date" : _expirationDate.toString().split(' ')[0], style: TextStyle(color: isDark ? Colors.white : Colors.black)),
          trailing: const Icon(Icons.calendar_today, color: AppColors.primary),
          tileColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          onTap: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2040), initialDate: DateTime.now());
            if (d != null) setState(() => _expirationDate = d);
          },
        ),
      ]),
    ]);
  }

  Widget _buildAdvancedTab(bool isDark) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [Expanded(child: _buildInput("Entrepôt", Icons.warehouse, _warehouseCtrl, isDark)), const SizedBox(width: 10), Expanded(child: _buildInput("Allée", Icons.signpost, _aisleCtrl, isDark))]),
      _buildInput("Rayon / Etagère", Icons.shelves, _shelfCtrl, isDark),
      const SizedBox(height: 20),
      const Center(child: Text("Les variantes se gèrent après création.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
    ]);
  }

  Widget _buildInput(String label, IconData icon, TextEditingController ctrl, bool isDark, {bool isNum = false, List<String>? suggestions, bool withScan = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label.toUpperCase(), style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700], fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
        TextFormField(
          controller: ctrl,
          keyboardType: isNum ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.primary, size: 18),
            suffixIcon: withScan 
              ? IconButton(icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary), onPressed: () => _scan(ctrl))
              : (suggestions != null && suggestions.isNotEmpty)
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    onSelected: (String value) {
                      ctrl.text = value; 
                    },
                    itemBuilder: (BuildContext context) {
                      return suggestions.map((String choice) {
                        return PopupMenuItem<String>(
                          value: choice,
                          child: Text(choice),
                        );
                      }).toList();
                    },
                  )
                : null,
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ==============================================================================
// 3. FICHE DÉTAIL / MODIF (AVEC PHOTO EN ÉDITION + AFFICHAGE CORRIGÉ + SCANNER)
// ==============================================================================
class ProductDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final Function(int, double) onStockUpdate;
  final Function(Map<String, dynamic>) onProductUpdate;
  final List<String> existingCategories;
  final List<String> existingSubCategories;

  const ProductDetailsSheet({super.key, required this.product, required this.onStockUpdate, required this.onProductUpdate, required this.existingCategories, required this.existingSubCategories});

  @override
  State<ProductDetailsSheet> createState() => _ProductDetailsSheetState();
}

class _ProductDetailsSheetState extends State<ProductDetailsSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isEditing = false;

  late TextEditingController _nameCtrl, _refCtrl, _barcodeCtrl, _catCtrl, _subCatCtrl;
  late TextEditingController _costCtrl, _priceCtrl, _priceSemiCtrl, _priceWholCtrl;
  late TextEditingController _minStockCtrl, _unitCtrl, _packingCtrl;
  late TextEditingController _warehouseCtrl, _aisleCtrl, _shelfCtrl;

  File? _newImageFile; 
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final p = widget.product;

    _nameCtrl = TextEditingController(text: p['name'] ?? '');
    _refCtrl = TextEditingController(text: p['ref'] ?? '');
    _barcodeCtrl = TextEditingController(text: p['barcode'] ?? '');
    _catCtrl = TextEditingController(text: p['category'] ?? 'Divers');
    _subCatCtrl = TextEditingController(text: p['sub_category'] ?? '');
    
    _costCtrl = TextEditingController(text: p['cost']?.toString() ?? '0');
    _priceCtrl = TextEditingController(text: p['price']?.toString() ?? '0');
    _priceSemiCtrl = TextEditingController(text: p['price_semi']?.toString() ?? '0');
    _priceWholCtrl = TextEditingController(text: p['price_whol']?.toString() ?? '0');

    _minStockCtrl = TextEditingController(text: p['min_stock']?.toString() ?? '5');
    _unitCtrl = TextEditingController(text: p['unit'] ?? 'u');
    _packingCtrl = TextEditingController(text: p['packing']?.toString() ?? '1');

    List locs = (p['locations'] is List) ? p['locations'] : [];
    var firstLoc = locs.isNotEmpty ? locs[0] : {};
    _warehouseCtrl = TextEditingController(text: firstLoc['warehouse'] ?? '');
    _aisleCtrl = TextEditingController(text: firstLoc['aisle'] ?? '');
    _shelfCtrl = TextEditingController(text: firstLoc['shelf'] ?? '');
  }

  Future<void> _pickNewImage() async {
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(
      child: Wrap(children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Prendre une photo'), onTap: () async { 
          Navigator.pop(ctx); 
          final XFile? img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
          if (img != null) setState(() => _newImageFile = File(img.path));
        }),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galerie'), onTap: () async { 
          Navigator.pop(ctx); 
          final XFile? img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
          if (img != null) setState(() => _newImageFile = File(img.path));
        }),
      ]),
    ));
  }

  // Fonction Scan pour la modification
  Future<void> _scan(TextEditingController ctrl) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AiBarcodeScanner(
          onDetect: (BarcodeCapture capture) {
            final String? scannedValue = capture.barcodes.first.rawValue;
            if (scannedValue != null) {
              Navigator.of(context).pop();
              setState(() {
                 ctrl.text = scannedValue;
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

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose(); _refCtrl.dispose(); _barcodeCtrl.dispose(); _catCtrl.dispose(); _subCatCtrl.dispose();
    _costCtrl.dispose(); _priceCtrl.dispose(); _priceSemiCtrl.dispose(); _priceWholCtrl.dispose();
    _minStockCtrl.dispose(); _unitCtrl.dispose(); _packingCtrl.dispose();
    _warehouseCtrl.dispose(); _aisleCtrl.dispose(); _shelfCtrl.dispose();
    super.dispose();
  }

  void _saveChanges() {
    if (_newImageFile != null) {
      ApiService().updateProductImage(widget.product['id'], _newImageFile!);
    }

    List<Map<String, dynamic>> locs = [];
    if (_warehouseCtrl.text.isNotEmpty || _aisleCtrl.text.isNotEmpty) {
      locs.add({'warehouse': _warehouseCtrl.text, 'aisle': _aisleCtrl.text, 'shelf': _shelfCtrl.text});
    }

    final updatedData = {
      "id": widget.product['id'],
      "name": _nameCtrl.text.trim(),
      "category": _catCtrl.text.trim(),
      "sub_category": _subCatCtrl.text.trim(),
      "barcode": _barcodeCtrl.text.trim(),
      "ref": _refCtrl.text.trim(),
      "price": double.tryParse(_priceCtrl.text) ?? 0,
      "cost": double.tryParse(_costCtrl.text) ?? 0,
      "price_semi": double.tryParse(_priceSemiCtrl.text) ?? 0,
      "price_whol": double.tryParse(_priceWholCtrl.text) ?? 0,
      "min_stock": double.tryParse(_minStockCtrl.text) ?? 5,
      "unit": _unitCtrl.text.trim(),
      "packing": double.tryParse(_packingCtrl.text) ?? 1,
      "locations": locs,
      "characteristics": widget.product['characteristics'],
      "variants": widget.product['variants']
    };
    
    widget.onProductUpdate(updatedData);
    Navigator.pop(context);
  }

  void _showStockCorrectionDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Correction Stock"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Quantité Réelle", border: OutlineInputBorder(), suffixIcon: Icon(Icons.numbers)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              double? qty = double.tryParse(controller.text);
              if (qty != null) {
                widget.onStockUpdate(widget.product['id'], qty);
                Navigator.pop(ctx); Navigator.pop(context); 
              }
            },
            child: const Text("Valider", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92, 
        decoration: BoxDecoration(color: bgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_isEditing ? "Modifier Produit" : "Détails Produit", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                  Row(children: [
                    IconButton(
                      icon: Icon(_isEditing ? Icons.save : Icons.edit, color: AppColors.primary),
                      onPressed: () { if (_isEditing) _saveChanges(); else setState(() => _isEditing = true); },
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () { if(_isEditing) setState(() => _isEditing = false); else Navigator.pop(context); }),
                  ])
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primary,
              tabs: const [Tab(text: "Info & Prix"), Tab(text: "Stock & Var"), Tab(text: "Empl.")],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  SingleChildScrollView(padding: const EdgeInsets.all(20), child: _isEditing ? _buildEditInfo(isDark) : _buildViewInfo(isDark)),
                  SingleChildScrollView(padding: const EdgeInsets.all(20), child: _isEditing ? _buildEditStock(isDark) : _buildViewStock(isDark)),
                  SingleChildScrollView(padding: const EdgeInsets.all(20), child: _isEditing ? _buildEditLocation(isDark) : _buildViewLocation(isDark)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- MODE LECTURE ---
  Widget _buildViewInfo(bool isDark) {
    final p = widget.product;
    final price = double.tryParse(p['price'].toString()) ?? 0;
    final cost = double.tryParse(p['cost']?.toString() ?? '0') ?? 0;
    final margin = price - cost;
    final marginPercent = price > 0 ? (margin / price * 100) : 0;

    final String? imgPath = p['base_image_path']?.toString();
    final bool hasImage = imgPath != null && imgPath.length > 2;

    ImageProvider? imageProvider;
    if (hasImage) {
       if (imgPath!.startsWith('http')) {
         imageProvider = NetworkImage(imgPath);
       } else {
         imageProvider = FileImage(File(imgPath));
       }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 100, height: 100,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: Colors.grey[200],
              image: imageProvider != null 
                ? DecorationImage(image: imageProvider, fit: BoxFit.cover) 
                : null
            ),
            child: imageProvider == null
              ? const Icon(Icons.image, size: 40, color: Colors.grey)
              : null,
          ),
        ),
        _buildSectionTitle("Identification"),
        _buildStatRow("Nom", p['name'], "Catégorie", "${p['category'] ?? ''} ${p['sub_category'] != null ? '> ' + p['sub_category'] : ''}", isDark),
        const SizedBox(height: 10),
        _buildStatRow("Réf", p['ref'] ?? '-', "Code-Barre", p['barcode'] ?? '-', isDark),

        const SizedBox(height: 25),
        _buildSectionTitle("Tarification"),
        Row(children: [
          Expanded(child: _buildStatCard("Achat (HT)", "${p['cost']} DA", Colors.orange, isDark)),
          const SizedBox(width: 10),
          Expanded(child: _buildStatCard("Vente (Détail)", "${p['price']} DA", AppColors.primary, isDark)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _buildStatCard("Semi-Gros", "${p['price_semi'] ?? 0} DA", Colors.teal, isDark)),
          const SizedBox(width: 10),
          Expanded(child: _buildStatCard("Gros", "${p['price_whol'] ?? 0} DA", Colors.indigo, isDark)),
        ]),
        const SizedBox(height: 10),
        Center(child: Text("Marge Unitaire : ${margin.toStringAsFixed(0)} DA (${marginPercent.toStringAsFixed(1)}%)", style: TextStyle(color: marginPercent > 20 ? Colors.green : Colors.red, fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _buildViewStock(bool isDark) {
    final p = widget.product;
    final stock = double.tryParse(p['stock']?.toString() ?? '0') ?? 0;
    final variants = List.from(p['variants'] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.withOpacity(0.2))),
          child: Row(children: [
            const Icon(Icons.inventory_2, size: 40, color: Colors.blue),
            const SizedBox(width: 20),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Stock Actuel", style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey)),
              Text("${stock.toInt()} ${p['unit'] ?? 'u'}", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            ]),
            const Spacer(),
            ElevatedButton(onPressed: _showStockCorrectionDialog, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: const CircleBorder(), padding: const EdgeInsets.all(12)), child: const Icon(Icons.edit, color: Colors.white))
          ]),
        ),
        const SizedBox(height: 25),
        _buildSectionTitle("Logistique"),
        _buildStatRow("Unité", p['unit'] ?? 'u', "Colisage", "Par ${p['packing'] ?? 1}", isDark),
        const SizedBox(height: 10),
        _buildStatRow("Alerte Min", "${p['min_stock'] ?? 5}", "Expiration", p['expiration_date'] ?? '-', isDark),
        
        if (variants.isNotEmpty) ...[
          const SizedBox(height: 25),
          _buildSectionTitle("Variantes (${variants.length})"),
          Container(
            decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.withOpacity(0.2))),
            child: Column(children: variants.map<Widget>((v) => ListTile(
              title: Text(v['sku'] ?? 'Variante', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
              subtitle: Text("Stock: ${v['stock']}", style: TextStyle(color: isDark ? Colors.white60 : Colors.grey)),
              trailing: Text("${v['price']} DA", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 15)),
              dense: true,
            )).toList()),
          )
        ]
      ],
    );
  }

  Widget _buildViewLocation(bool isDark) {
    final p = widget.product;
    List locs = (p['locations'] is List) ? p['locations'] : [];
    var loc = locs.isNotEmpty ? locs[0] : {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Emplacement Principal"),
        _buildStatRow("Entrepôt", loc['warehouse'] ?? '-', "Allée", loc['aisle'] ?? '-', isDark),
        const SizedBox(height: 10),
        _buildStatRow("Rayon", loc['shelf'] ?? '-', "Casier/Bin", loc['bin'] ?? '-', isDark),
        const SizedBox(height: 40),
        Center(child: Icon(Icons.map, size: 80, color: Colors.grey.withOpacity(0.2))),
        const Center(child: Text("Gestion multi-dépôts bientôt disponible", style: TextStyle(color: Colors.grey)))
      ],
    );
  }

  // --- MODE EDITION ---
  Widget _buildEditInfo(bool isDark) {
    final String? existingImgPath = widget.product['base_image_path']?.toString();
    final bool hasExistingImage = existingImgPath != null && existingImgPath.length > 2;

    ImageProvider? bgImage;
    if (_newImageFile != null) {
      bgImage = FileImage(_newImageFile!); 
    } else if (hasExistingImage) {
      if (existingImgPath!.startsWith('http')) {
        bgImage = NetworkImage(existingImgPath);
      } else {
        bgImage = FileImage(File(existingImgPath));
      }
    }

    return Column(children: [
      
      Center(
        child: GestureDetector(
          onTap: _pickNewImage,
          child: Container(
            width: 100, height: 100,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey[200],
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              image: bgImage != null 
                ? DecorationImage(image: bgImage, fit: BoxFit.cover)
                : null
            ),
            child: bgImage == null
              ? const Icon(Icons.camera_alt, size: 30, color: Colors.grey)
              : null,
          ),
        ),
      ),

      _buildInput("Désignation Produit", Icons.article, _nameCtrl, isDark),
      
      // ✅ SCANNER AJOUTÉ ICI POUR LE CODE BARRE (MODIFICATION)
      Row(children: [
        Expanded(child: _buildInput("Référence", Icons.tag, _refCtrl, isDark)), 
        const SizedBox(width: 10), 
        Expanded(child: _buildInput("Code-Barre", Icons.qr_code, _barcodeCtrl, isDark, withScan: true))
      ]),
      
      _buildInput("Catégorie", Icons.category, _catCtrl, isDark, suggestions: widget.existingCategories),
      _buildInput("Sous-Catégorie", Icons.subdirectory_arrow_right, _subCatCtrl, isDark, suggestions: widget.existingSubCategories),
      
      const Divider(height: 30),
      Row(children: [Expanded(child: _buildInput("Achat (HT)", Icons.money_off, _costCtrl, isDark, isNum: true)), const SizedBox(width: 10), Expanded(child: _buildInput("Vente (Détail)", Icons.person, _priceCtrl, isDark, isNum: true))]),
      Row(children: [Expanded(child: _buildInput("Semi-Gros", Icons.store, _priceSemiCtrl, isDark, isNum: true)), const SizedBox(width: 10), Expanded(child: _buildInput("Gros", Icons.local_shipping, _priceWholCtrl, isDark, isNum: true))]),
    ]);
  }

  Widget _buildEditStock(bool isDark) {
    return Column(children: [
      _buildInput("Stock Alerte (Min)", Icons.warning, _minStockCtrl, isDark, isNum: true),
      Row(children: [Expanded(child: _buildInput("Unité (kg, L, u)", Icons.scale, _unitCtrl, isDark)), const SizedBox(width: 10), Expanded(child: _buildInput("Colisage", Icons.grid_view, _packingCtrl, isDark, isNum: true))]),
      const SizedBox(height: 30),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.withOpacity(0.3))),
        child: const Text("⚠️ Pour modifier les variantes ou l'historique de stock complexe, veuillez utiliser la version PC.", textAlign: TextAlign.center, style: TextStyle(color: Colors.orange, fontSize: 12)),
      )
    ]);
  }

  Widget _buildEditLocation(bool isDark) {
    return Column(children: [
      _buildInput("Entrepôt", Icons.warehouse, _warehouseCtrl, isDark),
      Row(children: [Expanded(child: _buildInput("Allée", Icons.signpost, _aisleCtrl, isDark)), const SizedBox(width: 10), Expanded(child: _buildInput("Rayon / Etagère", Icons.shelves, _shelfCtrl, isDark))]),
    ]);
  }

  // ✅ MODIFIÉ POUR INCLURE LE SCANNER
  Widget _buildInput(String label, IconData icon, TextEditingController ctrl, bool isDark, {bool isNum = false, List<String>? suggestions, bool withScan = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label.toUpperCase(), style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700], fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
        TextFormField(
          controller: ctrl,
          keyboardType: isNum ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.primary, size: 18),
            suffixIcon: withScan 
              ? IconButton(icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary), onPressed: () => _scan(ctrl))
              : (suggestions != null && suggestions.isNotEmpty)
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    onSelected: (String value) {
                      ctrl.text = value; 
                    },
                    itemBuilder: (BuildContext context) {
                      return suggestions.map((String choice) {
                        return PopupMenuItem<String>(
                          value: choice,
                          child: Text(choice),
                        );
                      }).toList();
                    },
                  )
                : null,
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSectionTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(title.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey[600])));

  Widget _buildStatRow(String l1, String v1, String l2, String v2, bool isDark) {
    return Row(children: [
      Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withOpacity(0.2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l1, style: const TextStyle(fontSize: 11, color: Colors.grey)), Text(v1, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87))]))),
      const SizedBox(width: 10),
      Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withOpacity(0.2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l2, style: const TextStyle(fontSize: 11, color: Colors.grey)), Text(v2, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87))]))),
    ]);
  }

  Widget _buildStatCard(String label, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C35) : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.3)), boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey[600], fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color))]),
    );
  }
}