import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppConstants {
  static const String licenseServerUrl = "https://infinity-license-server.onrender.com";
}

class AppColors {
  // --- NOUVELLES COULEURS (Style Maquette) ---
  static const Color primary = Color(0xFF6C5CE7);    // Violet Principal
  static const Color accent = Color(0xFF00CEC9);     // Cyan Néon (Graphes)
  static const Color secondary = Color(0xFFA29BFE);  // Violet Clair
  
  // Backgrounds (Mode Sombre Profond pour le contraste Neon)
  static const Color bgDark = Color(0xFF1E1E2E);     
  static const Color bgLight = Color(0xFFF0F3F8);    
  
  static const Color cardDark = Color(0xFF2D2D44);   // Carte sombre
  
  static const Color textLight = Color(0xFF2D3436);  
  
  static const Color success = Color(0xFF00B894);    // Vert Menthe
  static const Color error = Color(0xFFFF7675);      // Rouge Saumon
  static const Color warning = Color(0xFFFDCB6E);    // Jaune Moutarde

  // Gradient Principal (Boutons, Graphes)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  // On garde ta logique, on change juste la Font pour "Poppins" (plus pro)
  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.bgLight,
    textTheme: GoogleFonts.poppinsTextTheme().apply(bodyColor: AppColors.textLight),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: AppColors.textLight),
      titleTextStyle: TextStyle(color: AppColors.textLight, fontSize: 20, fontWeight: FontWeight.bold),
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.bgDark,
    textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
    ),
  );
}