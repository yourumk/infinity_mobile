import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/kpi_model.dart';
import '../models/sales_trend_model.dart';

class DataProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  
  // Données
  KpiModel _dashboardData = KpiModel();
  List<SalesTrendModel> _salesTrend = [];
  
  // États
  bool _isLoading = false;
  Timer? _refreshTimer;

  // Getters
  KpiModel get dashboardData => _dashboardData;
  List<SalesTrendModel> get salesTrend => _salesTrend;
  bool get isLoading => _isLoading;

 void startAutoRefresh() {
    // 1. On charge immédiatement une première fois
    loadData(); 
    
    // 2. On nettoie tout ancien timer
    _refreshTimer?.cancel();
    
    // 3. MODIFICATION ICI : 2 secondes au lieu de 15
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) { //
      // "silent: true" pour ne pas afficher le rond de chargement
      loadData(silent: true); 
    });
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
    // Si ce n'est pas un chargement silencieux (ex: démarrage ou pull-to-refresh),
    // on affiche l'indicateur de chargement.
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // APPEL API INTELLIGENT
      // Si forceRefresh est true, l'API Service va utiliser le timestamp pour contourner le cache
      final data = await _api.fetchDashboardData(forceRefresh: forceRefresh || !silent);
      
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