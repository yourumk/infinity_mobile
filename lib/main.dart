import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Ajouté pour le style de la barre d'état
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants.dart';
import 'core/settings_keys.dart';
import 'providers/data_provider.dart';
import 'screens/activation_page.dart';
import 'screens/home_screen.dart';

void main() async {
  // 1. Assurer que le moteur Flutter est prêt
  WidgetsFlutterBinding.ensureInitialized();

  // 2. AMÉLIORATION UI : Rendre la barre de statut transparente (Moderne)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // Barre transparente
    statusBarIconBrightness: Brightness.dark, // Icônes sombres par défaut
    systemNavigationBarColor: Colors.transparent, // Barre de nav transparente (Android 10+)
  ));
  
  // 3. Chargement des préférences
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint("⚠️ Erreur SharedPreferences: $e");
  }

  // 4. Lecture de la configuration sauvegardée
  // Si rien n'est sauvegardé, on met 'system' (Auto) par défaut
  final savedTheme = prefs?.getString(SettingsKeys.appThemeMode) ?? 'system';
  final isActivated = prefs?.getBool('is_activated') ?? false;

  runApp(
    MultiProvider(
      providers: [
        // Le DataProvider est créé ici pour vivre dans toute l'app
        ChangeNotifierProvider(create: (_) => DataProvider()),
      ],
      child: InfinityApp(
        initialThemeMode: savedTheme, // On passe la chaîne 'system', 'light' ou 'dark'
        initialLanguage: 'fr',
        isActivated: isActivated,
      ),
    ),
  );
}

class InfinityApp extends StatefulWidget {
  final String initialThemeMode;
  final String initialLanguage;
  final bool isActivated;

  const InfinityApp({
    super.key,
    required this.initialThemeMode,
    required this.initialLanguage,
    required this.isActivated,
  });

  @override
  State<InfinityApp> createState() => _InfinityAppState();
}

class _InfinityAppState extends State<InfinityApp> {
  // Variable d'état pour le thème
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    // On convertit la chaîne reçue (ex: 'system') en ThemeMode réel
    _themeMode = _themeModeFromString(widget.initialThemeMode);
  }

  // --- LOGIQUE CRITIQUE POUR LE MODE AUTO ---
  ThemeMode _themeModeFromString(String mode) {
    if (mode == 'light') return ThemeMode.light;
    if (mode == 'dark') return ThemeMode.dark;
    return ThemeMode.system; // Par défaut : AUTO
  }

  // Sauvegarde et applique le thème
  void _saveTheme(ThemeMode newMode) async {
    setState(() {
      _themeMode = newMode; // Mise à jour immédiate de l'UI
    });

    // Ajustement dynamique de la barre d'état selon le thème
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: newMode == ThemeMode.dark ? Brightness.light : Brightness.dark,
    ));

    try {
      final prefs = await SharedPreferences.getInstance();
      // On convertit l'enum en texte pour le stockage :
      final modeStr = newMode.toString().split('.').last; 
      await prefs.setString(SettingsKeys.appThemeMode, modeStr);
      debugPrint("💾 Thème sauvegardé : $modeStr");
    } catch (e) {
      debugPrint("❌ Erreur sauvegarde thème: $e");
    }
  }
  
  // Callback legacy pour l'interrupteur simple (GARDÉ COMME DEMANDÉ)
  VoidCallback get toggleThemeLegacy => () {
    if (_themeMode == ThemeMode.dark) {
      _saveTheme(ThemeMode.light);
    } else {
      _saveTheme(ThemeMode.dark);
    }
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinity POS Mobile',
      debugShowCheckedModeBanner: false,
      
      // --- CONFIGURATION DES THÈMES ---
      theme: AppTheme.lightTheme, // Ton thème clair défini dans constants.dart
      darkTheme: AppTheme.darkTheme, // Ton thème sombre défini dans constants.dart
      
      // C'est ICI que la magie opère :
      themeMode: _themeMode, 
      
      locale: const Locale('fr', ''), 
      supportedLocales: const [Locale('fr', '')],
      
      localizationsDelegates: const [ 
        GlobalMaterialLocalizations.delegate, 
        GlobalWidgetsLocalizations.delegate, 
        GlobalCupertinoLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],

      // Navigation principale
      home: widget.isActivated 
        ? HomeScreen(
            toggleTheme: toggleThemeLegacy,
            onThemeModeChanged: _saveTheme, // On passe la nouvelle fonction ici
            onLanguageChanged: (lang) {},
          )
        : ActivationPage(
            toggleTheme: toggleThemeLegacy,
            onThemeModeChanged: _saveTheme,
            onLanguageChanged: (lang) {},
          ),
    );
  }
}