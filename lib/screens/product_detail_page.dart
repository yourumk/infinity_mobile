import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../core/constants.dart';
import '../models/article_model.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class ProductDetailPage extends StatefulWidget {
  final ArticleModel product;

  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  final ApiService _api = ApiService();
  late ArticleModel _displayProduct;
  bool _isLoading = true;
  Map<String, dynamic> _fullDetails = {};

  @override
  void initState() {
    super.initState();
    _displayProduct = widget.product;
    _loadFullDetails();
  }

  Future<void> _loadFullDetails() async {
    try {
      final fullData = await _api.getProductFullDetails(widget.product.id);
      
      if (mounted) {
        setState(() {
          if (fullData.isNotEmpty) {
            _fullDetails = fullData;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = _displayProduct;

    // Utilisation des données complètes si disponibles, sinon données de base
    final stock = _fullDetails['base_stock'] ?? p.stock;
    final price = _fullDetails['base_price_retail_ttc'] ?? p.price;
    final cost = _fullDetails['base_purchase_price'] ?? p.cost;
    final category = _fullDetails['family'] ?? p.category;
    final barcode = _fullDetails['base_reference'] ?? p.barcode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text("Détails Produit"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // IMAGE & NOM
            Center(
              child: Column(
                children: [
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(FontAwesomeIcons.boxOpen, size: 40, color: AppColors.primary),
                  ),
                  const SizedBox(height: 15),
                  Text(p.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                  const SizedBox(height: 5),
                  Text(category, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            
            const SizedBox(height: 30),

            // STATS CLÉS
            Row(
              children: [
                Expanded(child: _buildStatCard("Prix Vente", "${price} DA", Colors.green, isDark)),
                const SizedBox(width: 15),
                Expanded(child: _buildStatCard("Stock", "$stock", stock <= 5 ? Colors.red : Colors.blue, isDark)),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _buildStatCard("Coût Achat", "${cost} DA", Colors.orange, isDark)),
                const SizedBox(width: 15),
                Expanded(child: _buildStatCard("Marge", "${(price - cost)} DA", Colors.purple, isDark)),
              ],
            ),

            const SizedBox(height: 30),

            // INFOS TECHNIQUES
            Text("Informations Techniques", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 15),
            
            GlassCard(
              isDark: isDark,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildDetailRow("Référence / Code", barcode, isDark),
                  const Divider(),
                  _buildDetailRow("Famille", category, isDark),
                  const Divider(),
                  _buildDetailRow("Fournisseur", _fullDetails['supplier_name'] ?? "Non spécifié", isDark),
                  const Divider(),
                  _buildDetailRow("Emplacement", _fullDetails['location_aisle'] ?? "-", isDark),
                ],
              ),
            ),

            if (_isLoading)
              const Padding(padding: EdgeInsets.all(20.0), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
      ],
    );
  }
}