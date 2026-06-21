import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../models/sales_trend_model.dart';
import '../widgets/glass_card.dart';
import '../widgets/spotlight_search.dart';
import '../widgets/warehouse_selector_pill.dart';
import 'offline_queue_page.dart';
import '../core/permission_guard.dart';
import '../core/feature_guard.dart';

import 'fleet_tour_page.dart';
import 'tour_stops_page.dart';
import 'transfers_page.dart';
import 'fleet_map_page.dart';
import 'cash_manager_page.dart';

double safeDoubleGlobal(dynamic val) => double.tryParse(val?.toString() ?? '0') ?? 0.0;
String fmtMoney(dynamic amount) => NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 2).format(safeDoubleGlobal(amount));

class DashboardHeader extends StatelessWidget {
  final bool isDark;
  final Function(int) onNavigateToTab;
  final VoidCallback onOpenSettings;

  const DashboardHeader({
    Key? key,
    required this.isDark,
    required this.onNavigateToTab,
    required this.onOpenSettings,
  }) : super(key: key);

  void _openSpotlight(BuildContext context) {
    showSearch(
      context: context,
      delegate: SpotlightSearch(onNavigateToTab: onNavigateToTab),
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
        child: Icon(icon, color: isDark ? Colors.white70 : Colors.grey.shade600, size: 17),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Bonjour' : hour < 18 ? 'Bon après-midi' : 'Bonsoir';
    final dateStr = DateFormat('EEEE d MMMM', 'fr').format(DateTime.now());

    return Row(
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
                    " • ",
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
            _buildHeaderBtn(FontAwesomeIcons.magnifyingGlass, isDark, () => _openSpotlight(context)),
            const SizedBox(width: 10),
            StreamBuilder<void>(
              stream: ApiService().onDataUpdated,
              builder: (context, snapshot) {
                final queueCount = ApiService().currentQueue.length;
                final hasPending = queueCount > 0;
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OfflineQueuePage())),
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
                          Positioned(
                            right: -6, top: -6, 
                            child: Container(
                              padding: const EdgeInsets.all(3.5), 
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), 
                              child: Text('$queueCount', style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold))
                            )
                          )
                      ],
                    ),
                  ),
                );
              }
            ),
            const SizedBox(width: 10),
            _buildHeaderBtn(Icons.settings_rounded, isDark, onOpenSettings),
          ],
        ),
      ],
    );
  }
}

class DashboardToolGrid extends StatelessWidget {
  final bool isDark;
  final Function(int) onNavigateToTab;
  final int totalAlerts;
  final bool Function(String) hasPerm;

  const DashboardToolGrid({
    Key? key,
    required this.isDark,
    required this.onNavigateToTab,
    required this.totalAlerts,
    required this.hasPerm,
  }) : super(key: key);

  Widget _buildToolItem(IconData icon, String label, Color color, bool isDark, VoidCallback onTap, {int? badge}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              if (badge != null && badge > 0)
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
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade300, width: 0.5),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: isDark ? Colors.white24 : Colors.grey.shade400, size: 20),
              Positioned(bottom: 2, right: 2, child: Icon(FontAwesomeIcons.lock, size: 10, color: isDark ? Colors.white38 : Colors.grey.shade500)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white38 : Colors.grey.shade400)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 🟢 FIX LAYOUT : Guard contre les contraintes invalides (width <= 0)
        if (constraints.maxWidth <= 0) return const SizedBox.shrink();

        final int crossAxisCount = constraints.maxWidth > 600 ? 6 : 4;
        const double spacing = 12.0;
        // 🟢 FIX LAYOUT : Clamp à 0 minimum pour éviter BoxConstraints négatifs
        final double itemWidth = ((constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount).clamp(0.0, constraints.maxWidth);

        Widget wrapper(Widget child) => SizedBox(width: itemWidth, child: child);

        return Wrap(
          spacing: spacing,
          runSpacing: 20.0,
          alignment: WrapAlignment.start,
          children: [
            wrapper(FeatureGuard(feature: 'feature_cash_manager_unlocked', child: RequirePermission(permission: 'mobile_sales', child: _buildToolItem(FontAwesomeIcons.vault, "Multi-Caisse", const Color(0xFF0EA5E9), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashManagerPage()))), fallback: _buildLockedToolItem(FontAwesomeIcons.vault, "Multi-Caisse", isDark)))),
            wrapper(RequirePermission(permission: 'mobile_history_sales', child: _buildToolItem(FontAwesomeIcons.receipt, "Hist. Ventes", const Color(0xFF8B5CF6), isDark, () => onNavigateToTab(5)), fallback: _buildLockedToolItem(FontAwesomeIcons.receipt, "Hist. Ventes", isDark))),
            wrapper(RequirePermission(permission: 'mobile_clients', child: _buildToolItem(FontAwesomeIcons.users, "Clients", const Color(0xFF3B82F6), isDark, () => onNavigateToTab(6)), fallback: _buildLockedToolItem(FontAwesomeIcons.users, "Clients", isDark))),
            wrapper(RequirePermission(permission: 'mobile_history_purchases', child: _buildToolItem(FontAwesomeIcons.cartFlatbed, "Hist. Achats", const Color(0xFFF97316), isDark, () => onNavigateToTab(11)), fallback: _buildLockedToolItem(FontAwesomeIcons.cartFlatbed, "Hist. Achats", isDark))),
            
            wrapper(RequirePermission(permission: 'mobile_suppliers', child: _buildToolItem(FontAwesomeIcons.truckField, "Fournisseurs", const Color(0xFF06B6D4), isDark, () => onNavigateToTab(12)), fallback: _buildLockedToolItem(FontAwesomeIcons.truckField, "Fournisseurs", isDark))),
            wrapper(RequirePermission(permission: 'mobile_catalog', child: _buildToolItem(FontAwesomeIcons.boxOpen, "Pertes", const Color(0xFFEF4444), isDark, () => onNavigateToTab(9)), fallback: _buildLockedToolItem(FontAwesomeIcons.boxOpen, "Pertes", isDark))),
            wrapper(RequirePermission(permission: 'mobile_reports', child: _buildToolItem(FontAwesomeIcons.bellConcierge, "Alertes", const Color(0xFFF59E0B), isDark, () => onNavigateToTab(8), badge: totalAlerts), fallback: _buildLockedToolItem(FontAwesomeIcons.bellConcierge, "Alertes", isDark))),
            wrapper(RequirePermission(permission: 'mobile_catalog', child: _buildToolItem(FontAwesomeIcons.print, "Print Studio", const Color(0xFF14B8A6), isDark, () => onNavigateToTab(10)), fallback: _buildLockedToolItem(FontAwesomeIcons.print, "Print Studio", isDark))),
            
            wrapper(FeatureGuard(feature: 'feature_fleet_management', child: RequirePermission(permission: 'mobile_tour', child: _buildToolItem(FontAwesomeIcons.truck, "Ma Tournée", const Color(0xFFF97316), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FleetTourPage()))), fallback: _buildLockedToolItem(FontAwesomeIcons.truck, "Ma Tournée", isDark)))),
            wrapper(FeatureGuard(feature: 'feature_fleet_management', child: RequirePermission(permission: 'mobile_transfers', child: _buildToolItem(FontAwesomeIcons.boxesStacked, "Transferts", const Color(0xFF64748B), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransfersPage()))), fallback: _buildLockedToolItem(FontAwesomeIcons.boxesStacked, "Transferts", isDark)))),
            if (hasPerm('mobile_map_admin'))
              wrapper(FeatureGuard(feature: 'feature_gps_tracking', child: _buildToolItem(FontAwesomeIcons.mapLocationDot, "Live Tracking", const Color(0xFF22C55E), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FleetMapPage()))))),
            wrapper(FeatureGuard(feature: 'feature_fleet_management', child: RequirePermission(permission: 'mobile_tour', child: _buildToolItem(FontAwesomeIcons.route, "Programme", const Color(0xFF6F2DBD), isDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => TourStopsPage(onBack: () => Navigator.pop(context))))), fallback: _buildLockedToolItem(FontAwesomeIcons.route, "Programme", isDark)))),
          ],
        );
      },
    );
  }
}

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final bool isDark;

  const ShimmerBox({Key? key, required this.width, required this.height, this.borderRadius = 8, required this.isDark}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black12,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
