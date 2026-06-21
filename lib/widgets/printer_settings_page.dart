// =============================================================================
// 🖨️ PRINTER SETTINGS PAGE — Paramètres d'impression (Bluetooth & Réseau)
// =============================================================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../services/print_service.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- ETAT GLOBAL ---
  String _savedType = "bluetooth"; // 'bluetooth' ou 'network'
  String _savedMac = "";
  String _savedIp = "";

  // --- ETAT BLUETOOTH ---
  List<BluetoothInfo> _btDevices = [];
  bool _isScanningBt = false;

  // --- ETAT RÉSEAU ---
  final TextEditingController _ipController = TextEditingController();
  List<String> _networkDevices = [];
  bool _isScanningNetwork = false;
  
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedPrinter();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  // ============================================
  // 💾 GESTION DES PRÉFÉRENCES
  // ============================================

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedType = prefs.getString('printer_type') ?? "bluetooth";
      _savedMac = prefs.getString('mac_printer') ?? "";
      _savedIp = prefs.getString('network_printer') ?? "";
      
      if (_savedType == "network") {
        _tabController.index = 1;
        _ipController.text = _savedIp;
      } else {
        _tabController.index = 0;
        _scanBluetooth(); // Lancer le scan BT par défaut
      }
    });
  }

  Future<void> _savePrinter(String type, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_type', type);
    
    if (type == 'bluetooth') {
      await prefs.setString('mac_printer', value);
      setState(() { _savedType = type; _savedMac = value; });
    } else {
      await prefs.setString('network_printer', value);
      setState(() { _savedType = type; _savedIp = value; });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Imprimante $type configurée avec succès !"), backgroundColor: Colors.green)
      );
    }
  }

  Future<void> _removePrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('printer_type');
    await prefs.remove('mac_printer');
    await prefs.remove('network_printer');
    setState(() {
      _savedType = "bluetooth";
      _savedMac = "";
      _savedIp = "";
    });
  }

  // ============================================
  // 🔵 LOGIQUE BLUETOOTH
  // ============================================

  Future<void> _scanBluetooth() async {
    if (!mounted) return;
    setState(() => _isScanningBt = true);
    try {
      // 🟢 FIX DETECTION IMPRIMANTE : Utilise getPairedDevices de PrintService (gère les perms)
      final List<BluetoothInfo> devices = await PrintService().getPairedDevices();
      if (devices.isEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Aucun appareil BT trouvé ou permissions manquantes."), backgroundColor: Colors.orange));
      }
      if (mounted) setState(() => _btDevices = devices);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ Erreur Bluetooth : $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isScanningBt = false);
    }
  }

  // ============================================
  // 🖧 LOGIQUE RÉSEAU (WIFI SCANNER)
  // ============================================

  Future<void> _scanNetwork() async {
    if (!mounted) return;
    setState(() {
      _isScanningNetwork = true;
      _networkDevices.clear();
    });

    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      
      if (wifiIP == null || wifiIP.isEmpty) {
        throw Exception("Veuillez vous connecter à un réseau Wi-Fi.");
      }

      final subnet = wifiIP.substring(0, wifiIP.lastIndexOf('.'));
      
      // On scanne les IP de 1 à 254
      final List<Future<void>> futures = [];
      for (int i = 1; i <= 254; i++) {
        futures.add(_checkPrinterIP('$subnet.$i'));
      }
      
      await Future.wait(futures);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur scan réseau: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isScanningNetwork = false);
    }
  }

  Future<void> _checkPrinterIP(String ip) async {
    try {
      // 🟢 FIX DETECTION IMPRIMANTE : Utilisation du ping rapide du service centralisé
      bool isAlive = await PrintService().pingPrinterIP(ip);
      if (isAlive && mounted) {
        setState(() {
          if (!_networkDevices.contains(ip)) _networkDevices.add(ip);
        });
      }
    } catch (_) {
      // Silencieux pour les IP inactives
    }
  }

  // ============================================
  // 🖨️ TEST IMPRESSION
  // ============================================

  Future<void> _printTestPage() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      final success = await PrintService().printTestPage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? "✅ Page de test imprimée !" : "❌ Échec : Vérifiez la connexion de l'imprimante."),
          backgroundColor: success ? Colors.green : Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  // ============================================
  // 🎨 BUILD UI
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text("Imprimante Ticket", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.teal,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.teal,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: "Bluetooth"),
            Tab(icon: Icon(Icons.wifi), text: "Réseau (LAN)"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBluetoothTab(isDark),
          _buildNetworkTab(isDark),
        ],
      ),
    );
  }

  // --- ONGLET BLUETOOTH ---
  Widget _buildBluetoothTab(bool isDark) {
    return Column(
      children: [
        _buildCurrentPrinterHeader(isDark, "bluetooth"),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Align(alignment: Alignment.centerLeft, child: Text("Appareils Appairés", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        ),
        Expanded(
          child: _isScanningBt 
            ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
            : _btDevices.isEmpty 
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text("Aucun appareil Bluetooth trouvé.\nAllez dans les paramètres Bluetooth de votre téléphone pour appairer l'imprimante.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  ))
                : ListView.builder(
                    itemCount: _btDevices.length,
                    itemBuilder: (context, index) {
                      final device = _btDevices[index];
                      final isSelected = _savedType == "bluetooth" && device.macAdress == _savedMac;

                      return ListTile(
                        leading: Icon(Icons.print, color: isSelected ? Colors.green : Colors.grey),
                        title: Text(device.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text(device.macAdress),
                        trailing: isSelected 
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : TextButton(
                              onPressed: () => _savePrinter("bluetooth", device.macAdress),
                              child: const Text("Choisir"),
                            ),
                      );
                    },
                  ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton.icon(
            onPressed: _scanBluetooth,
            icon: const Icon(Icons.refresh),
            label: const Text("Rafraîchir"),
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          ),
        ),
      ],
    );
  }

  // --- ONGLET RÉSEAU ---
  Widget _buildNetworkTab(bool isDark) {
    return Column(
      children: [
        _buildCurrentPrinterHeader(isDark, "network"),
        
        // Saisie manuelle IP
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              const Icon(FontAwesomeIcons.networkWired, size: 16, color: Colors.teal),
              const SizedBox(width: 15),
              Expanded(
                child: TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: "Saisie manuelle IP (ex: 192.168.1.87)",
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (_ipController.text.isNotEmpty) {
                    _savePrinter("network", _ipController.text.trim());
                  }
                },
                child: const Text("Sauvegarder", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Align(alignment: Alignment.centerLeft, child: Text("Imprimantes détectées sur le réseau", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        ),

        Expanded(
          child: _isScanningNetwork 
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.teal),
                  const SizedBox(height: 15),
                  Text("Recherche d'imprimantes (Port 9100)...", style: TextStyle(color: Colors.grey[600])),
                ],
              )
            : _networkDevices.isEmpty 
                ? const Center(child: Text("Aucune imprimante détectée automatiquement.\nUtilisez la saisie manuelle ci-dessus.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _networkDevices.length,
                    itemBuilder: (context, index) {
                      final ip = _networkDevices[index];
                      final isSelected = _savedType == "network" && ip == _savedIp;

                      return ListTile(
                        leading: Icon(FontAwesomeIcons.print, color: isSelected ? Colors.green : Colors.grey, size: 20),
                        title: const Text("Imprimante Thermique (Réseau)"),
                        subtitle: Text("IP : $ip"),
                        trailing: isSelected 
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : TextButton(
                              onPressed: () {
                                _ipController.text = ip;
                                _savePrinter("network", ip);
                              },
                              child: const Text("Choisir"),
                            ),
                      );
                    },
                  ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton.icon(
            onPressed: _scanNetwork,
            icon: const Icon(Icons.radar),
            label: const Text("Scanner le réseau"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // --- HEADER IMPRIMANTE ACTUELLE ---
  Widget _buildCurrentPrinterHeader(bool isDark, String tabType) {
    final isConfigured = _savedType == tabType && 
                        (tabType == 'bluetooth' ? _savedMac.isNotEmpty : _savedIp.isNotEmpty);
    
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isConfigured ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isConfigured ? Icons.check_circle : Icons.info_outline, color: isConfigured ? Colors.green : Colors.blueAccent),
              const SizedBox(width: 10),
              const Expanded(child: Text("Imprimante actuelle :", style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 10),
          if (isConfigured) ...[
            Text(
              tabType == 'bluetooth' ? "MAC: $_savedMac" : "IP: $_savedIp", 
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _removePrinter,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1), elevation: 0),
                  icon: const Icon(Icons.link_off, size: 16, color: Colors.redAccent),
                  label: const Text("Déconnecter", style: TextStyle(color: Colors.redAccent)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _printTestPage,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.1), elevation: 0),
                    icon: _isPrinting 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green))
                      : const Icon(Icons.print, size: 16, color: Colors.green),
                    label: const Text("Test", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          ] else
            Text("Aucune imprimante $tabType configurée.", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}