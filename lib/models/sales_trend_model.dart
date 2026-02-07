class SalesTrendModel {
  final String label;
  final double value;

  SalesTrendModel({required this.label, required this.value});

  factory SalesTrendModel.fromJson(Map<String, dynamic> json) {
    return SalesTrendModel(
      label: json['label'] as String? ?? 'N/A',
      // L'API renvoie souvent des entiers ou des chaînes, on le force en double
      value: (json['value'] as num?)?.toDouble() ?? 0.0, 
    );
  }
}