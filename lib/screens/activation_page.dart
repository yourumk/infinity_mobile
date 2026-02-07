import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart'; 
import 'home_screen.dart';

class ActivationPage extends StatefulWidget {
  final VoidCallback toggleTheme;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<String> onLanguageChanged;

  const ActivationPage({
    super.key, 
    required this.toggleTheme,
    required this.onThemeModeChanged,
    required this.onLanguageChanged,
  });

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> with SingleTickerProviderStateMixin {
  final _keyController = TextEditingController();
  final _passController = TextEditingController();
  
  bool _obscurePass = true;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _keyController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    
    final licenseKey = _keyController.text.trim();
    final apiPass = _passController.text.trim();

    // 🔒 SÉCURITÉ 1 : Licence Obligatoire
    if (licenseKey.isEmpty) {
      setState(() { _isLoading = false; _errorMessage = "Veuillez entrer la Clé de Licence."; });
      return;
    }

    // 🔒 SÉCURITÉ 2 : Mot de passe Obligatoire (Bloquant)
    if (apiPass.isEmpty) {
      setState(() { _isLoading = false; _errorMessage = "Le mot de passe est obligatoire 🔒"; });
      return;
    }

    final api = ApiService();
    
    try {
      // Vérification auprès du serveur
      final result = await api.verifyCredentials(licenseKey, apiPass);

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        
        await prefs.setString('license_key', licenseKey);
        await prefs.setString('api_pass', apiPass);
        await prefs.setString('api_user', licenseKey); 
        await prefs.setBool('is_activated', true);

        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🚀 Connexion Infinity réussie !"), backgroundColor: Color(0xFF6C5CE7)),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(
            toggleTheme: widget.toggleTheme,
            onThemeModeChanged: widget.onThemeModeChanged,
            onLanguageChanged: widget.onLanguageChanged,
          )),
        );
      } else {
        setState(() { 
          _isLoading = false; 
          // Message d'erreur plus clair
          _errorMessage = "Accès refusé. Vérifiez vos identifiants."; 
        });
      }
    } catch (e) {
      setState(() { 
          _isLoading = false; 
          _errorMessage = "Serveur injoignable. Vérifiez votre internet."; 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Fond Dégradé Pro (Style Cyberpunk / Tech)
    final bgGradient = const LinearGradient(
      colors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)], 
      begin: Alignment.topLeft, 
      end: Alignment.bottomRight
    );

    return Scaffold(
      body: Stack(
        children: [
          // 1. Fond
          Container(decoration: BoxDecoration(gradient: bgGradient)),
          
          // 2. Effets de lumière (Glow)
          Positioned(
            top: -100, right: -50,
            child: _buildBlurCircle(const Color(0xFF6C5CE7).withOpacity(0.3), 300),
          ),
          Positioned(
            bottom: -50, left: -50,
            child: _buildBlurCircle(const Color(0xFF00CEC9).withOpacity(0.2), 350),
          ),

          // 3. Contenu Central
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- NOUVEAU LOGO PRO ---
                    _buildProLogo(),
                    
                    const SizedBox(height: 50),
                    
                    // --- CARTE DE CONNEXION ---
                    GlassCard(
                      isDark: true, // On force le style sombre pour le contraste
                      borderRadius: 30,
                      padding: const EdgeInsets.all(25),
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                      child: Column(
                        children: [
                          const Text(
                            "Espace Sécurisé",
                            style: TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 25),

                          // Champ Licence
                          _buildModernInput(
                            controller: _keyController,
                            icon: FontAwesomeIcons.key,
                            hint: "Licence",
                          ),
                          
                          const SizedBox(height: 15),

                          // Champ Mot de passe
                          _buildModernInput(
                            controller: _passController,
                            icon: FontAwesomeIcons.lock,
                            hint: "Mot de passe",
                            isPassword: true,
                          ),
                          
                          const SizedBox(height: 25),

                          // Message d'erreur
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 15),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                                    const SizedBox(width: 8),
                                    Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),

                          // Bouton Connexion
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _activate,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6C5CE7),
                                foregroundColor: Colors.white,
                                shadowColor: const Color(0xFF6C5CE7).withOpacity(0.5),
                                elevation: 10,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: _isLoading 
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Text("CONNECTER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                                      SizedBox(width: 10),
                                      Icon(Icons.arrow_forward_rounded, size: 20),
                                    ],
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    Text("Infinity POS Mobile v2.0", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS DU DESIGN ---

  Widget _buildProLogo() {
    return Column(
      children: [
        Container(
          height: 100, width: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [
              BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.6), blurRadius: 30, offset: const Offset(0, 10)),
            ],
            border: Border.all(color: Colors.white, width: 2)
          ),
          child: const Center(
            child: Icon(FontAwesomeIcons.infinity, size: 50, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "INFINITY",
          style: TextStyle(
            fontSize: 32, 
            fontWeight: FontWeight.w900, 
            color: Colors.white, 
            letterSpacing: 3,
            shadows: [Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 5))]
          ),
        ),
        Text(
          "RETAIL INTELLIGENCE",
          style: TextStyle(
            fontSize: 12, 
            fontWeight: FontWeight.bold, 
            color: const Color(0xFF00CEC9), 
            letterSpacing: 5
          ),
        ),
      ],
    );
  }

  Widget _buildModernInput({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && _obscurePass,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
          prefixIcon: Icon(icon, color: Colors.white70, size: 18),
          suffixIcon: isPassword 
            ? IconButton(
                icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 18),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              )
            : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildBlurCircle(Color color, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50), child: Container(color: Colors.transparent)),
    );
  }
}