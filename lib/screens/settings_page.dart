import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import 'activation_page.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/update_service.dart'; // ✅ IMPORT IMPORTANT

class SettingsPage extends StatelessWidget {
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<String> onLanguageChanged;
  final ThemeMode currentThemeMode;
  final String currentLanguage;
  
  final VoidCallback? toggleTheme; 
  final VoidCallback? onBack;

  const SettingsPage({
    super.key,
    required this.onThemeModeChanged,
    required this.onLanguageChanged,
    required this.currentThemeMode,
    required this.currentLanguage,
    this.toggleTheme,
    this.onBack,
  });

  // --- FONCTION DE DÉCONNEXION ---
  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Déconnexion"),
        content: const Text("Voulez-vous vraiment vous déconnecter ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Déconnexion", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('license_key');
    await prefs.remove('is_activated');

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => ActivationPage(
          toggleTheme: toggleTheme ?? () {}, 
          onThemeModeChanged: onThemeModeChanged,
          onLanguageChanged: onLanguageChanged,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text("Paramètres", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black),
          onPressed: onBack ?? () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // SECTION APPARENCE
            _buildSection(context, "Apparence", [
              ListTile(
                leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: Colors.blue),
                title: const Text("Mode Sombre"),
                trailing: Switch(
                  value: isDark,
                  activeColor: AppColors.primary,
                  onChanged: (val) {
                    if (toggleTheme != null) toggleTheme!();
                  },
                ),
              ),
            ], isDark),
            
            const SizedBox(height: 20),
            
            // SECTION SYSTÈME (NOUVEAU)
            _buildSection(context, "Système", [
               // ✅ BOUTON DE MISE À JOUR MANUELLE
               ListTile(
                leading: const Icon(Icons.system_update, color: Colors.teal),
                title: const Text("Mise à jour"),
                subtitle: const Text("Vérifier la version"),
                trailing: const Icon(Icons.refresh, color: Colors.grey),
                onTap: () {
                   // Appel manuel du service de mise à jour
                   UpdateService().checkForUpdate(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.print, color: Colors.purple),
                title: const Text("Imprimante"),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () { 
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Configuration Imprimante à venir...")));
                },
              ),
              ListTile(
                leading: const Icon(Icons.language, color: Colors.green),
                title: const Text("Langue"),
                subtitle: Text(currentLanguage == 'fr' ? 'Français' : 'English'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () { /* Config Langue */ },
              ),
            ], isDark),
            
            const SizedBox(height: 20),

            // SECTION COMPTE
            _buildSection(context, "Compte", [
              ListTile(
                leading: const Icon(Icons.person, color: Colors.orange),
                title: const Text("Profil Utilisateur"),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text("Déconnexion", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                onTap: () => _logout(context),
              ),
            ], isDark),
            
            const SizedBox(height: 40),
            // Tu peux laisser ça, ou le rendre dynamique avec PackageInfo plus tard
            const Text("Infinity POS Mobile", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text("v1.0.2", style: TextStyle(color: Colors.grey, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 8),
          child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C23) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
          ),
          child: Column(
            children: children.asMap().entries.map((entry) {
              final idx = entry.key;
              final child = entry.value;
              return Column(
                children: [
                  child,
                  if (idx < children.length - 1) 
                    Divider(height: 1, indent: 50, color: Colors.grey.withOpacity(0.1)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}