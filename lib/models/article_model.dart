class ArticleModel {
  final int id;
  final String name;
  final String ref;
  final String family;
  final String supplierName;
  final String? imagePath; 
  final double price;
  final double stock;
  
  // On remet le champ caractéristiques
  final Map<String, dynamic> characteristics; 

  ArticleModel({
    required this.id,
    required this.name,
    required this.ref,
    required this.family,
    required this.supplierName,
    this.imagePath,
    required this.price,
    required this.stock,
    this.characteristics = const {},
  });

  factory ArticleModel.fromJson(Map<String, dynamic> json) {
    // On remet la logique de lecture des caractéristiques
    Map<String, dynamic> chars = {};
    if (json['characteristics_json'] != null) {
      if (json['characteristics_json'] is Map) {
        chars = Map<String, dynamic>.from(json['characteristics_json']);
      }
    }

    return ArticleModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'Article Inconnu',
      ref: json['ref'] as String? ?? '',
      family: json['family'] as String? ?? 'Général',
      supplierName: json['supplier_name'] as String? ?? 'N/A',
      imagePath: json['base_image_path'] as String?,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      stock: (json['stock'] as num?)?.toDouble() ?? 0.0,
      characteristics: chars,
    );
  }
}