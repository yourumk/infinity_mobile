class KpiModel {
  final double salesToday;
  final double profitToday;
  final int salesCount;
  final double treasury;
  final double stockValue;
  final double clientCredit;
  final double supplierDebt;
  final double capital;
  final int alertsLow;
  final int alertsExpiry;

  KpiModel({
    this.salesToday = 0.0,
    this.profitToday = 0.0,
    this.salesCount = 0,
    this.treasury = 0.0,
    this.stockValue = 0.0,
    this.clientCredit = 0.0,
    this.supplierDebt = 0.0,
    this.capital = 0.0,
    this.alertsLow = 0,
    this.alertsExpiry = 0,
  });

  factory KpiModel.fromJson(Map<String, dynamic> json) {
    // Sécurité : si les données sont dans 'dashboard' ou à la racine
    final data = json['dashboard'] != null ? json['dashboard'] : json;

    return KpiModel(
      salesToday: double.tryParse(data['sales_today']?.toString() ?? '0') ?? 0.0,
      profitToday: double.tryParse(data['profit_today']?.toString() ?? '0') ?? 0.0,
      salesCount: int.tryParse(data['sales_count']?.toString() ?? '0') ?? 0,
      treasury: double.tryParse(data['treasury']?.toString() ?? '0') ?? 0.0,
      stockValue: double.tryParse(data['stock_value']?.toString() ?? '0') ?? 0.0,
      clientCredit: double.tryParse(data['client_credit']?.toString() ?? '0') ?? 0.0,
      supplierDebt: double.tryParse(data['supplier_debt']?.toString() ?? '0') ?? 0.0,
      capital: double.tryParse(data['capital']?.toString() ?? '0') ?? 0.0,
      alertsLow: int.tryParse(data['alerts_low']?.toString() ?? '0') ?? 0,
      alertsExpiry: int.tryParse(data['alerts_expiry']?.toString() ?? '0') ?? 0,
    );
  }
}