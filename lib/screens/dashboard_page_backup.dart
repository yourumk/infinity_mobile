import 'dart:ui';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../services/update_service.dart';
import '../services/gps_service.dart';
import 'package:flutter/services.dart';

import 'offline_queue_page.dart';
import '../widgets/print_config_modal.dart';
import '../widgets/spotlight_search.dart';
import '../pages/infinity_studio_page.dart';
import 'fleet_tour_page.dart';
import 'tour_stops_page.dart';
import 'transfers_page.dart';
import 'fleet_map_page.dart';
import 'cash_manager_page.dart';
import '../core/permission_guard.dart';
// ðŸ› ï¸ FIX UI/STATE : Import de la Pilule de sÃ©lection sÃ©curisÃ©e
import '../widgets/warehouse_selector_pill.dart';

// Ã¢â€â‚¬Ã¢â€â‚¬ Top-level helpers (accessible by all classes in this file) Ã¢â€â‚¬Ã¢â€â‚¬
double _safeDoubleGlobal(dynamic val) => double.tryParse(val?.toString() ?? '0') ?? 0.0;
String fmtMoney(dynamic amount) => NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2).format(_safeDoubleGlobal(amount));

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
  
  int _currentTabIndex = 0;
  final PageController _pageController = PageController();
  final PageController _chartController = PageController();
  int _currentChartIndex = 0;

  Map<String, dynamic> _rawKpi = {};
  List<dynamic> _financeData = [];
  List<dynamic> _topProducts = [];
  List<dynamic> _recentPurchases = []; 
  List<dynamic> _sleepingStock = [];   
  int _sellerSalesLimit = 10; // ðŸ› ï¸ Filtre quantitÃ© ventes (10/50/100/0=tout)

  bool _hasDashboardPerm = true;
  String _userRole = '';
  List<String> _userPermissions = [];
  bool get _canViewProfit => !['chauffeur', 'vendeur'].contains(_userRole);
  
  // ðŸ› ï¸ FIX RBAC & DASHBOARD : VÃ©rification de permission (identique Ã  home_screen.dart)
  bool _hasPerm(String perm) => _userRole == 'admin' || _userPermissions.contains(perm);

  @override
  void initState() {
    super.initState();
    ApiService().startAutoSync();
    _loadPermissions();
    
    
    // ðŸ” Lancement du GPS Tracking
    GpsTrackingService().startTracking();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<DataProvider>(context, listen: false);
      provider.startAutoRefresh();
      provider.addListener(_onProviderUpdate);
      Future.delayed(const Duration(seconds: 3), () {
        UpdateService().checkForUpdate(context);
      });
    });
  }

  @override
  void dispose() {
    try { Provider.of<DataProvider>(context, listen: false).removeListener(_onProviderUpdate); } catch(e) {}
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

  Future<void> _loadPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';
    final permsString = prefs.getString('user_permissions') ?? '[]';
    List<String> perms = [];
    try {
      final List<dynamic> decoded = json.decode(permsString);
      perms = decoded.map((e) => e.toString()).toList();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _userRole = role;
        _userPermissions = perms;
        // ðŸŸ¢ FIX DASHBOARD : Chauffeur/Vendeur ont TOUJOURS accÃ¨s Ã  leur dashboard personnel
        if (role == 'chauffeur' || role == 'vendeur') {
          _hasDashboardPerm = true;
        } else if (role == 'admin') {
          _hasDashboardPerm = true;
        } else {
          _hasDashboardPerm = perms.contains('mobile_dashboard');
        }
      });
    }
    // Charger les donnÃ©es aprÃ¨s avoir le rÃ´le correct
    _loadTabsData();
  }

  List<dynamic> _safeList(dynamic data) => (data is List) ? data : [];
  String _safeString(dynamic val, [String d = '']) => val?.toString() ?? d;
  String _safeDate(dynamic dateStr) {
    if (dateStr == null) return '---';
    String s = dateStr.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }
  double _safeDouble(dynamic val) => _safeDoubleGlobal(val);
  int _safeInt(dynamic val) => int.tryParse(val?.toString() ?? '0') ?? 0;

  Future<void> _loadTabsData() async {
    try {
      final data = await _api.fetchDashboardData();
      if (mounted) {
        setState(() {
          _rawKpi = data;
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
    } catch (e) {}
  }

  void _navTo(int index) => widget.onNavigateToTab(index);
  void _onTabChanged(int index) {
    setState(() => _currentTabIndex = index);
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _openDetailList(String type, String title, Color themeColor) {
    showModalBottomSheet(context: context, useRootNavigator: true, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => DetailedListModal(api: _api, type: type, title: title, themeColor: themeColor));
  }

  // ðŸŸ¢ SPOTLIGHT SEARCH : Ouvre la recherche globale
  void _openSpotlight() {
    showSearch(
      context: context,
      delegate: SpotlightSearch(onNavigateToTab: _navTo),
    );
  }

  void _openDaySalesSheet(String date) {
    showModalBottomSheet(context: context, useRootNavigator: true, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => DaySalesModal(api: _api, date: date));
  }

  void _openTransactionDetail(Map<String, dynamic> data, bool isSale) {
    showModalBottomSheet(context: context, useRootNavigator: true, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (ctx) => TransactionDetailSheet(api: _api, data: data, isSale: isSale));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dataProvider = Provider.of<DataProvider>(context);
    final dynamic kpi = _rawKpi.isNotEmpty ? _rawKpi : dataProvider.dashboardData; 
    final isLoading = dataProvider.isLoading;
    
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

    final List<SalesTrendModel> cleanData = dataProvider.salesTrend.isNotEmpty ? dataProvider.salesTrend : [SalesTrendModel(label: 'N/A', value: 0)];

    // Dynamic greeting
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Bonjour' : hour < 18 ? 'Bon aprÃ¨s-midi' : 'Bonsoir';
    final dateStr = DateFormat('EEEE d MMMM', 'fr').format(DateTime.now());

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F4F8),
      body: isLoading && salesCount == 0
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
              onRefresh: () async {
                await dataProvider.loadData(forceRefresh: true);
                await _loadTabsData();
              },
              child: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• ERROR BANNER â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
                      if (_api.lastError != null) ...[
                        GestureDetector(
                          onTap: () async {
                            _api.clearError();
                            await dataProvider.loadData(forceRefresh: true);
                            await _loadTabsData();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.red.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.wifi_off_rounded, color: Colors.red, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _api.lastError!,
                                    style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                                    maxLines: 2, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                                  child: const Icon(Icons.refresh_rounded, color: Colors.red, size: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• HEADER â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  greeting,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.grey.shade500),
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    "Tableau de Bord",
                                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF1A1A2E), letterSpacing: -0.5),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        dateStr,
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? Colors.white38 : Colors.grey.shade400),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      " â€¢ ",
                                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade400),
                                    ),
                                    const Flexible(child: WarehouseSelectorPill()),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildHeaderBtn(FontAwesomeIcons.magnifyingGlass, isDark, _openSpotlight),
                              const SizedBox(width: 10),
                              StreamBuilder<void>(
                                stream: ApiService().onDataUpdated,
                                builder: (context, snapshot) {
                                  final queueCount = ApiService().currentQueue.length;
                                  final hasPending = queueCount > 0;
                                  return GestureDetector(
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => OfflineQueuePage())),
                                    child: Container(
                                      padding: const EdgeInsets.all(11),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.8),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: hasPending ? Colors.orange.withOpacity(0.6) : (isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200),
                                          width: hasPending ? 1.5 : 0.5,
                                        ),
                                      ),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Icon(hasPending ? FontAwesomeIcons.cloudArrowUp : FontAwesomeIcons.cloud, color: hasPending ? Colors.orange : (isDark ? Colors.white70 : Colors.grey.shade600), size: 17),
                                          if (hasPending)
                                            Positioned(right: -6, top: -6, child: Container(padding: const EdgeInsets.all(3.5), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: Text('$queueCount', style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold))))
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              ),
                              const SizedBox(width: 10),
                              _buildHeaderBtn(Icons.settings_rounded, isDark, () => widget.onOpenSettings()),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• TOOL GRID (RÃ‰PARÃ‰) â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final int crossAxisCount = constraints.maxWidth > 600 ? 6 : 4;
                          const double spacing = 12.0;
                          final double itemWidth = ((constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount) - 0.1;

                          Widget wrapper(Widget child) => SizedBox(width: itemWidth, child: child);

                          return Wrap(
                            spacing: spacing,
                            runSpacing: 20.0, // Espace vertical parfait entre les lignes
                            alignment: WrapAlignment.start,
                            children: [
                              wrapper(RequirePermission(permission: 'mobile_sales', child: _buildToolItem(FontAwesomeIcons.vault, "Multi-Caisse", const Color(0xFF0EA5E9), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashManagerPage()))), fallback: _buildLockedToolItem(FontAwesomeIcons.vault, "Multi-Caisse", isDark))),
                              wrapper(RequirePermission(permission: 'mobile_history_sales', child: _buildToolItem(FontAwesomeIcons.receipt, "Hist. Ventes", const Color(0xFF8B5CF6), isDark, () => _navTo(5)), fallback: _buildLockedToolItem(FontAwesomeIcons.receipt, "Hist. Ventes", isDark))),
                              wrapper(RequirePermission(permission: 'mobile_clients', child: _buildToolItem(FontAwesomeIcons.users, "Clients", const Color(0xFF3B82F6), isDark, () => _navTo(6)), fallback: _buildLockedToolItem(FontAwesomeIcons.users, "Clients", isDark))),
                              wrapper(RequirePermission(permission: 'mobile_history_purchases', child: _buildToolItem(FontAwesomeIcons.cartFlatbed, "Hist. Achats", const Color(0xFFF97316), isDark, () => _navTo(11)), fallback: _buildLockedToolItem(FontAwesomeIcons.cartFlatbed, "Hist. Achats", isDark))),
                              
                              wrapper(RequirePermission(permission: 'mobile_suppliers', child: _buildToolItem(FontAwesomeIcons.truckField, "Fournisseurs", const Color(0xFF06B6D4), isDark, () => _navTo(12)), fallback: _buildLockedToolItem(FontAwesomeIcons.truckField, "Fournisseurs", isDark))),
                              wrapper(RequirePermission(permission: 'mobile_catalog', child: _buildToolItem(FontAwesomeIcons.boxOpen, "Pertes", const Color(0xFFEF4444), isDark, () => _navTo(9)), fallback: _buildLockedToolItem(FontAwesomeIcons.boxOpen, "Pertes", isDark))),
                              wrapper(RequirePermission(permission: 'mobile_reports', child: _buildToolItem(FontAwesomeIcons.bellConcierge, "Alertes", const Color(0xFFF59E0B), isDark, () => _navTo(8), badge: totalAlerts > 0 ? totalAlerts : null), fallback: _buildLockedToolItem(FontAwesomeIcons.bellConcierge, "Alertes", isDark))),
                              wrapper(RequirePermission(permission: 'mobile_catalog', child: _buildToolItem(FontAwesomeIcons.print, "Print Studio", const Color(0xFF14B8A6), isDark, () => _navTo(10)), fallback: _buildLockedToolItem(FontAwesomeIcons.print, "Print Studio", isDark))),
                              
                              wrapper(RequirePermission(permission: 'mobile_tour', child: _buildToolItem(FontAwesomeIcons.truck, "Ma TournÃ©e", const Color(0xFFF97316), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FleetTourPage()))), fallback: _buildLockedToolItem(FontAwesomeIcons.truck, "Ma TournÃ©e", isDark))),
                              wrapper(RequirePermission(permission: 'mobile_transfers', child: _buildToolItem(FontAwesomeIcons.boxesStacked, "Transferts", const Color(0xFF64748B), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransfersPage()))), fallback: _buildLockedToolItem(FontAwesomeIcons.boxesStacked, "Transferts", isDark))),
                              if (_hasPerm('mobile_map_admin'))
                                wrapper(_buildToolItem(FontAwesomeIcons.mapLocationDot, "Live Tracking", const Color(0xFF22C55E), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FleetMapPage())))),
                              wrapper(RequirePermission(permission: 'mobile_tour', child: _buildToolItem(FontAwesomeIcons.route, "Programme", const Color(0xFF6F2DBD), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => TourStopsPage(onBack: () => Navigator.pop(context))))), fallback: _buildLockedToolItem(FontAwesomeIcons.route, "Programme", isDark))),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12), // ðŸŸ¢ Espacement grandement rÃ©duit

                      _buildCompactSalesToday(isDark, salesToday, salesCount, profitToday, totalAlerts, treasury),
                      const SizedBox(height: 24),

                      // â”€â”€â”€ Vue Admin/Manager : Dashboard complet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                      if (_hasDashboardPerm && _canViewProfit) ...[ 
                        _buildFusedChartAndFinance(
                          isDark, cleanData, salesToday, profitToday,
                          treasury, capital, stockValue, clientCredit, supplierDebt,
                        ),
                        const SizedBox(height: 8),
                        // Chart dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            width: _currentChartIndex == index ? 20 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: _currentChartIndex == index ? AppColors.accent : (isDark ? Colors.white.withOpacity(0.15) : Colors.grey.withOpacity(0.25)),
                            ),
                          )),
                        ),
                        const SizedBox(height: 24),
                        _buildProfitBanner(isDark, profitToday),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _buildDetailStatCard("Capital Total", fmtMoney(capital), const Color(0xFFF59E0B), FontAwesomeIcons.coins, isDark, () {})),
                            const SizedBox(width: 14),
                            Expanded(child: _buildDetailStatCard("Valeur Stock", fmtMoney(stockValue), const Color(0xFFF97316), FontAwesomeIcons.boxesStacked, isDark, () => _openDetailList('STOCK_VALUE', 'Top Valeur Stock', Colors.orange))),
                          ],
                        ),
                        const SizedBox(height: 28),
                        // Tabs complets (Journal / Top / Achats / Dormant)
                        Column(
                          children: [
                            Container(
                              height: 52, padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200, width: 0.5),
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
                            const SizedBox(height: 20),
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

                      // â”€â”€â”€ Vue Chauffeur / Vendeur : Dashboard Personnel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                      ] else if (_hasDashboardPerm && !_canViewProfit) ...[
                        // ðŸŸ¢ FIX DASHBOARD : 2 KPIs hÃ©ros mis en avant (Mon CA + Mes Ventes)
                        Row(
                          children: [
                            Expanded(
                              child: GlassCard(
                                isDark: isDark,
                                padding: const EdgeInsets.all(18),
                                borderRadius: 20,
                                borderColor: AppColors.success.withOpacity(0.3),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                                      child: const Icon(FontAwesomeIcons.chartLine, color: AppColors.success, size: 16),
                                    ),
                                    const SizedBox(height: 12),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(fmtMoney(salesToday), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.success)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text("Mon CA du Jour", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? Colors.white54 : Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: GlassCard(
                                isDark: isDark,
                                padding: const EdgeInsets.all(18),
                                borderRadius: 20,
                                borderColor: AppColors.primary.withOpacity(0.3),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                                      child: const Icon(FontAwesomeIcons.receipt, color: AppColors.primary, size: 16),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '$salesCount',
                                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary),
                                    ),
                                    const SizedBox(height: 4),
                                    Text("Mes Ventes", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? Colors.white54 : Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ðŸ› ï¸ NOUVEAU : Journal des ventes rÃ©centes pour vendeur/chauffeur
                        GlassCard(
                          isDark: isDark,
                          padding: const EdgeInsets.all(0),
                          borderRadius: 20,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                                      child: const Icon(FontAwesomeIcons.clockRotateLeft, color: AppColors.primary, size: 16),
                                    ),
                                    const SizedBox(width: 10),
                                    Text("DerniÃ¨res Ventes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: Text("${_financeData.length}", style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ),
                              // Chips de filtrage quantitÃ©
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [10, 50, 100, 0].map((n) {
                                      final label = n == 0 ? 'Tout' : '$n';
                                      final isSelected = _sellerSalesLimit == n;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(label),
                                          selected: isSelected,
                                          onSelected: (_) => setState(() => _sellerSalesLimit = n),
                                          selectedColor: AppColors.primary,
                                          backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
                                          labelStyle: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black87), fontWeight: FontWeight.bold, fontSize: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          showCheckmark: false,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 350,
                                child: _buildSellerRecentSales(isDark),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                      // â”€â”€â”€ AccÃ¨s refusÃ© â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                      ] else ...[
                        const SizedBox(height: 24),
                        Center(
                          child: Column(
                            children: [
                              Icon(FontAwesomeIcons.lock, size: 40, color: isDark ? Colors.white24 : Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text("AccÃ¨s au Dashboard non autorisÃ©", style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildCompactSalesToday(bool isDark, double salesToday, int salesCount, double profitToday, int totalAlerts, double treasury) {
    String status; Color statusColor;
    if (totalAlerts > 5) { status = "âš ï¸ $totalAlerts alertes"; statusColor = Colors.red; }
    else if (salesToday > treasury * 0.1 && salesToday > 0) { status = "ðŸ“ˆ Croissance"; statusColor = Colors.green; }
    else if (salesToday == 0) { status = "ðŸŒ™ Calme"; statusColor = Colors.grey; }
    else { status = "âœ… Normal"; statusColor = AppColors.accent; }

    return GlassCard(
      isDark: isDark,
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.2), AppColors.accent.withOpacity(0.1)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(FontAwesomeIcons.chartLine, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Text("VENTES AUJOURD'HUI", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isDark ? Colors.white54 : Colors.grey.shade500, letterSpacing: 1.5), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(fmtMoney(salesToday), style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF1A1A2E), letterSpacing: -1)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _buildPillChip("$salesCount ventes", AppColors.primary, isDark),
              if (_canViewProfit)
                _buildPillChip("Marge ${fmtMoney(profitToday)}", AppColors.success, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPillChip(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.15), width: 0.5),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _buildFusedChartAndFinance(
    bool isDark, List<SalesTrendModel> cleanData,
    double salesToday, double profitToday, double treasury,
    double capital, double stockValue, double clientCredit, double supplierDebt,
  ) {
    return GlassCard(
      isDark: isDark,
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.08) : AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(FontAwesomeIcons.chartLine, color: isDark ? Colors.white70 : AppColors.primary, size: 14),
              ),
              const SizedBox(width: 10),
              Text("Ã‰volution & Finance", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1A1A2E))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(fmtMoney(salesToday), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildFinanceKpiRow(isDark, treasury, clientCredit, supplierDebt),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: ((treasury + clientCredit) > supplierDebt ? Colors.green : Colors.orange).withOpacity(isDark ? 0.1 : 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ((treasury + clientCredit) > supplierDebt ? Colors.green : Colors.orange).withOpacity(0.1), width: 0.5),
            ),
            child: Row(
              children: [
                Icon(
                  (treasury + clientCredit) > supplierDebt ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                  color: (treasury + clientCredit) > supplierDebt ? Colors.green : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (treasury + clientCredit) > supplierDebt
                        ? "SantÃ© financiÃ¨re saine"
                        : "Attention â€” dettes Ã©levÃ©es",
                    style: TextStyle(
                      color: (treasury + clientCredit) > supplierDebt ? Colors.green : Colors.orange,
                      fontSize: 11, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: PageView(
              controller: _chartController,
              onPageChanged: (idx) => setState(() => _currentChartIndex = idx),
              children: [
                _buildMainChartSection(isDark, cleanData, fmtMoney(salesToday), "Ã‰volution Ventes"),
                _buildBarChartSection(isDark, "Performance (7 Jours)"),
                if (_canViewProfit)
                  _buildPieChartSection(isDark, salesToday, profitToday, "RÃ©partition Marge"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceKpiRow(bool isDark, double treasury, double clientCredit, double supplierDebt) {
    return Row(
      children: [
        Expanded(child: _buildMiniKpi("TrÃ©sorerie", fmtMoney(treasury), const Color(0xFF3B82F6), FontAwesomeIcons.wallet, isDark, onTap: () => _navTo(3))),
        const SizedBox(width: 10),
        Expanded(child: _buildMiniKpi("CrÃ©dit Clients", fmtMoney(clientCredit), const Color(0xFF22C55E), FontAwesomeIcons.handHoldingDollar, isDark, onTap: () => _openDetailList('CLIENT_DEBT', 'CrÃ©dits Clients', Colors.green))),
        const SizedBox(width: 10),
        Expanded(child: _buildMiniKpi("Dettes Fourn.", fmtMoney(supplierDebt), const Color(0xFFEF4444), FontAwesomeIcons.fileInvoiceDollar, isDark, onTap: () => _openDetailList('SUPPLIER_DEBT', 'Dettes Fournisseurs', Colors.redAccent))),
      ],
    );
  }

  Widget _buildMiniKpi(String label, String value, Color color, IconData icon, bool isDark, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.10 : 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.12), width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(height: 4),
            FittedBox(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color))),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isDark ? Colors.white54 : Colors.grey.shade500), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildProfitBanner(bool isDark, double profitToday) {
    return GestureDetector(
      onTap: () => _openDetailList('PROFIT', 'Journal des Profits', AppColors.success),
      child: GlassCard(
        isDark: isDark,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        borderRadius: 20,
        borderColor: AppColors.success.withOpacity(0.2),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFFFFD700).withOpacity(0.3), AppColors.success.withOpacity(0.2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(FontAwesomeIcons.trophy, color: AppColors.success, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("BÃ©nÃ©fice du jour", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                  const SizedBox(height: 2),
                  Text("Voir le dÃ©tail des marges â†’", style: TextStyle(fontSize: 10, color: isDark ? Colors.white30 : Colors.grey.shade400)),
                ],
              ),
            ),
            Text(fmtMoney(profitToday), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.success)),
          ],
        ),
      ),
    );
  }

 Widget _buildToolItem(IconData icon, String label, Color color, bool isDark, VoidCallback onTap, {int? badge}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min, // ðŸŸ¢ CRITIQUE : EmpÃªche le dÃ©bordement vertical !
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(isDark ? 0.20 : 0.12), color.withOpacity(isDark ? 0.08 : 0.04)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.15), width: 0.5),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (badge != null)
                Positioned(
                  right: -5, top: -5,
                  child: Container(
                    padding: const EdgeInsets.all(4.5),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F4F8), width: 2),
                    ),
                    child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.grey.shade600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildLockedToolItem(IconData icon, String label, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min, // ðŸŸ¢ CRITIQUE Ã‰GALEMENT !
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12, width: 0.5),
              ),
              child: Icon(icon, color: isDark ? Colors.white30 : Colors.black26, size: 20),
            ),
            Positioned(
              right: -5, top: -5,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  shape: BoxShape.circle,
                  border: Border.all(color: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F4F8), width: 2),
                ),
                child: const Icon(Icons.lock, color: Colors.white, size: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white30 : Colors.black26),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMainChartSection(bool isDark, List<SalesTrendModel> cleanData, String totalSales, String title) {
    List<FlSpot> spots = cleanData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(totalSales, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            ]),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(14)), child: const Icon(FontAwesomeIcons.chartLine, color: Colors.white, size: 16)),
          ]),
          const SizedBox(height: 12),
          Expanded(child: LineChart(LineChartData(gridData: FlGridData(show: false), titlesData: FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.white, barWidth: 2.5, dotData: FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.white.withOpacity(0.15)))]))),
        ],
      ),
    );
  }

  Widget _buildBarChartSection(bool isDark, String title) {
    List<dynamic> chartData = _financeData.take(7).toList().reversed.toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E), fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 12),
          Expanded(child: BarChart(BarChartData(barTouchData: BarTouchData(enabled: false), titlesData: FlTitlesData(show: false), borderData: FlBorderData(show: false), gridData: FlGridData(show: false), barGroups: chartData.asMap().entries.map((e) {
            double sales = double.tryParse(e.value['total_revenue'].toString()) ?? 0;
            double profit = double.tryParse(e.value['total_profit'].toString()) ?? 0;
            return BarChartGroupData(x: e.key, barRods: [BarChartRodData(toY: sales, color: const Color(0xFF6366F1), width: 8, borderRadius: BorderRadius.circular(4)), BarChartRodData(toY: profit, color: const Color(0xFF34D399), width: 8, borderRadius: BorderRadius.circular(4))]);
          }).toList()))),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [_legendItem(const Color(0xFF6366F1), "CA"), const SizedBox(width: 20), _legendItem(const Color(0xFF34D399), "Profit")]),
        ],
      ),
    );
  }

  Widget _buildPieChartSection(bool isDark, double sales, double profit, String title) {
    double validSales = (sales.isNaN || sales < 0) ? 0 : sales;
    double validProfit = (profit.isNaN || profit < 0) ? 0 : profit;
    double cost = validSales - validProfit;
    if (cost <= 0) cost = 0.1;
    if (validProfit <= 0) validProfit = 0.1;
    bool isEmpty = (validSales == 0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E), fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 12),
            _legendItem(const Color(0xFFA78BFA), "Marge Nette"),
            const SizedBox(height: 6),
            _legendItem(const Color(0xFFFBBF24), "CoÃ»t Produit"),
          ])),
          SizedBox(
            width: 100, height: 100,
            child: isEmpty
              ? Center(child: Text("0%", style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)))
              : PieChart(PieChartData(sectionsSpace: 2, centerSpaceRadius: 25, sections: [
                  PieChartSectionData(value: validProfit, color: const Color(0xFFA78BFA), radius: 22, showTitle: false),
                  PieChartSectionData(value: cost, color: const Color(0xFFFBBF24), radius: 18, showTitle: false),
                ])),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 8), Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600))]);
  }

  Widget _buildSegment(String label, int index, bool isDark) {
    final isActive = _currentTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isActive ? AppColors.primaryGradient : null,
            color: isActive ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            boxShadow: isActive ? [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))] : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: isActive ? Colors.white : Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBtn(IconData icon, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.8),
          shape: BoxShape.circle,
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200, width: 0.5),
        ),
        child: Icon(icon, color: isDark ? Colors.white70 : Colors.grey.shade700, size: 18),
      ),
    );
  }

  Widget _buildDetailStatCard(String title, String value, Color color, IconData icon, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        isDark: isDark,
        borderRadius: 22,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color.withOpacity(0.2), color.withOpacity(0.08)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 14),
            FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: isDark ? Colors.white : const Color(0xFF1A1A2E)))),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceList(bool isDark) {
    if (_financeData.isEmpty) return Center(child: Text("Aucune donnÃ©e", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.all(4), itemCount: _financeData.length, physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, i) {
        final item = _financeData[i];
        return GestureDetector(
          onTap: () => _openDaySalesSheet(_safeString(item['day'])),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200, width: 0.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Text(_safeDate(item['day']), style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E), fontWeight: FontWeight.w700)),
                ]),
                Text(fmtMoney(item['total_revenue']), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success, fontSize: 14)),
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _buildSellerRecentSales(bool isDark) {
    if (_financeData.isEmpty) {
      return Center(child: Text("Aucune vente rÃ©cente", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)));
    }
    // ðŸ› ï¸ Filtrage par quantitÃ© (10/50/100/Tout)
    final displayData = _sellerSalesLimit > 0 ? _financeData.take(_sellerSalesLimit).toList() : _financeData;
    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: displayData.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, i) {
        final s = displayData[i];
        return GestureDetector(
          onTap: () => _openTransactionDetail(s, true),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(FontAwesomeIcons.receipt, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Ticket #${_safeString(s['invoice_number'])}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text("${_safeString(s['time'])} â€¢ ${_safeString(s['client_name'])}", style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Text(fmtMoney(s['total_amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopProductsList(bool isDark) {
    if (_topProducts.isEmpty) return Center(child: Text("Pas assez de donnÃ©es", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)));
    return ListView.separated(
      padding: const EdgeInsets.all(4), itemCount: _topProducts.length, separatorBuilder: (ctx, i) => const SizedBox(height: 4), physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, i) {
        final p = _topProducts[i];
        return ListTile(
          onTap: () => _showProductStatModal(p), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: Container(
            width: 36, height: 36, alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accent.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(10)),
            child: Text("${i+1}", style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent, fontSize: 14)),
          ),
          title: Text(_safeString(p['name'], 'Produit'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E), fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Row(children: [Text("${_safeDouble(p['qty']).toStringAsFixed(0)} Ventes", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)), const SizedBox(width: 10), Text("CA: ${fmtMoney(p['total_revenue'])}", style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 12, fontWeight: FontWeight.w600))]),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text("Gain", style: TextStyle(fontSize: 10, color: Colors.grey.shade400)), Text(fmtMoney(p['total_profit']), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w900, fontSize: 14))]),
        );
      },
    );
  }

  Widget _buildPurchasesList(bool isDark) {
    if (_recentPurchases.isEmpty) return Center(child: Text("Aucun achat rÃ©cent", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.all(4), itemCount: _recentPurchases.length, physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, i) {
        final item = _recentPurchases[i];
        return GestureDetector(
          onTap: () => _openTransactionDetail(item, false),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withOpacity(0.15), width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(FontAwesomeIcons.truck, color: Colors.orange, size: 16),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_safeString(item['supplier_name'], 'Fournisseur'), style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_safeDate(item['date']), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ])),
                Text(fmtMoney(item['total_amount']), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSleepingStockList(bool isDark) {
    if (_sleepingStock.isEmpty) return Center(child: Text("Aucun stock dormant dÃ©tectÃ©", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.all(4), itemCount: _sleepingStock.length, physics: const BouncingScrollPhysics(),
      itemBuilder: (ctx, i) {
        final p = _sleepingStock[i];
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.purple.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(10)),
            child: const Icon(FontAwesomeIcons.bed, color: Colors.purple, size: 16),
          ),
          title: Text(_safeString(p['name'], 'Article Inconnu'), style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E), fontWeight: FontWeight.w700)),
          subtitle: Text("Invendu > 30j", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text("Perte: ${fmtMoney(p['sleeping_value'] ?? p['value'] ?? 0)}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 12)), Text("Qte: ${p['stock'] ?? p['base_stock'] ?? 0}", style: TextStyle(color: Colors.grey.shade500, fontSize: 11))]),
        );
      },
    );
  }
  
  void _showProductStatModal(Map<String, dynamic> product) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(25), decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E2C) : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10))), const SizedBox(height: 20),
            Text(_safeString(product['name']), textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)), const SizedBox(height: 5),
            Text("DÃ©tails 30 derniers jours", style: TextStyle(color: Colors.grey[500], fontSize: 12)), const SizedBox(height: 30),
            Row(children: [Expanded(child: _buildModalStatCard("Ventes (QtÃ©)", "${_safeDouble(product['qty']).toStringAsFixed(0)}", Colors.blue, FontAwesomeIcons.cartShopping, isDark)), const SizedBox(width: 15), Expanded(child: _buildModalStatCard("Stock Actuel", "${_safeDouble(product['current_stock']).toStringAsFixed(0)}", Colors.orange, FontAwesomeIcons.boxesStacked, isDark))]), const SizedBox(height: 15),
            Row(children: [Expanded(child: _buildModalStatCard("Chiffre d'Affaires", fmtMoney(product['total_revenue']), Colors.purple, FontAwesomeIcons.moneyBillWave, isDark)), const SizedBox(width: 15), Expanded(child: _buildModalStatCard("BÃ©nÃ©fice Net", fmtMoney(product['total_profit']), Colors.green, FontAwesomeIcons.trophy, isDark))]), const SizedBox(height: 30),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: () => Navigator.pop(ctx), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text("Fermer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))
          ],
        ),
      ),
    );
  }

  Widget _buildModalStatCard(String label, String value, Color color, IconData icon, bool isDark) {
    return Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.2))), child: Column(children: [Icon(icon, color: color, size: 24), const SizedBox(height: 10), FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isDark ? Colors.white : Colors.black))), const SizedBox(height: 2), Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.grey[700]))]));
  }
}



class DetailedListModal extends StatefulWidget {
  final ApiService api; final String type; final String title; final Color themeColor;
  const DetailedListModal({super.key, required this.api, required this.type, required this.title, required this.themeColor});
  @override
  State<DetailedListModal> createState() => _DetailedListModalState();
}

class _DetailedListModalState extends State<DetailedListModal> {
  List<dynamic> _list = []; bool _loading = true;
  @override
  void initState() { super.initState(); _fetchList(); }

  Future<void> _fetchList() async {
    try {
      List<dynamic> res = []; Map<String, dynamic> dashboardData = {};
      if (widget.type == 'CAPITAL' || widget.type == 'PROFIT' || widget.type == 'SALES_TODAY') dashboardData = await widget.api.fetchDashboardData();
      if (widget.type == 'SALES_TODAY' || widget.type == 'PROFIT') { final tables = dashboardData['tables']; if(tables is Map && tables['finance'] is List) res = tables['finance']; }
      else if (widget.type == 'CAPITAL') { final kpi = dashboardData['dashboard'] ?? {}; res = [{'name': 'Valeur Stock', 'balance': kpi['stock_value'], 'icon': FontAwesomeIcons.boxesStacked}, {'name': 'TrÃ©sorerie', 'balance': kpi['treasury'], 'icon': FontAwesomeIcons.wallet}, {'name': 'CrÃ©ances Clients', 'balance': kpi['client_credit'], 'icon': FontAwesomeIcons.handHoldingDollar}]; }
      else if (widget.type == 'CLIENT_DEBT') { final clients = await widget.api.getTiersList('clients', ''); res = clients.where((c) => (double.tryParse(c['balance']?.toString() ?? '0') ?? 0) > 0).toList(); res.sort((a, b) => (double.tryParse(b['balance'].toString())??0).compareTo(double.tryParse(a['balance'].toString())??0)); }
      else if (widget.type == 'SUPPLIER_DEBT') { final suppliers = await widget.api.getTiersList('suppliers', ''); res = suppliers.map((s) { s['balance'] = double.tryParse(s['balance']?.toString() ?? '0') ?? 0; return s; }).toList(); res = res.where((s) => s['balance'] != 0).toList(); res.sort((a, b) => b['balance'].compareTo(a['balance'])); }
      else if (widget.type == 'STOCK_VALUE') { final products = await widget.api.getMobileProductCatalog(); res = products['products'] ?? []; res.sort((a, b) { final valA = (double.tryParse(a['price'].toString())??0) * (double.tryParse(a['stock'].toString())??0); final valB = (double.tryParse(b['price'].toString())??0) * (double.tryParse(b['stock'].toString())??0); return valB.compareTo(valA); }); res = res.take(100).toList(); }
      if (mounted) setState(() { _list = res; _loading = false; });
    } catch(e) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E2C).withOpacity(0.95) : Colors.white.withOpacity(0.95), borderRadius: const BorderRadius.vertical(top: Radius.circular(35)), border: Border.all(color: Colors.white.withOpacity(0.1))),
        child: Column(
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10))), const SizedBox(height: 20),
            Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: widget.themeColor.withOpacity(0.15), shape: BoxShape.circle), child: Icon(Icons.list_alt, color: widget.themeColor, size: 24)), const SizedBox(width: 15), Text(widget.title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: widget.themeColor, borderRadius: BorderRadius.circular(10)), child: Text("${_list.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))]),
            const SizedBox(height: 20), const Divider(),
            Expanded(
              child: _loading ? Center(child: CircularProgressIndicator(color: widget.themeColor)) : _list.isEmpty ? const Center(child: Text("Aucune donnÃ©e")) : ListView.separated(
                      itemCount: _list.length, separatorBuilder: (c, i) => Divider(color: Colors.grey.withOpacity(0.1), height: 1),
                      itemBuilder: (ctx, i) {
                        final item = _list[i];
                        if (widget.type == 'CAPITAL') return ListTile(leading: Icon(item['icon'] as IconData, color: widget.themeColor), title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)), trailing: Text(fmtMoney(item['balance']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)));
                        else if (widget.type == 'CLIENT_DEBT' || widget.type == 'SUPPLIER_DEBT') return ListTile(leading: CircleAvatar(backgroundColor: widget.themeColor.withOpacity(0.1), child: Text(item['name'][0], style: TextStyle(color: widget.themeColor, fontWeight: FontWeight.bold))), title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)), subtitle: Text(item['phone'] ?? ''), trailing: Text(fmtMoney(item['balance']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 16)));
                        else if (widget.type == 'PROFIT' || widget.type == 'SALES_TODAY') return ListTile(title: Text(item['day'].toString(), style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)), trailing: Text(fmtMoney(item[widget.type == 'PROFIT' ? 'total_profit' : 'total_revenue']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)));
                        else { final stock = double.tryParse(item['stock'].toString()) ?? 0; final price = double.tryParse(item['price'].toString()) ?? 0; final totalVal = stock * price; return ListTile(title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)), subtitle: Text("QtÃ©: ${stock.toInt()} x ${fmtMoney(price)}"), trailing: Text(fmtMoney(totalVal), style: TextStyle(fontWeight: FontWeight.bold, color: widget.themeColor))); }
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
  final ApiService api; final String date;
  const DaySalesModal({super.key, required this.api, required this.date});
  @override
  State<DaySalesModal> createState() => _DaySalesModalState();
}

class _DaySalesModalState extends State<DaySalesModal> {
  List<dynamic> _sales = []; bool _loading = true;
  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    final data = await widget.api.getSalesByDay(widget.date);
    if(mounted) setState(() { _sales = data; _loading = false; });
  }
Future<void> _quickPrint(BuildContext context, String format, String docType, dynamic id) async {
    // 1. Ouvrir le Modal d'options
    final config = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PrintConfigModal(initialFormat: format),
    );

    if (config != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Demande au PC...", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );

      // 2. Appel de la nouvelle fonction magique
      final success = await widget.api.printViaPC(
        config['format'], 
        docType, 
        id,
        options: config
      );

      if (context.mounted) Navigator.pop(context); // Ferme le loader

      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ã‰chec : Le PC de la boutique est-il allumÃ© et connectÃ© ?")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E2C).withOpacity(0.98) : Colors.white.withOpacity(0.98), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10))), const SizedBox(height: 20),
            Text("Ventes du ${widget.date}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)), const SizedBox(height: 15),
            Expanded(
              child: _loading ? const Center(child: CircularProgressIndicator()) : _sales.isEmpty ? const Center(child: Text("Aucune vente ce jour-lÃ .")) : ListView.builder(
                      itemCount: _sales.length,
                      itemBuilder: (ctx, i) {
                        final s = _sales[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () => showModalBottomSheet(context: context, useRootNavigator: true, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (ctx) => TransactionDetailSheet(api: widget.api, data: s, isSale: true)),
                            child: GlassCard(
                              isDark: isDark, padding: const EdgeInsets.all(15), borderRadius: 15,
                     child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
                                    child: const Icon(FontAwesomeIcons.receipt, size: 16, color: Colors.blue),
                                  ),
                                  const SizedBox(width: 15),
                                  // Le widget Expanded empÃªche le dÃ©passement d'Ã©cran !
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Ticket #${s['invoice_number']}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        Text("${s['time']} â€¢ ${s['client_name']}", style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  // Colonne de droite (Prix + Petits boutons)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(fmtMoney(s['total_amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
                                      const SizedBox(height: 5),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () => _quickPrint(context, 'A5', 'bl', s['id']),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
                                              child: const Icon(FontAwesomeIcons.truckFast, size: 14, color: Colors.green),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: () => _quickPrint(context, 'A4', 'sale', s['id']),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
                                              child: const Icon(FontAwesomeIcons.filePdf, size: 14, color: Colors.redAccent),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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

// ==============================================================================
// MODALE DÃ‰TAIL TRANSACTION
// ==============================================================================
class TransactionDetailSheet extends StatelessWidget {
  final ApiService api;
  final Map<String, dynamic> data;
  final bool isSale;

  const TransactionDetailSheet({super.key, required this.api, required this.data, required this.isSale});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isSale ? "Ticket #${data['invoice_number'] ?? data['id']}" : "Achat #${data['number'] ?? data['id']}";
    final name = isSale ? (data['client_name'] ?? 'Client') : (data['supplier_name'] ?? 'Fournisseur');
    final color = isSale ? AppColors.primary : Colors.orange;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, 
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E2C) : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)), Text(name, style: const TextStyle(color: Colors.grey, fontSize: 13))]),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(),
          const Align(alignment: Alignment.centerLeft, child: Text("DÃ©tail du panier", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))),
          
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: isSale ? api.getSaleItems(data['id']) : api.getPurchaseItems(data['id']),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("DÃ©tails non disponibles."));
                
                final items = snapshot.data!;
                return ListView.separated(
                  itemCount: items.length, separatorBuilder: (c,i) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final item = items[i];
                    final qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0;
                    final price = double.tryParse(isSale ? item['price'].toString() : item['cost'].toString()) ?? 0;
                    final total = qty * price;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Container(width: 35, height: 35, alignment: Alignment.center, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text("${qty % 1 == 0 ? qty.toInt() : qty}x", style: TextStyle(fontWeight: FontWeight.bold, color: color))),
                          const SizedBox(width: 15),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['name'] ?? 'Article', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black)), Text("${price.toStringAsFixed(0)} DA", style: const TextStyle(color: Colors.grey, fontSize: 12))])),
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
                const Text("Montant Total", style: TextStyle(color: Colors.grey)),
                Text(fmtMoney(data['total_amount']), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
          const SizedBox(height: 10),

       if (isSale) ...[
            const Align(alignment: Alignment.centerLeft, child: Text("ðŸ“„ Imprimer Facture :", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildPrintBtn(context, "Ticket", FontAwesomeIcons.receipt, Colors.teal, 'Ticket', 'sale', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A5", FontAwesomeIcons.fileLines, Colors.blueAccent, 'A5', 'sale', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A4", FontAwesomeIcons.filePdf, Colors.redAccent, 'A4', 'sale', data['id'])),
              ],
            ),
            const SizedBox(height: 15),
            const Align(alignment: Alignment.centerLeft, child: Text("ðŸšš Imprimer Bon de Livraison :", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildPrintBtn(context, "Ticket", FontAwesomeIcons.receipt, Colors.teal, 'Ticket', 'bl', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A5", FontAwesomeIcons.fileLines, Colors.blueAccent, 'A5', 'bl', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A4", FontAwesomeIcons.filePdf, Colors.redAccent, 'A4', 'bl', data['id'])),
              ],
            ),
          ] else ...[
            const Align(alignment: Alignment.centerLeft, child: Text("ðŸ›’ Imprimer Bon de Commande :", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildPrintBtn(context, "Ticket", FontAwesomeIcons.receipt, Colors.teal, 'Ticket', 'purchase', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A5", FontAwesomeIcons.fileLines, Colors.blueAccent, 'A5', 'purchase', data['id'])),
                const SizedBox(width: 10),
                Expanded(child: _buildPrintBtn(context, "A4", FontAwesomeIcons.filePdf, Colors.redAccent, 'A4', 'purchase', data['id'])),
              ],
            ),
          ],
        ],
      ),
    );
  }

Widget _buildPrintBtn(BuildContext context, String label, IconData icon, Color color, String format, String docType, dynamic docId) {
    return ElevatedButton(
      onPressed: () async {
        final config = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => PrintConfigModal(initialFormat: format),
        );

        if (config != null && context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Text("Demande au PC...", style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          );

          final success = await api.printViaPC(
            config['format'], 
            docType, 
            docId, 
            options: config
          );

          if (context.mounted) Navigator.pop(context);

          if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ã‰chec : Le PC est-il allumÃ© et connectÃ© ?")));
          }
        }
      },
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
