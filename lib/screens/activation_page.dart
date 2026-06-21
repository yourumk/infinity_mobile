import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import '../services/update_service.dart';

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

class _ActivationPageState extends State<ActivationPage> with TickerProviderStateMixin {
  final _keyController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();

  bool _obscurePass = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _licenseIsLocked = false;

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic);

    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _fadeController.forward();
    _loadSavedCredentials();

  Future.delayed(const Duration(seconds: 2), () {
      // 🟢 CORRECTION : On s'assure que le contexte est valide avant de lancer la vérification
      if (mounted && context.mounted) {
        UpdateService().checkForUpdate(context);
      }
    });
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('license_key') ?? '';
    final savedUser = prefs.getString('api_user') ?? '';

    if (mounted && savedKey.isNotEmpty) {
      setState(() {
        _keyController.text = savedKey;
        _licenseIsLocked = true;
        if (savedUser.isNotEmpty) _userController.text = savedUser;
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _keyController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }
Future<void> _activate() async {
    FocusScope.of(context).unfocus();
    setState(() { _isLoading = true; _errorMessage = null; });

    final licenseKey = _keyController.text.trim();
    final username = _userController.text.trim();
    final apiPass = _passController.text.trim();

    if (licenseKey.isEmpty) { setState(() { _isLoading = false; _errorMessage = "Entrez votre Code Magasin."; }); return; }
    if (username.isEmpty) { setState(() { _isLoading = false; _errorMessage = "Entrez votre nom d'utilisateur."; }); return; }
    if (apiPass.isEmpty) { setState(() { _isLoading = false; _errorMessage = "Le mot de passe est requis."; }); return; }

    // 🟢 CORRECTION CRITIQUE : Capturer le contexte AVANT les `await`
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Sauvegarde IMMÉDIATE de la licence AVANT le réseau
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('license_key', licenseKey);
    
    if (!mounted) return; // Sécurité

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: const Row(children: [Icon(Icons.save, color: Colors.white, size: 18), SizedBox(width: 10), Text("Licence sauvegardée localement.")]),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final result = await ApiService().verifyCredentials(licenseKey, username, apiPass);
      if (!mounted) return; // Sécurité après le réseau

      if (result['success'] == true) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: const Row(children: [Icon(Icons.check_circle, color: Colors.white, size: 18), SizedBox(width: 10), Text("Bienvenue sur Infinity !")]),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        // On utilise la variable "navigator" capturée au début
        navigator.pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(
          toggleTheme: widget.toggleTheme,
          onThemeModeChanged: widget.onThemeModeChanged,
          onLanguageChanged: widget.onLanguageChanged,
        )));
      } else {
        // En cas d'erreur d'identifiants, on nettoie la clé pour éviter le verrouillage parasite
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('license_key');
        setState(() { _isLoading = false; _errorMessage = result['message'] ?? "Identifiants incorrects."; });
      }
    } catch (e) {
      if (!mounted) return;
      // En cas de crash réseau, on nettoie également la clé pour pouvoir la modifier librement
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('license_key');
      setState(() { _isLoading = false; _errorMessage = "Serveur injoignable. Vérifiez votre connexion."; });
    }
  }

  // 🔐 Purge complète des données de session avant changement de licence
  Future<void> _unlockLicense() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Nettoyage absolu de toutes les variables de session de l'ancienne boutique
    await prefs.remove('license_key');
    await prefs.remove('api_user');
    await prefs.remove('api_pass');
    await prefs.remove('user_role');
    await prefs.remove('user_permissions');
    await prefs.remove('mobile_user_id');
    await prefs.remove('employee_id');
    await prefs.remove('pos_user_id');
    await prefs.remove('assigned_register_id');
    await prefs.remove('assigned_warehouse_id');
    await prefs.remove('selected_warehouse_id');
    await prefs.remove('global_warehouse');
    await prefs.remove('global_register');
    
    // 2. Purge complète du cache SQLite local (produits, tiers, paniers)
    // ✅ FIX : try/catch pour éviter que le crash SQLite bloque le déverrouillage
    try {
      await ApiService().clearCache();
    } catch (e) {
      debugPrint("⚠️ Erreur clearCache (ignorée) : $e");
    }

    setState(() {
      _keyController.clear();
      _userController.clear();
      _passController.clear();
      _licenseIsLocked = false;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B0D1A), Color(0xFF151A30), Color(0xFF1A1040)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            // ═══ Animated Ambient Orbs ═══
            AnimatedBuilder(animation: _pulseAnim, builder: (_, __) => Stack(children: [
              Positioned(top: size.height * 0.08, left: -60, child: _glowOrb(const Color(0xFF6366F1), 220 * _pulseAnim.value)),
              Positioned(bottom: size.height * 0.12, right: -40, child: _glowOrb(const Color(0xFF10B981), 200 * (2.0 - _pulseAnim.value))),
              Positioned(top: size.height * 0.35, right: size.width * 0.2, child: _glowOrb(const Color(0xFF8B5CF6), 100 * _pulseAnim.value)),
            ])),

            // ═══ Main Content ═══
            SafeArea(
              bottom: false,
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ═══ LOGO ═══
                        _buildLogo(),
                        const SizedBox(height: 10),
                        const Text("INFINITY POS", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4)),
                        const SizedBox(height: 6),
                        Text("Connexion à votre espace", style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.45), letterSpacing: 1)),
                        const SizedBox(height: 36),

                        // ═══ ERROR BOX ═══
                        if (_errorMessage != null) _buildErrorBox(),

                        // ═══ FROSTED GLASS FORM ═══
                        _buildFrostedCard(children: [
                          // License field + Bouton modifier externe
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 8),
                                child: Text("Code Magasin", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5), letterSpacing: 0.8)),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: Colors.white.withOpacity(0.06),
                                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                                      ),
                                      child: TextField(
                                        controller: _keyController,
                                        enabled: !_licenseIsLocked && !_isLoading,
                                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                                        decoration: InputDecoration(
                                          hintText: "INF-VOTRE-CODE",
                                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14),
                                          prefixIcon: Padding(
                                            padding: const EdgeInsets.only(left: 14, right: 10),
                                            child: Icon(Icons.storefront_rounded, color: const Color(0xFF6366F1).withOpacity(0.8), size: 20),
                                          ),
                                          prefixIconConstraints: const BoxConstraints(minWidth: 44),
                                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 0),
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          disabledBorder: InputBorder.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // ✅ FIX : Bouton EXTERNE au TextField — toujours cliquable
                                  if (_licenseIsLocked)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 10),
                                      child: GestureDetector(
                                        onTap: () => _unlockLicense(),
                                        child: Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                                          ),
                                          child: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFF6366F1)),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          // Username field
                          _buildGlassField(
                            controller: _userController,
                            icon: Icons.person_rounded,
                            label: "Nom d'utilisateur",
                            hint: "ex: admin, vendeur1",
                            enabled: !_isLoading,
                          ),

                          const SizedBox(height: 18),

                          // Password field
                          _buildGlassField(
                            controller: _passController,
                            icon: Icons.lock_rounded,
                            label: "Mot de passe",
                            hint: "••••••••",
                            isPassword: true,
                            enabled: !_isLoading,
                          ),

                          const SizedBox(height: 30),

                          // Login Button
                          _buildLoginButton(),
                        ]),

                        const SizedBox(height: 24),

                        // ═══ Footer ═══
                        Text("© ${DateTime.now().year} Infinity POS — Tous droits réservés",
                            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.2))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  LOGO with glow ring
  // ═══════════════════════════════════════════════════════════
  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) => Container(
        width: 100, height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3 * _pulseAnim.value), blurRadius: 40, spreadRadius: 5),
          ],
        ),
        child: child,
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            ),
            child: ClipOval(
              child: Image.asset('assets/logo.png', width: 90, height: 90, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.rocket_launch_rounded, size: 44, color: Color(0xFF6366F1)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  ERROR BOX
  // ═══════════════════════════════════════════════════════════
  Widget _buildErrorBox() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  FROSTED GLASS CARD
  // ═══════════════════════════════════════════════════════════
  Widget _buildFrostedCard({required List<Widget> children}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.04)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              width: 1.2,
              color: Colors.white.withOpacity(0.15),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 40, offset: const Offset(0, 20)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  GLASS TEXT FIELD
  // ═══════════════════════════════════════════════════════════
  Widget _buildGlassField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    String? hint,
    bool isPassword = false,
    bool enabled = true,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5), letterSpacing: 0.8)),
        ),
        // Field
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword && _obscurePass,
            enabled: enabled,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Icon(icon, color: const Color(0xFF6366F1).withOpacity(0.8), size: 20),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 44),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: Colors.white.withOpacity(0.3), size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    )
                  : suffix,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 0),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  LOGIN BUTTON
  // ═══════════════════════════════════════════════════════════
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _isLoading
              ? LinearGradient(colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.04)])
              : const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], begin: Alignment.centerLeft, end: Alignment.centerRight),
          boxShadow: _isLoading ? [] : [
            BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _activate,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.login_rounded, size: 20),
                    SizedBox(width: 10),
                    Text("Se Connecter", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ],
                ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  GLOW ORB
  // ═══════════════════════════════════════════════════════════
  Widget _glowOrb(Color color, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color.withOpacity(0.35), color.withOpacity(0.0)]),
      ),
    );
  }
}