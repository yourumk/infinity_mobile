class DashboardData {
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

  DashboardData({
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

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final dashboard = json['dashboard'] ?? {};
    return DashboardData(
      salesToday: double.tryParse(dashboard['sales_today']?.toString() ?? '0') ?? 0.0,
      profitToday: double.tryParse(dashboard['profit_today']?.toString() ?? '0') ?? 0.0,
      salesCount: int.tryParse(dashboard['sales_count']?.toString() ?? '0') ?? 0,
      treasury: double.tryParse(dashboard['treasury']?.toString() ?? '0') ?? 0.0,
      stockValue: double.tryParse(dashboard['stock_value']?.toString() ?? '0') ?? 0.0,
      clientCredit: double.tryParse(dashboard['client_credit']?.toString() ?? '0') ?? 0.0,
      supplierDebt: double.tryParse(dashboard['supplier_debt']?.toString() ?? '0') ?? 0.0,
      capital: double.tryParse(dashboard['capital']?.toString() ?? '0') ?? 0.0,
      alertsLow: int.tryParse(dashboard['alerts_low']?.toString() ?? '0') ?? 0,
      alertsExpiry: int.tryParse(dashboard['alerts_expiry']?.toString() ?? '0') ?? 0,
    );
  }
}