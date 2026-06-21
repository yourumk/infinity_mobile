import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../core/constants.dart';
import 'dashboard_page.dart';
import 'sales_page.dart';
import 'purchases_page.dart';
import 'charges_page.dart';
import 'articles_page.dart';
import 'history_page.dart';
import 'tiers_page.dart';
import 'settings_page.dart';
import 'alerts_page.dart';
import 'losses_page.dart';
import 'print_studio_page.dart';
import 'package:flutter/services.dart';
import '../core/permission_guard.dart';
// 🛠️ FIX TRACKING PERMANENT : Import du service GPS
import '../services/gps_service.dart';
import '../providers/feature_provider.dart';
import '../services/api_service.dart';
// 🛠️ FIX SELECTOR & STATE : Import de la Pilule de sélection
import '../widgets/warehouse_selector_pill.dart';
import 'package:shared_preferences/shared_preferences.dart';


class HomeScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<String> onLanguageChanged;
  final ThemeMode currentThemeMode;
  final String currentLanguage;

  const HomeScreen({
    super.key,
    required this.toggleTheme,
    required this.onThemeModeChanged,
    required this.onLanguageChanged,
    this.currentThemeMode = ThemeMode.system,
    this.currentLanguage = 'fr',
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  DateTime? _lastBackPressTime;
  bool _isChauffeur = false;
  bool _isLoadingRole = true;

  bool _isAdmin = false;
  List<String> _userPermissions = [];

  // 🛠️ FIX TRACKING PERMANENT : Démarrage du GPS conditionné par le Feature Toggling
  @override
  void initState() {
    super.initState();
    _loadRole();
    FeatureProvider.instance.addListener(_onFeatureUpdated);
    // 🟢 FIX FEATURES : Synchroniser les options POS (modules activés depuis admin.html)
    ApiService().syncCompanySettings();
  }

  @override
  void dispose() {
    FeatureProvider.instance.removeListener(_onFeatureUpdated);
    super.dispose();
  }

  void _onFeatureUpdated() {
    if (!FeatureProvider.instance.hasGpsTracking) {
      GpsTrackingService().stopTracking();
    } else {
      _checkAndStartGps();
    }
  }

  void _checkAndStartGps() {
    bool hasGpsPerm = _isAdmin || _userPermissions.contains('mobile_map_admin') || _userPermissions.contains('mobile_tour');
    if (FeatureProvider.instance.hasGpsTracking && hasGpsPerm) {
      GpsTrackingService().startTracking();
    } else {
      GpsTrackingService().stopTracking();
    }
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';
    final permsString = prefs.getString('user_permissions') ?? '[]';
    List<String> perms = [];
    try {
      final List<dynamic> p = json.decode(permsString);
      perms = p.map((e) => e.toString()).toList();
    } catch(e) {
      debugPrint("Cache corrompu purgé (key: user_permissions)");
      await prefs.remove('user_permissions');
    }

    if (mounted) {
      setState(() {
        _isChauffeur = role == 'chauffeur';
        _isAdmin = role == 'admin';
        _userPermissions = perms;
        // Dashboard toujours visible pour tout le monde, donc on peut laisser par défaut 0
        _isLoadingRole = false;
      });
      _checkAndStartGps();
    }
  }

  bool _hasPerm(String perm) => _isAdmin || _userPermissions.contains(perm);


  void _changeTab(int index) {
    setState(() => _currentIndex = index);
  }

  // Cette fonction permet de revenir à l'onglet "Accueil" (Dashboard)
  void _goHome() {
    setState(() => _currentIndex = 0); // 🛠️ FIX RBAC & DASHBOARD : Toujours revenir au Dashboard
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final List<Widget> pages = [
      // 0. Dashboard
      DashboardPage(
        onNavigateToTab: _changeTab,
        onOpenSettings: () => _changeTab(7), 
      ), 
      
      // 1. Vente
      RequirePermission(
        permission: 'mobile_sales',
        fallback: _buildLockedPage('Vente'),
        child: SalesPage(onBack: _goHome),
      ),
      
      // 2. Achat
      RequirePermission(
        permission: 'mobile_purchases',
        fallback: _buildLockedPage('Achat'),
        child: PurchasesPage(onBack: _goHome),
      ),
      
      // 3. Charges
      RequirePermission(
        permission: 'mobile_charges',
        fallback: _buildLockedPage('Charges'),
        child: const ChargesPage(),
      ),
      
      // 4. Stock
      RequirePermission(
        permission: 'mobile_catalog',
        fallback: _buildLockedPage('Stock'),
        child: const ArticlesPage(),
      ),
      
      // --- PAGES SECONDAIRES ---
      
      // 5. Historique Ventes
      RequirePermission(
        permission: 'mobile_history_sales',
        fallback: _buildLockedPage('Hist. Ventes'),
        child: HistoryPage(onBack: _goHome, initialTab: 0),
      ),
      
      // 6. Clients
      RequirePermission(
        permission: 'mobile_clients',
        fallback: _buildLockedPage('Clients'),
        child: TiersPage(onBack: _goHome, initialTab: 'clients'),
      ),
      
      // 7. Paramètres (Toujours accessible car permet la déconnexion)
      SettingsPage(
        toggleTheme: widget.toggleTheme, 
        onThemeModeChanged: widget.onThemeModeChanged,
        onLanguageChanged: widget.onLanguageChanged,
        currentThemeMode: widget.currentThemeMode,
        currentLanguage: widget.currentLanguage,
        onBack: _goHome,
      ),

      // 8. Alertes
      RequirePermission(
        permission: 'mobile_reports',
        fallback: _buildLockedPage('Alertes'),
        child: AlertsPage(type: 'stock', title: 'Centre d\'Alertes', onBack: _goHome),
      ),

      // 9. Pertes
      RequirePermission(
        permission: 'mobile_catalog',
        fallback: _buildLockedPage('Pertes'),
        child: LossesPage(onBack: _goHome),
      ),

      // 10. Print Studio
      RequirePermission(
        permission: 'mobile_catalog',
        fallback: _buildLockedPage('Print Studio'),
        child: PrintStudioPage(onBack: _goHome),
      ),

      // 11. Historique Achats
      RequirePermission(
        permission: 'mobile_history_purchases',
        fallback: _buildLockedPage('Hist. Achats'),
        child: HistoryPage(onBack: _goHome, initialTab: 1),
      ),

      // 12. Fournisseurs
      RequirePermission(
        permission: 'mobile_suppliers',
        fallback: _buildLockedPage('Fournisseurs'),
        child: TiersPage(onBack: _goHome, initialTab: 'suppliers'),
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentIndex != 0) {
          _goHome();
        } else {
          final now = DateTime.now();
          if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
            _lastBackPressTime = now;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Appuyez encore une fois pour quitter l'application"), duration: Duration(seconds: 2)),
            );
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        // 🛠️ FIX SELECTOR & STATE : Stack pour superposer la Pilule de dépôt
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: pages,
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 15),
            child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                height: 70,
                decoration: BoxDecoration(
                  color: isDark 
                      ? const Color(0xFF1E1E2C).withOpacity(0.90) 
                      : Colors.white.withOpacity(0.90),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(isDark ? 0.1 : 0.5), width: 1),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 🛠️ FIX RBAC: Accueil toujours visible
                    _buildNavItem(0, FontAwesomeIcons.chartPie, "Accueil"),
                    
                    // 🛠️ FIX RBAC: Filtrage dynamique des onglets
                    if (_hasPerm('mobile_sales')) 
                      _buildNavItem(1, FontAwesomeIcons.basketShopping, "Vente"),
                    
                    if (_hasPerm('mobile_purchases')) 
                      _buildNavItem(2, FontAwesomeIcons.truckFast, "Achat"),
                    
                    if (_hasPerm('mobile_charges')) 
                      _buildNavItem(3, FontAwesomeIcons.moneyBillTransfer, "Frais"),
                    
                    if (_hasPerm('mobile_catalog')) 
                      _buildNavItem(4, FontAwesomeIcons.boxOpen, "Stock"),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: isSelected 
            ? BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(15)) 
            : const BoxDecoration(color: Colors.transparent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isSelected ? 20 : 18, color: isSelected ? AppColors.primary : Colors.grey),
            if (isSelected) ...[
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 9)),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildLockedPage(String title) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F0F13) : const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(FontAwesomeIcons.lock, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            const Text("🔒 Accès Refusé", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            const SizedBox(height: 10),
            Text("Vous n'avez pas la permission\npour accéder à cette page.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _goHome,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text("Retour à l'accueil", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}