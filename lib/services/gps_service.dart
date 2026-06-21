import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class GpsTrackingService {
  static final GpsTrackingService _instance = GpsTrackingService._internal();
  factory GpsTrackingService() => _instance;
  GpsTrackingService._internal();

  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _heartbeatTimer; // 🛠️ FIX HEARTBEAT : Envoi périodique même sans mouvement
  final ApiService _api = ApiService();
  bool _isTracking = false;
  bool get isTracking => _isTracking;

  /// Démarre le tracking GPS (Même en arrière-plan)
  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("GPS_SERVICE: Les services de localisation sont désactivés.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("GPS_SERVICE: Permission refusée.");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("GPS_SERVICE: Permissions refusées définitivement.");
        return;
      }

      // 🟢 CONFIGURATION ARRIÈRE-PLAN (BACKGROUND)
      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15, // Mise à jour tous les 15 mètres
          forceLocationManager: true,
          // 🚀 INDISPENSABLE POUR LE BACKGROUND SUR ANDROID 10+
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Infinity POS trace votre tournée en arrière-plan.",
            notificationTitle: "Logistique & Suivi GPS en cours",
            enableWakeLock: true,
          ),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 15,
          pauseLocationUpdatesAutomatically: false, // 🚀 iOS Background
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        );
      }

      _isTracking = true;
      debugPrint("GPS_SERVICE: Démarrage du tracking GPS...");

      _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position? position) {
          if (position != null) {
            _onPositionUpdate(position);
          }
        },
        onError: (error) {
          debugPrint("GPS_SERVICE: Erreur du flux - $error");
        },
      );

      // 🛠️ FIX HEARTBEAT : Timer périodique (60s) pour envoyer la position
      // même si le téléphone ne bouge pas (distance filter = 15m)
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          ).timeout(const Duration(seconds: 10));
          // 🛠️ FIX CHANTIER 5 : Protection contre les positions null/invalides
          if (pos.latitude == 0.0 && pos.longitude == 0.0) {
            debugPrint("GPS_SERVICE: ❤️ Heartbeat ignoré (position 0,0)");
            return;
          }
          _onPositionUpdate(pos);
          debugPrint("GPS_SERVICE: ❤️ Heartbeat envoyé (${pos.latitude}, ${pos.longitude})");
        } catch (e) {
          debugPrint("GPS_SERVICE: Heartbeat échoué - $e");
        }
      });
    } catch (e) {
      debugPrint("GPS_SERVICE: Crash évité lors du démarrage - $e");
    }
  }

  void _onPositionUpdate(Position position) {
    // 🛠️ FIX CHANTIER 5 : Guard unifié — s'applique aussi au stream continu
    if (position.latitude == 0.0 && position.longitude == 0.0) {
      debugPrint("GPS_SERVICE: Position (0,0) ignorée dans le stream (pas de fix GPS)");
      return;
    }
    if (position.latitude.isNaN || position.longitude.isNaN) {
      debugPrint("GPS_SERVICE: Position NaN ignorée dans le stream");
      return;
    }
    debugPrint("GPS_SERVICE: Nouvelle position captée - Lat: ${position.latitude}, Lng: ${position.longitude}");
    try {
      _api.sendGpsPositionDirect(position.latitude, position.longitude);
    } catch (e) {
      debugPrint("GPS_SERVICE: Échec de l'envoi de la position - $e");
    }
  }

  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _heartbeatTimer?.cancel(); // 🛠️ FIX HEARTBEAT
    _heartbeatTimer = null;
    _isTracking = false;
    debugPrint("GPS_SERVICE: Tracking GPS arrêté.");
  }

  Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      return null;
    }
  }
}