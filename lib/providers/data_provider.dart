import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../models/kpi_model.dart';
import '../models/sales_trend_model.dart';

class DataProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  
  // 🚀 Clé de cache dashboard dans SharedPreferences
  static const String _dashboardCacheKey = 'dashboard_data_cache';
  
  // Données
  KpiModel _dashboardData = KpiModel();
  List<SalesTrendModel> _salesTrend = [];
  
  // États
  bool _isLoading = false;
  bool _hasCachedData = false; // 🚀 Indique si on a déjà affiché du cache
  Timer? _refreshTimer;

  // Getters
  KpiModel get dashboardData => _dashboardData;
  List<SalesTrendModel> get salesTrend => _salesTrend;
  bool get isLoading => _isLoading;

 void startAutoRefresh() {
    // 1. 🚀 CACHE-FIRST : Charger instantanément depuis le cache local
    _loadCachedDashboard().then((_) {
      // 2. Puis lancer le fetch réseau en arrière-plan
      loadData(silent: _hasCachedData);
    });
    
    // 3. On nettoie tout ancien timer
    _refreshTimer?.cancel();
    
    // 4. Rafraîchissement toutes les 15 secondes (économie batterie + réseau)
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      // "silent: true" pour ne pas afficher le rond de chargement
      loadData(silent: true); 
    });
  }

  // 🚀 CACHE-FIRST : Charge les données depuis SharedPreferences (instantané)
  Future<void> _loadCachedDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_dashboardCacheKey);
      if (cached != null && cached.isNotEmpty) {
        final data = json.decode(cached) as Map<String, dynamic>;
        _dashboardData = KpiModel.fromJson(data);
        if (data['sales_trend'] != null && data['sales_trend'] is List) {
          _salesTrend = (data['sales_trend'] as List)
              .map((e) => SalesTrendModel.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        _hasCachedData = true;
        notifyListeners(); // 🚀 Affichage instantané avec les données cachées
        debugPrint("⚡ [DataProvider] Dashboard affiché depuis le cache local");
      }
    } catch (e) {
      debugPrint("⚠️ [DataProvider] Erreur lecture cache dashboard: $e");
    }
  }

  // 🚀 Sauvegarde les données API dans le cache local
  Future<void> _saveDashboardCache(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dashboardCacheKey, json.encode(data));
    } catch (e) {
      debugPrint("⚠️ [DataProvider] Erreur écriture cache dashboard: $e");
    }
  }

  // Arrête le rafraîchissement (quand on quitte l'écran)
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }

  // ==============================================================================
  // 2. CHARGEMENT DES DONNÉES (CŒUR DU SYSTÈME)
  // ==============================================================================

  Future<void> loadData({bool forceRefresh = false, bool silent = false}) async {
    // Si ce n'est pas un chargement silencieux ET qu'on n'a pas de cache,
    // on affiche l'indicateur de chargement.
    if (!silent && !_hasCachedData) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // APPEL API INTELLIGENT
      // Si forceRefresh est true, l'API Service va utiliser le timestamp pour contourner le cache
      final data = await _api.fetchDashboardData(forceRefresh: forceRefresh || !silent);
      
      if (data.isNotEmpty) {
        // Mise à jour du Modèle KPI (Chiffres clés)
        _dashboardData = KpiModel.fromJson(data);
        
        // Mise à jour du Graphique
        if (data['sales_trend'] != null && data['sales_trend'] is List) {
          _salesTrend = (data['sales_trend'] as List)
              .map((e) => SalesTrendModel.fromJson(e))
              .toList();
        } else {
          _salesTrend = [];
        }

        // 🚀 Sauvegarder dans le cache pour le prochain lancement
        _saveDashboardCache(data);
      }

    } catch (e) {
      debugPrint("❌ Erreur Provider loadData: $e");
    } finally {
      // On enlève le chargement seulement si on l'avait mis
      if (!silent) {
        _isLoading = false;
      }
      // On notifie l'interface : "Hey, les chiffres ont changé, redessine-toi !"
      notifyListeners();
    }
  }
}