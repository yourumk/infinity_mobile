import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';

class UpdateService {
  // ✅ C'est ICI que j'ai mis ton lien RAW correct
  final String versionUrl = "https://raw.githubusercontent.com/yourumk/infinity_mobile/main/version.json"; 

  Future<void> checkForUpdate(BuildContext context) async {
    try {
      // 1. Quelle version j'ai installée sur le téléphone ?
      PackageInfo info = await PackageInfo.fromPlatform();
      String currentVersion = info.version;
      debugPrint("📱 Version actuelle : $currentVersion");

      // 2. Quelle version est sur GitHub ?
      // On ajoute un timestamp (?t=...) pour être sûr de ne pas lire une version en cache
      final response = await http.get(Uri.parse('$versionUrl?t=${DateTime.now().millisecondsSinceEpoch}'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String latestVersion = data['version'];
        String apkUrl = data['url'];
        String logs = data['changelog'];

        debugPrint("☁️ Dernière version dispo : $latestVersion");

        // 3. Comparaison : Est-ce que la version GitHub est plus grande que la mienne ?
        if (_isNewer(currentVersion, latestVersion)) {
          // Une mise à jour existe !
          if (context.mounted) {
            _showDialog(context, latestVersion, apkUrl, logs);
          }
        } else {
          debugPrint("✅ L'application est à jour.");
        }
      } else {
        debugPrint("⚠️ Erreur récupération JSON: Code ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Erreur update : $e");
    }
  }

  // Fonction utilitaire pour comparer "1.0.0" et "1.0.1"
  bool _isNewer(String current, String latest) {
    List<int> c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    for (int i = 0; i < 3; i++) {
      int v1 = (i < c.length) ? c[i] : 0;
      int v2 = (i < l.length) ? l[i] : 0;
      if (v2 > v1) return true; 
      if (v2 < v1) return false; 
    }
    return false;
  }

  // Affiche la fenêtre "Mise à jour disponible"
  void _showDialog(BuildContext context, String version, String url, String logs) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Nouvelle version v$version 🚀"),
        content: Text("Nouveautés :\n$logs\n\nVoulez-vous l'installer maintenant ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text("Plus tard")
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startDownload(context, url);
            },
            child: const Text("Mettre à jour"),
          ),
        ],
      ),
    );
  }

  // Lance le téléchargement et l'installation de l'APK
  void _startDownload(BuildContext context, String url) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Téléchargement en cours... L'installation suivra."))
      );
      
      // Lance OTA Update
      OtaUpdate().execute(
        url, 
        destinationFilename: 'infinity_update.apk'
      ).listen(
        (OtaEvent event) {
          debugPrint("⬇️ Status: ${event.status}, Progression: ${event.value}%");
        },
      );
    } catch (e) {
      debugPrint("❌ Erreur téléchargement: $e");
    }
  }
}