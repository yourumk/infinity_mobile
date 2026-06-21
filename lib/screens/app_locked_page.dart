import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'dashboard_page.dart';
import 'activation_page.dart';

class AppLockedPage extends StatefulWidget {
  const AppLockedPage({super.key});

  @override
  State<AppLockedPage> createState() => _AppLockedPageState();
}

class _AppLockedPageState extends State<AppLockedPage> {
  final ApiService _api = ApiService();
  Timer? _timer;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      // Un simple appel pour vérifier l'état du serveur et l'empreinte
      await _api.syncCompanySettings();
      
      // Si ça passe sans erreur, le serveur a déverrouillé le terminal
      if (mounted) {
        _timer?.cancel();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => DashboardPage(
            onNavigateToTab: (_) {},
            onOpenSettings: () {},
          )),
          (route) => false,
        );
      }
    } catch (e) {
      if (e.toString().contains('AUTH_INVALID')) {
        _timer?.cancel();
        _forceLogout();
      }
      // Si AUTH_LOCKED on ignore et on continue à attendre
    } finally {
      _isChecking = false;
    }
  }

  void _forceLogout() {
    if (mounted) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('license_key');
        prefs.remove('user_role');
        prefs.remove('employee_id');
        prefs.remove('assigned_warehouse_id');
        prefs.remove('assigned_register_id');
        prefs.remove('mobile_user_id');
        prefs.remove('user_hash');
      });

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (ctx) => ActivationPage(
          toggleTheme: () {},
          onThemeModeChanged: (_) {},
          onLanguageChanged: (_) {},
        )), 
        (route) => false
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⚠️ Session expirée : Votre compte a été modifié ou désactivé par l\'administrateur.'),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 5),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber.withOpacity(0.3), width: 2),
                ),
                child: const Icon(
                  FontAwesomeIcons.lock,
                  size: 60,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "Terminal Verrouillé",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Votre administrateur a temporairement suspendu l'accès à ce terminal.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.2)),
                ),
                child: const Text(
                  "Vos données non synchronisées sont conservées en sécurité. La reprise du travail sera immédiate après déverrouillage.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.amberAccent,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(color: Colors.amber),
              const SizedBox(height: 16),
              const Text(
                "En attente de déverrouillage...",
                style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
