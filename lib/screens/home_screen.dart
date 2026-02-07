import 'dart:ui';
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

  void _changeTab(int index) {
    setState(() => _currentIndex = index);
  }

  // Cette fonction permet de revenir à l'onglet "Accueil" (Dashboard)
  void _goHome() {
    setState(() => _currentIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final List<Widget> pages = [
      // 0. Dashboard
      DashboardPage(
        onNavigateToTab: _changeTab,
        onOpenSettings: () => _changeTab(7), 
      ), 
      
      // 1. Vente (MODIFIÉ : On passe la fonction de retour)
      SalesPage(onBack: _goHome),
      
      // 2. Achat (MODIFIÉ : On passe la fonction de retour)
      PurchasesPage(onBack: _goHome),
      
      // 3. Charges
      const ChargesPage(),
      
      // 4. Stock
      const ArticlesPage(),
      
      // --- PAGES SECONDAIRES ---
      
      // 5. Historique
      HistoryPage(onBack: _goHome),
      
      // 6. Tiers
      TiersPage(onBack: _goHome),
      
      // 7. Paramètres
      SettingsPage(
        toggleTheme: widget.toggleTheme, 
        onThemeModeChanged: widget.onThemeModeChanged,
        onLanguageChanged: widget.onLanguageChanged,
        currentThemeMode: widget.currentThemeMode,
        currentLanguage: widget.currentLanguage,
        onBack: _goHome,
      ),

      // 8. Alertes
      AlertsPage(type: 'stock', title: 'Centre d\'Alertes', onBack: _goHome),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
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
                  _buildNavItem(0, FontAwesomeIcons.chartPie, "Accueil"),
                  _buildNavItem(1, FontAwesomeIcons.basketShopping, "Vente"),
                  _buildNavItem(2, FontAwesomeIcons.truckFast, "Achat"),
                  _buildNavItem(3, FontAwesomeIcons.moneyBillTransfer, "Frais"),
                  _buildNavItem(4, FontAwesomeIcons.boxOpen, "Stock"),
                ],
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
}