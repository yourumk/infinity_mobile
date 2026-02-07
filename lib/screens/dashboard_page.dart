import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import '../providers/data_provider.dart';
import '../models/sales_trend_model.dart';
import '../widgets/glass_card.dart';

// Imports pour la navigation
import 'sales_page.dart';
import 'charges_page.dart';
import 'purchases_page.dart';
import 'articles_page.dart';
import 'tiers_page.dart';     
import 'alerts_page.dart';    
import 'history_page.dart';   

class DashboardPage extends StatefulWidget {
  final Function(int) onNavigateToTab; 
  final VoidCallback onOpenSettings;

  const DashboardPage({
    super.key, 
    required this.onNavigateToTab,
    required this.onOpenSettings,
  }); 

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ApiService _api = ApiService();
  
  // GESTION DES ONGLETS DU BAS
  int _currentTabIndex = 0;
  final PageController _pageController = PageController();
  
  // GESTION DES CHARTS (CARROUSEL)
  final PageController _chartController = PageController();
  int _currentChartIndex = 0;

  // Données locales pour les listes
  List<dynamic> _financeData = [];
  List<dynamic> _topProducts = [];
  List<dynamic> _recentPurchases = []; 
  List<dynamic> _sleepingStock = [];   

  @override
  void initState() {
    super.initState();
    ApiService().startAutoSync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<DataProvider>(context, listen: false);
      provider.startAutoRefresh();
      _loadTabsData();
      provider.addListener(_onProviderUpdate);
    });
  }

  @override
  void dispose() {
    try {
      Provider.of<DataProvider>(context, listen: false).removeListener(_onProviderUpdate);
    } catch(e) {}
    _pageController.dispose();
    _chartController.dispose();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;
    if (!Provider.of<DataProvider>(context, listen: false).isLoading) {
       _loadTabsData();
    }
  }

  // --- HELPERS ---
  List<dynamic> _safeList(dynamic data) => (data is List) ? data : [];
  String _safeString(dynamic val, [String d = '']) => val?.toString() ?? d;
  
  String _safeDate(dynamic dateStr) {
    if (dateStr == null) return '---';
    String s = dateStr.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  double _safeDouble(dynamic val) => double.tryParse(val?.toString() ?? '0') ?? 0.0;
  int _safeInt(dynamic val) => int.tryParse(val?.toString() ?? '0') ?? 0;

  String fmtMoney(dynamic amount) {
    return NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(_safeDouble(amount));
  }

  Future<void> _loadTabsData() async {
    try {
      final data = await _api.fetchDashboardData();
      if (mounted) {
        setState(() {
          final tables = data['tables'];
          if (tables is Map) {
            _financeData = _safeList(tables['finance']);
            _topProducts = _safeList(tables['top_products']);
            _recentPurchases = _safeList(tables['purchases']);
            
            if (tables['sleeping_stock'] != null) {
                 _sleepingStock = _safeList(tables['sleeping_stock']);
            } else if (tables['charges'] != null && (tables['charges'] as List).isNotEmpty) {
                 _sleepingStock = _safeList(tables['charges']); 
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Erreur chargement tabs: $e");
    }
  }

  void _navTo(int index) => widget.onNavigateToTab(index);

  void _onTabChanged(int index) {
    setState(() => _currentTabIndex = index);
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // --- OUVERTURE DES MODALES ---
  void _openDetailList(String type, String title, Color themeColor) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true, 
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DetailedListModal(
        api: _api, type: type, title: title, themeColor: themeColor,
      ),
    );
  }

  void _openDaySalesSheet(String date) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DaySalesModal(api: _api, date: date),
    );
  }

  void _openTransactionDetail(Map<String, dynamic> data, bool isSale) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => TransactionDetailSheet(api: _api, data: data, isSale: isSale),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dataProvider = Provider.of<DataProvider>(context);
    final dynamic kpi = dataProvider.dashboardData; 
    final isLoading = dataProvider.isLoading;
    
    // Extraction KPIs
    final double salesToday = kpi is Map ? _safeDouble(kpi['sales_today']) : (kpi.salesToday as double? ?? 0.0);
    final double profitToday = kpi is Map ? _safeDouble(kpi['profit_today']) : (kpi.profitToday as double? ?? 0.0);
    final double treasury = kpi is Map ? _safeDouble(kpi['treasury']) : (kpi.treasury as double? ?? 0.0);
    final double capital = kpi is Map ? _safeDouble(kpi['capital']) : (kpi.capital as double? ?? 0.0);
    final double stockValue = kpi is Map ? _safeDouble(kpi['stock_value']) : (kpi.stockValue as double? ?? 0.0);
    final double clientCredit = kpi is Map ? _safeDouble(kpi['client_credit']) : (kpi.clientCredit as double? ?? 0.0);
    final double supplierDebt = kpi is Map ? _safeDouble(kpi['supplier_debt']) : (kpi.supplierDebt as double? ?? 0.0);
    
    final int alertsLow = kpi is Map ? _safeInt(kpi['alerts_low']) : (kpi.alertsLow as int? ?? 0);
    final int alertsExpiry = kpi is Map ? _safeInt(kpi['alerts_expiry']) : (kpi.alertsExpiry as int? ?? 0);
    final int totalAlerts = alertsLow + alertsExpiry;
    final int salesCount = kpi is Map ? _safeInt(kpi['sales_count']) : (kpi.salesCount as int? ?? 0);

    final List<SalesTrendModel> cleanData = dataProvider.salesTrend.isNotEmpty 
        ? dataProvider.salesTrend 
        : [SalesTrendModel(label: 'N/A', value: 0)];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      body: isLoading && salesCount == 0
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
              onRefresh: () async {
                await dataProvider.loadData(forceRefresh: true);
                await _loadTabsData();
              },
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: MediaQuery.of(context).padding.top + 20), 
                      
                      // 1. HEADER
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("INFINITY POS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent, letterSpacing: 2)),
                                const SizedBox(height: 5),
                                Text(
                                  "Tableau de Bord",
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildHeaderBtn(FontAwesomeIcons.clockRotateLeft, isDark, () => _navTo(5)), 
                                const SizedBox(width: 8),
                                _buildHeaderBtn(FontAwesomeIcons.users, isDark, () => _navTo(6)),
                                const SizedBox(width: 8),
                                _buildHeaderBtn(FontAwesomeIcons.gear, isDark, widget.onOpenSettings),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _navTo(8),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Icon(Icons.notifications_none_rounded, color: isDark ? Colors.white : Colors.black, size: 22),
                                        if (totalAlerts > 0)
                                          Positioned(
                                            right: 0, top: 0,
                                            child: Container(
                                              width: 8, height: 8,
                                              decoration: BoxDecoration(color: AppColors.error, shape: BoxShape.circle, border: Border.all(color: AppColors.bgDark, width: 1.5)),
                                            ),
                                          )
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // 2. 🤖 AI DETECTOR
                      _buildAIDetector(isDark, salesToday, treasury, totalAlerts),

                      const SizedBox(height: 20),

                      // 3. 📊 CARROUSEL 3 GRAPHIQUES
                      SizedBox(
                        height: 280,
                        child: PageView(
                          controller: _chartController,
                          onPageChanged: (idx) => setState(() => _currentChartIndex = idx),
                          children: [
                            _buildMainChartSection(isDark, cleanData, fmtMoney(salesToday), "Évolution Ventes"),
                            _buildBarChartSection(isDark, "Performance (7 Jours)"),
                            _buildPieChartSection(isDark, salesToday, profitToday, "Répartition Marge"),
                          ],
                        ),
                      ),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentChartIndex == index ? AppColors.accent : Colors.grey.withOpacity(0.3),
                          ),
                        )),
                      ),

                      const SizedBox(height: 20),

                      // 4. KPI CARDS
                      Row(
                        children: [
                          Expanded(child: _buildSmallStatCard("Bénéfice", fmtMoney(profitToday), AppColors.success, FontAwesomeIcons.arrowTrendUp, isDark, () => _openDetailList('PROFIT', 'Journal des Profits', AppColors.success))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildSmallStatCard("Trésorerie", fmtMoney(treasury), Colors.blue, FontAwesomeIcons.wallet, isDark, () => _navTo(3))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildSmallStatCard("Achats", "Gestion", Colors.orange, FontAwesomeIcons.truckFast, isDark, () => _navTo(2))),
                        ],
                      ),
                      
                      const SizedBox(height: 15),

                      // 5. GRID DÉTAILS
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        childAspectRatio: 1.6,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        children: [
                          _buildDetailStatCard("Capital Total", fmtMoney(capital), Colors.amber, FontAwesomeIcons.coins, isDark, () {}),
                          _buildDetailStatCard("Valeur Stock", fmtMoney(stockValue), Colors.orange, FontAwesomeIcons.boxesStacked, isDark, () => _openDetailList('STOCK_VALUE', 'Top Valeur Stock', Colors.orange)),
                          _buildDetailStatCard("Crédit Clients", fmtMoney(clientCredit), Colors.redAccent, FontAwesomeIcons.handHoldingDollar, isDark, () => _openDetailList('CLIENT_DEBT', 'Crédits Clients', Colors.redAccent)),
                          _buildDetailStatCard("Dettes Fourn.", fmtMoney(supplierDebt), Colors.purpleAccent, FontAwesomeIcons.fileInvoiceDollar, isDark, () => _openDetailList('SUPPLIER_DEBT', 'Dettes Fournisseurs', Colors.purpleAccent)),
                        ],
                      ),

                      const SizedBox(height: 25),

                      // 6. 🆕 NOUVEAU GRAPHIQUE D'ANALYSE FINANCIÈRE
                      // Comparaison visuelle Trésorerie vs Crédits vs Dettes
                      _buildDebtAnalysisChart(isDark, treasury, clientCredit, supplierDebt),

                      const SizedBox(height: 30),

                      // 7. LISTES ONGLETS
                      Container(
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(25)),
                        child: Column(
                          children: [
                            Container(
                              height: 50,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]
                              ),
                              child: Row(
                                children: [
                                  _buildSegment("Journal", 0, isDark),
                                  _buildSegment("Top Ventes", 1, isDark),
                                  _buildSegment("Achats", 2, isDark),
                                  _buildSegment("Dormant", 3, isDark),
                                ],
                              ),
                            ),
                            const SizedBox(height: 15),
                            SizedBox(
                              height: 400,
                              child: PageView(
                                controller: _pageController,
                                onPageChanged: (index) => setState(() => _currentTabIndex = index),
                                children: [
                                  _buildFinanceList(isDark),
                                  _buildTopProductsList(isDark),
                                  _buildPurchasesList(isDark), 
                                  _buildSleepingStockList(isDark), 
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ==========================================
  // 🆕 NOUVEAU WIDGET : ANALYSE DETTES
  // ==========================================
  Widget _buildDebtAnalysisChart(bool isDark, double treasury, double clientCredit, double supplierDebt) {
    // Calcul pour l'échelle
    double maxVal = [treasury, clientCredit, supplierDebt].reduce((curr, next) => curr > next ? curr : next);
    if (maxVal == 0) maxVal = 100; // Éviter division par zéro

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FontAwesomeIcons.scaleBalanced, color: isDark ? Colors.white : Colors.black, size: 18),
              const SizedBox(width: 10),
              Text("Analyse Financière", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 20),
          
          // Graphique à Barres Horizontal Custom
          _buildDebtBar("Trésorerie (Dispo)", treasury, maxVal, Colors.blue, isDark),
          const SizedBox(height: 15),
          _buildDebtBar("Crédit Clients (Entrées prévues)", clientCredit, maxVal, Colors.green, isDark),
          const SizedBox(height: 15),
          _buildDebtBar("Dettes Fournisseurs (Sorties)", supplierDebt, maxVal, Colors.redAccent, isDark),
          
          const SizedBox(height: 20),
          Container(
             padding: const EdgeInsets.all(10),
             decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
             child: Row(
               children: [
                 const Icon(Icons.lightbulb_outline, color: Colors.orange, size: 20),
                 const SizedBox(width: 10),
                 Expanded(
                   child: Text(
                     (treasury + clientCredit) > supplierDebt 
                        ? "Situation Saine : Vos avoirs couvrent vos dettes." 
                        : "Attention : Vos dettes dépassent vos liquidités + crédits.",
                     style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                   ),
                 ),
               ],
             ),
          )
        ],
      ),
    );
  }

  Widget _buildDebtBar(String label, double value, double max, Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700], fontSize: 11)),
            Text(fmtMoney(value), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 5),
        Stack(
          children: [
            Container(height: 8, width: double.infinity, decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey[200], borderRadius: BorderRadius.circular(5))),
            FractionallySizedBox(
              widthFactor: (value / max).clamp(0.0, 1.0),
              child: Container(height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
            )
          ],
        )
      ],
    );
  }

  // ==========================================
  // 🤖 AI DETECTOR
  // ==========================================
  Widget _buildAIDetector(bool isDark, double sales, double treasury, int alerts) {
    String status = "Analyse en cours...";
    Color statusColor = Colors.blue;
    IconData statusIcon = FontAwesomeIcons.robot;
    String subtext = "L'IA surveille votre activité";

    if (alerts > 5) {
      status = "Attention Requise";
      statusColor = Colors.red;
      statusIcon = FontAwesomeIcons.triangleExclamation;
      subtext = "$alerts alertes stock critiques détectées";
    } else if (sales > treasury * 0.1 && sales > 0) {
      status = "Croissance Forte";
      statusColor = Colors.green;
      statusIcon = FontAwesomeIcons.chartLine;
      subtext = "Vos ventes dépassent les prévisions";
    } else if (sales == 0) {
      status = "Journée Calme";
      statusColor = Colors.grey;
      statusIcon = FontAwesomeIcons.moon;
      subtext = "Aucune vente pour le moment";
    } else {
      status = "Activité Normale";
      statusColor = AppColors.accent;
      statusIcon = FontAwesomeIcons.checkDouble;
      subtext = "Tous les indicateurs sont au vert";
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [statusColor.withOpacity(0.2), statusColor.withOpacity(0.05)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("IA DETECTOR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                    const SizedBox(width: 5),
                    Icon(Icons.bolt, size: 12, color: statusColor)
                  ],
                ),
                Text(status, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                Text(subtext, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 📈 CHART 1 : LIGNE
  // ==========================================
  Widget _buildMainChartSection(bool isDark, List<SalesTrendModel> cleanData, String totalSales, String title) {
     List<FlSpot> spots = cleanData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList();
     return Container(
       padding: const EdgeInsets.all(20),
       decoration: BoxDecoration(
         gradient: AppColors.primaryGradient,
         borderRadius: BorderRadius.circular(30),
         boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
       ),
       child: Column(
         children: [
           Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
               Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(title, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                   Text(totalSales, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                 ],
               ),
               Container(
                 padding: const EdgeInsets.all(10),
                 decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                 child: const Icon(FontAwesomeIcons.chartLine, color: Colors.white, size: 20),
               ),
             ],
           ),
           const SizedBox(height: 20),
           Expanded(
             child: LineChart(
               LineChartData(
                 gridData: FlGridData(show: false),
                 titlesData: FlTitlesData(show: false),
                 borderData: FlBorderData(show: false),
                 lineBarsData: [
                   LineChartBarData(
                     spots: spots,
                     isCurved: true,
                     color: Colors.white,
                     barWidth: 3,
                     dotData: FlDotData(show: false),
                     belowBarData: BarAreaData(show: true, color: Colors.white.withOpacity(0.2)),
                   ),
                 ],
               ),
             ),
           ),
         ],
       ),
     );
  }

  // ==========================================
  // 📊 CHARTE 2 : BARRES
  // ==========================================
  Widget _buildBarChartSection(bool isDark, String title) {
    List<dynamic> chartData = _financeData.take(7).toList().reversed.toList();
    
    return Container(
       padding: const EdgeInsets.all(20),
       decoration: BoxDecoration(
         color: isDark ? const Color(0xFF1C1C23) : Colors.white,
         borderRadius: BorderRadius.circular(30),
         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
       ),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
            Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            Expanded(
              child: BarChart(
                BarChartData(
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: false),
                  barGroups: chartData.asMap().entries.map((e) {
                    final item = e.value;
                    double sales = double.tryParse(item['total_revenue'].toString()) ?? 0;
                    double profit = double.tryParse(item['total_profit'].toString()) ?? 0;
                    
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(toY: sales, color: Colors.blueAccent, width: 8, borderRadius: BorderRadius.circular(4)),
                        BarChartRodData(toY: profit, color: Colors.greenAccent, width: 8, borderRadius: BorderRadius.circular(4)),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem(Colors.blueAccent, "CA"),
                const SizedBox(width: 15),
                _legendItem(Colors.greenAccent, "Profit"),
              ],
            )
         ],
       ),
    );
  }

  // ==========================================
  // 🍰 CHARTE 3 : CAMEMBERT
  // ==========================================
  Widget _buildPieChartSection(bool isDark, double sales, double profit, String title) {
    double cost = sales - profit;
    if(cost < 0) cost = 0;
    
    return Container(
       padding: const EdgeInsets.all(20),
       decoration: BoxDecoration(
         color: isDark ? const Color(0xFF1C1C23) : Colors.white,
         borderRadius: BorderRadius.circular(30),
         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
       ),
       child: Row(
         children: [
           Expanded(
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                 const SizedBox(height: 10),
                 _legendItem(Colors.purpleAccent, "Marge Nette"),
                 const SizedBox(height: 5),
                 _legendItem(Colors.orangeAccent, "Coût Produit"),
               ],
             ),
           ),
           SizedBox(
             width: 120,
             height: 120,
             child: sales == 0 
               ? Center(child: Text("0%", style: TextStyle(color: isDark ? Colors.white : Colors.black))) 
               : PieChart(
                 PieChartData(
                   sectionsSpace: 0,
                   centerSpaceRadius: 30,
                   sections: [
                     PieChartSectionData(value: profit, color: Colors.purpleAccent, radius: 25, showTitle: false),
                     PieChartSectionData(value: cost, color: Colors.orangeAccent, radius: 20, showTitle: false),
                   ],
                 ),
               ),
           ),
         ],
       ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // --- WIDGETS DE BASE ---

  Widget _buildSegment(String label, int index, bool isDark) {
    final isActive = _currentTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: isActive ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBtn(IconData icon, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10), 
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: Icon(icon, color: isDark ? Colors.white : Colors.black, size: 20),
      ),
    );
  }

  Widget _buildSmallStatCard(String title, String value, Color color, IconData icon, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C23) : Colors.white, 
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black))),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailStatCard(String title, String value, Color color, IconData icon, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C23) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.05)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const Spacer(),
            FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black))),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // --- LIST BUILDERS ---

  Widget _buildFinanceList(bool isDark) {
    if (_financeData.isEmpty) return const Center(child: Text("Aucune donnée"));
    return ListView.builder(
      padding: const EdgeInsets.all(15), 
      itemCount: _financeData.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, i) {
        final item = _financeData[i];
        return GestureDetector(
          onTap: () => _openDaySalesSheet(_safeString(item['day'])),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, 
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)]
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Row(children: [
                   const Icon(Icons.calendar_month, color: AppColors.primary),
                   const SizedBox(width: 10),
                   Text(_safeDate(item['day']), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                 ]),
                 Text("${fmtMoney(item['total_revenue'])} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopProductsList(bool isDark) {
    if (_topProducts.isEmpty) return const Center(child: Text("Pas assez de données"));
    return ListView.builder(
      padding: const EdgeInsets.all(15), 
      itemCount: _topProducts.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, i) {
        final p = _topProducts[i];
        return ListTile(
          leading: CircleAvatar(backgroundColor: AppColors.accent.withOpacity(0.2), child: Text("${i+1}")),
          title: Text(_safeString(p['name'], 'Produit'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
          subtitle: Text("${p['qty']} ventes"),
          trailing: Text("${fmtMoney(p['total_revenue'])}", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
        );
      },
    );
  }

  Widget _buildPurchasesList(bool isDark) {
    if (_recentPurchases.isEmpty) return const Center(child: Text("Aucun achat récent"));
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: _recentPurchases.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, i) {
        final item = _recentPurchases[i];
        return GestureDetector(
           onTap: () => _openTransactionDetail(item, false), 
           child: Container(
             margin: const EdgeInsets.only(bottom: 10),
             decoration: BoxDecoration(
               color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
               borderRadius: BorderRadius.circular(15),
               border: Border.all(color: Colors.orange.withOpacity(0.2))
             ),
             child: ListTile(
               leading: const Icon(FontAwesomeIcons.truck, color: Colors.orange),
               title: Text(_safeString(item['supplier_name'], 'Fournisseur'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
               subtitle: Text(_safeDate(item['date'])),
               trailing: Text("${fmtMoney(item['total_amount'])} DA", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
             ),
           ),
        );
      },
    );
  }

  Widget _buildSleepingStockList(bool isDark) {
    if (_sleepingStock.isEmpty) return const Center(child: Text("Aucun stock dormant détecté"));
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: _sleepingStock.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, i) {
        final p = _sleepingStock[i];
        final name = _safeString(p['name'], 'Article Inconnu');
        final stock = p['stock'] ?? p['base_stock'] ?? 0;
        final value = fmtMoney(p['sleeping_value'] ?? p['value'] ?? 0);
        
        return ListTile(
          leading: const Icon(FontAwesomeIcons.bed, color: Colors.purple),
          title: Text(name, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
          subtitle: const Text("Invendu > 30j"),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
               Text("Perte: $value", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
               Text("Qte: $stock", style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }
}

// ==============================================================================
// MODALE DÉTAIL TRANSACTION
// ==============================================================================
class TransactionDetailSheet extends StatelessWidget {
  final ApiService api;
  final Map<String, dynamic> data;
  final bool isSale;

  const TransactionDetailSheet({super.key, required this.api, required this.data, required this.isSale});

  Future<void> _handlePrint(BuildContext context, String format) async {
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E2C) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text("Impression $format...", style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );

    try {
      await api.printLocalTransaction(data['id'], isSale, format);
    } catch (e) {
      debugPrint("Erreur impression: $e");
    } finally {
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isSale ? "Ticket #${data['invoice_number'] ?? data['id']}" : "Achat #${data['number'] ?? data['id']}";
    final name = isSale ? (data['client_name'] ?? 'Client') : (data['supplier_name'] ?? 'Fournisseur');
    final color = isSale ? AppColors.primary : Colors.orange;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75, 
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                  Text(name, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(),
          const Align(alignment: Alignment.centerLeft, child: Text("Détail du panier", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))),
          
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: isSale ? api.getSaleItems(data['id']) : api.getPurchaseItems(data['id']),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Détails non disponibles."));
                
                final items = snapshot.data!;
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (c,i) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final item = items[i];
                    final qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0;
                    final price = double.tryParse(isSale ? item['price'].toString() : item['cost'].toString()) ?? 0;
                    final total = qty * price;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 35, height: 35,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text("${qty % 1 == 0 ? qty.toInt() : qty}x", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['name'] ?? 'Article', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black)),
                                Text("${price.toStringAsFixed(0)} DA", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                          Text("${total.toStringAsFixed(0)} DA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          const Divider(),
          
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("TOTAL", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text("${data['total_amount']} DA", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
          
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _buildPrintBtn(context, "Ticket", FontAwesomeIcons.receipt, Colors.teal, 
                  () => _handlePrint(context, 'Ticket')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPrintBtn(context, "A5", FontAwesomeIcons.noteSticky, Colors.blueAccent, 
                  () => _handlePrint(context, 'A5')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPrintBtn(context, "A4", FontAwesomeIcons.filePdf, Colors.redAccent, 
                  () => _handlePrint(context, 'A4')),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPrintBtn(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withOpacity(0.3))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}

class DetailedListModal extends StatefulWidget {
  final ApiService api;
  final String type; 
  final String title;
  final Color themeColor;

  const DetailedListModal({super.key, required this.api, required this.type, required this.title, required this.themeColor});

  @override
  State<DetailedListModal> createState() => _DetailedListModalState();
}

class _DetailedListModalState extends State<DetailedListModal> {
  List<dynamic> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchList();
  }

  Future<void> _fetchList() async {
    try {
      List<dynamic> res = [];
      Map<String, dynamic> dashboardData = {};
      
      if (widget.type == 'CAPITAL' || widget.type == 'PROFIT' || widget.type == 'SALES_TODAY') {
          dashboardData = await widget.api.fetchDashboardData();
      }

      if (widget.type == 'SALES_TODAY' || widget.type == 'PROFIT') {
        final tables = dashboardData['tables'];
        if(tables is Map && tables['finance'] is List) res = tables['finance'];
      }
      else if (widget.type == 'CAPITAL') {
        final kpi = dashboardData['dashboard'] ?? {};
        res = [
          {'name': 'Valeur Stock', 'balance': kpi['stock_value'], 'icon': FontAwesomeIcons.boxesStacked},
          {'name': 'Trésorerie', 'balance': kpi['treasury'], 'icon': FontAwesomeIcons.wallet},
          {'name': 'Créances Clients', 'balance': kpi['client_credit'], 'icon': FontAwesomeIcons.handHoldingDollar},
        ];
      }
      else if (widget.type == 'CLIENT_DEBT') {
        final clients = await widget.api.getTiersList('clients', '');
        res = clients.where((c) => (double.tryParse(c['balance']?.toString() ?? '0') ?? 0) > 0).toList();
        res.sort((a, b) => (double.tryParse(b['balance'].toString())??0).compareTo(double.tryParse(a['balance'].toString())??0));
      }
      else if (widget.type == 'SUPPLIER_DEBT') {
        final suppliers = await widget.api.getTiersList('suppliers', '');
        res = suppliers.map((s) {
           s['balance'] = double.tryParse(s['balance']?.toString() ?? '0') ?? 0;
           return s;
        }).toList();
        res = res.where((s) => s['balance'] != 0).toList();
        res.sort((a, b) => b['balance'].compareTo(a['balance']));
      }
      else if (widget.type == 'STOCK_VALUE') {
        final products = await widget.api.getMobileProductCatalog();
        res = products['products'] ?? [];
        res.sort((a, b) {
          final valA = (double.tryParse(a['price'].toString())??0) * (double.tryParse(a['stock'].toString())??0);
          final valB = (double.tryParse(b['price'].toString())??0) * (double.tryParse(b['stock'].toString())??0);
          return valB.compareTo(valA); 
        });
        res = res.take(100).toList();
      }

      if (mounted) setState(() { _list = res; _loading = false; });
    } catch(e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C).withOpacity(0.95) : Colors.white.withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: widget.themeColor.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(Icons.list_alt, color: widget.themeColor, size: 24),
                ),
                const SizedBox(width: 15),
                Text(widget.title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: widget.themeColor, borderRadius: BorderRadius.circular(10)),
                  child: Text("${_list.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            ),
            
            const SizedBox(height: 20),
            const Divider(),
            
            Expanded(
              child: _loading 
                ? Center(child: CircularProgressIndicator(color: widget.themeColor))
                : _list.isEmpty 
                  ? const Center(child: Text("Aucune donnée"))
                  : ListView.separated(
                      itemCount: _list.length,
                      separatorBuilder: (c, i) => Divider(color: Colors.grey.withOpacity(0.1), height: 1),
                      itemBuilder: (ctx, i) {
                        final item = _list[i];
                        
                        if (widget.type == 'CAPITAL') {
                           return ListTile(
                            leading: Icon(item['icon'] as IconData, color: widget.themeColor),
                            title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                            trailing: Text("${item['balance']} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                          );
                        }
                        else if (widget.type == 'CLIENT_DEBT' || widget.type == 'SUPPLIER_DEBT') {
                          return ListTile(
                            leading: CircleAvatar(backgroundColor: widget.themeColor.withOpacity(0.1), child: Text(item['name'][0], style: TextStyle(color: widget.themeColor, fontWeight: FontWeight.bold))),
                            title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                            subtitle: Text(item['phone'] ?? ''),
                            trailing: Text("${item['balance']} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 16)),
                          );
                        } else if (widget.type == 'PROFIT' || widget.type == 'SALES_TODAY') {
                           return ListTile(
                            title: Text(item['day'].toString(), style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                            trailing: Text("${item[widget.type == 'PROFIT' ? 'total_profit' : 'total_revenue']} DA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                          );
                        } else {
                          final stock = double.tryParse(item['stock'].toString()) ?? 0;
                          final price = double.tryParse(item['price'].toString()) ?? 0;
                          final totalVal = stock * price;
                          return ListTile(
                            title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                            subtitle: Text("Qté: ${stock.toInt()} x ${price.toStringAsFixed(0)} DA"),
                            trailing: Text("${totalVal.toStringAsFixed(0)} DA", style: TextStyle(fontWeight: FontWeight.bold, color: widget.themeColor)),
                          );
                        }
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}

class DaySalesModal extends StatefulWidget {
  final ApiService api;
  final String date;
  const DaySalesModal({super.key, required this.api, required this.date});

  @override
  State<DaySalesModal> createState() => _DaySalesModalState();
}

class _DaySalesModalState extends State<DaySalesModal> {
  List<dynamic> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final data = await widget.api.getSalesByDay(widget.date);
    if(mounted) setState(() { _sales = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C).withOpacity(0.98) : Colors.white.withOpacity(0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            Text("Ventes du ${widget.date}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 15),
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty 
                  ? const Center(child: Text("Aucune vente ce jour-là."))
                  : ListView.builder(
                      itemCount: _sales.length,
                      itemBuilder: (ctx, i) {
                        final s = _sales[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () => showModalBottomSheet(
                              context: context,
                              useRootNavigator: true, 
                              backgroundColor: Colors.transparent,
                              isScrollControlled: true,
                              builder: (ctx) => TransactionDetailSheet(api: widget.api, data: s, isSale: true),
                            ),
                            child: GlassCard(
                              isDark: isDark,
                              padding: const EdgeInsets.all(15),
                              borderRadius: 15,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
                                        child: const Icon(FontAwesomeIcons.receipt, size: 16, color: Colors.blue),
                                      ),
                                      const SizedBox(width: 15),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("Ticket #${s['invoice_number']}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                                          Text("${s['time']} • ${s['client_name']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Text("${s['total_amount']} DA", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}