// lib/screens/splash_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'activation_page.dart';
import 'home_screen.dart';
import '../core/constants.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final ValueChanged<ThemeMode> onThemeModeChanged; 
  final ValueChanged<String> onLanguageChanged;    

  const SplashScreen({
    super.key,
    required this.toggleTheme,
    required this.onThemeModeChanged,
    required this.onLanguageChanged,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Petit délai pour l'effet visuel
    await Future.delayed(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    final isActivated = prefs.getBool('is_activated') ?? false;

    if (!mounted) return;

    if (isActivated) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(
          toggleTheme: widget.toggleTheme,
          onThemeModeChanged: widget.onThemeModeChanged,
          onLanguageChanged: widget.onLanguageChanged,
        )),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ActivationPage(
          toggleTheme: widget.toggleTheme,
          onThemeModeChanged: widget.onThemeModeChanged,
          onLanguageChanged: widget.onLanguageChanged,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.all_inclusive, size: 80, color: Colors.white)
              ),
              const SizedBox(height: 20),
              const Text(
                "INFINITY MOBILE",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}