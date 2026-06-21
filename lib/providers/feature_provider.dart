import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeatureProvider extends ChangeNotifier {
  static final FeatureProvider instance = FeatureProvider._internal();

  FeatureProvider._internal() {
    refreshFeatures();
  }

  bool _hasCashManager = false;
  bool _hasFleetManagement = false;
  bool _hasGpsTracking = false;

  bool get hasCashManager => _hasCashManager;
  bool get hasFleetManagement => _hasFleetManagement;
  bool get hasGpsTracking => _hasGpsTracking;

  Future<void> refreshFeatures() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('pos_options_cache')) {
      try {
        final posOptions = json.decode(prefs.getString('pos_options_cache')!);

        _hasCashManager = _parseBool(posOptions['feature_cash_manager_unlocked']);
        _hasFleetManagement = _parseBool(posOptions['feature_fleet_management']);
        _hasGpsTracking = _parseBool(posOptions['feature_gps_tracking']);
      } catch (e) {
        debugPrint("Cache corrompu purgé (key: pos_options_cache)");
        await prefs.remove('pos_options_cache');
      }
    }
    notifyListeners();
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }
}
