import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
class UpdateService {
  // ✅ SINGLETON
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  bool _isChecking = false;

  final String versionUrl = "https://raw.githubusercontent.com/yourumk/infinity_mobile/main/version.json"; 

  /// Point d'entrée principal
  Future<void> checkForUpdate(BuildContext context, {bool silent = true}) async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      PackageInfo info = await PackageInfo.fromPlatform();
      String currentVersion = info.version;
      debugPrint("📱 Version actuelle : $currentVersion");

      final response = await http.get(
        Uri.parse('$versionUrl?t=${DateTime.now().millisecondsSinceEpoch}'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String latestVersion = data['version'];
        String apkUrl = data['url'];
        String logs = data['changelog'] ?? '';

        debugPrint("☁️ Dernière version dispo : $latestVersion");

        if (_isNewer(currentVersion, latestVersion)) {
          if (context.mounted) {
            _showUpdateDialog(context, currentVersion, latestVersion, apkUrl, logs);
          }
        } else {
          debugPrint("✅ L'application est à jour.");
          if (!silent && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(children: [
                  Icon(Icons.verified, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text("Vous utilisez la dernière version !", style: TextStyle(fontWeight: FontWeight.w600)),
                ]),
                backgroundColor: const Color(0xFF059669),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Serveur indisponible (code ${response.statusCode})"),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Erreur vérification : $e");
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.wifi_off, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text("Connexion impossible. Réessayez plus tard.")),
            ]),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } finally {
      _isChecking = false;
    }
  }

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

 // ═══════════════════════════════════════════════════════════════
  // 🔐 PERMISSIONS ANDROID (Correction Android 13+)
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _requestPermissions(BuildContext context) async {
    if (Platform.isAndroid) {
      // 🚀 La permission de stockage a été retirée car elle fait planter Android 13+.
      // Elle n'est pas requise pour écrire dans getTemporaryDirectory().

      // Permission d'installation d'APK (La seule vraiment nécessaire)
      final installStatus = await Permission.requestInstallPackages.status;
      if (!installStatus.isGranted) {
        final result = await Permission.requestInstallPackages.request();
        if (!result.isGranted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text("Autorisez l'installation depuis cette source"),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(label: "Paramètres", textColor: Colors.white, onPressed: () => openAppSettings()),
            ));
          }
          return false;
        }
      }
    }
    return true;
  }
  // ═══════════════════════════════════════════════════════════════
  // 🎨 DIALOGUE PREMIUM "NOUVELLE VERSION DISPONIBLE"
  // ═══════════════════════════════════════════════════════════════
  void _showUpdateDialog(BuildContext context, String currentVer, String newVer, String url, String logs) {
    // Séparer les lignes du changelog
    final logLines = logs.split('\n').where((l) => l.trim().isNotEmpty).toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.3), blurRadius: 40, spreadRadius: 2),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── EN-TÊTE GRADIENT ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 36),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Amélioration Disponible",
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "v$currentVer  →  v$newVer",
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── CONTENU (CHANGELOG) ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Quoi de neuf ?",
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...logLines.map((line) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 6, height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF6C63FF),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                line.replaceAll(RegExp(r'^[•\-]\s*'), ''),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: isDark ? Colors.white.withOpacity(0.85) : Colors.grey.shade800,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),

                // ── BOUTONS ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    children: [
                      // Bouton principal
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _startDownloadWithProgress(context, url);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.download_rounded, size: 20),
                              SizedBox(width: 8),
                              Text("Installer Maintenant", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Bouton secondaire
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            foregroundColor: isDark ? Colors.white38 : Colors.grey.shade500,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text("Rappeler plus tard", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ⬇️ DIALOGUE DE TÉLÉCHARGEMENT AVEC PROGRESSION
  // ═══════════════════════════════════════════════════════════════
  void _startDownloadWithProgress(BuildContext context, String url) async {
    final hasPerms = await _requestPermissions(context);
    if (!hasPerms) return;
    if (!context.mounted) return;

    final ValueNotifier<double> progress = ValueNotifier(0.0);
    final ValueNotifier<String> statusText = ValueNotifier("Connexion au serveur...");

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.2), blurRadius: 30),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icône animée
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.system_update_alt_rounded, color: Color(0xFF6C63FF), size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Installation en cours",
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<String>(
                    valueListenable: statusText,
                    builder: (_, text, __) => Text(
                      text,
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.grey.shade500),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ValueListenableBuilder<double>(
                    valueListenable: progress,
                    builder: (_, value, __) => Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LinearProgressIndicator(
                            value: value > 0 ? value / 100 : null,
                            minHeight: 12,
                            color: const Color(0xFF6C63FF),
                            backgroundColor: const Color(0xFF6C63FF).withOpacity(0.1),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          value > 0 ? "${value.toStringAsFixed(0)} %" : "Préparation...",
                          style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 22,
                            color: isDark ? Colors.white : const Color(0xFF6C63FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Ne fermez pas l'application",
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white30 : Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // 🚀 Lancer le téléchargement MANUEL (Bypass permission storage sur Android 13+)
    try {
      // On utilise le dossier cache pour ne pas avoir besoin de permissions
      final dir = await getTemporaryDirectory();
      final savePath = "${dir.path}/infinity_update.apk";
      final file = File(savePath);

      if (await file.exists()) {
        await file.delete();
      }

      final request = await HttpClient().getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode == 200) {
        final totalBytes = response.contentLength;
        int receivedBytes = 0;

        statusText.value = "Téléchargement...";
        final sink = file.openWrite();

        await response.forEach((List<int> chunk) {
          receivedBytes += chunk.length;
          sink.add(chunk);
          if (totalBytes > 0) {
            progress.value = (receivedBytes / totalBytes) * 100;
          }
        });

        await sink.flush();
        await sink.close();

        statusText.value = "Finalisation...";
        progress.value = 100;
        
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // Ferme le modal
        }

        // 🚀 Lancer l'installation !
        final result = await OpenFile.open(savePath, type: "application/vnd.android.package-archive");
        debugPrint("Installation OTA résultat: ${result.message}");

      } else {
        throw Exception("Serveur injoignable (Code ${response.statusCode})");
      }
    } catch (e) {
      debugPrint("❌ OTA Launch Error: $e");
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Impossible de lancer la mise à jour : $e"),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }
}