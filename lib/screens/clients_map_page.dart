import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../core/constants.dart';
import 'sales_page.dart';

class ClientsMapPage extends StatefulWidget {
  const ClientsMapPage({Key? key}) : super(key: key);

  @override
  State<ClientsMapPage> createState() => _ClientsMapPageState();
}

class _ClientsMapPageState extends State<ClientsMapPage> {
  final ApiService _api = ApiService();
  List<dynamic> _clients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    final clients = await _api.getTiersWithQueue('client', '');
    setState(() {
      _clients = clients.where((c) => c['geo_lat'] != null && c['geo_lng'] != null && c['geo_lat'].toString().isNotEmpty && c['geo_lng'].toString().isNotEmpty).toList();
      _isLoading = false;
    });
  }

  void _showClientDetails(dynamic client) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        double balance = double.tryParse(client['balance']?.toString() ?? '0') ?? 0.0;
        bool hasDebt = balance > 0;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2C).withOpacity(0.95) : Colors.white.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50, height: 5, 
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(10))
                  )
                ),
                const SizedBox(height: 20),
                Text(client['name'] ?? 'Client Inconnu', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                if (client['phone'] != null && client['phone'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.phone, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(client['phone'], style: const TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: hasDebt ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(hasDebt ? "Dette" : "Solde", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: hasDebt ? Colors.red : Colors.green)),
                      Text("${balance.toStringAsFixed(2)} DZD", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: hasDebt ? Colors.red : Colors.green)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final lat = client['geo_lat'];
                          final lng = client['geo_lng'];
                          final uri = Uri.parse("google.navigation:q=$lat,$lng");
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          } else {
                            final webUri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng");
                            if (await canLaunchUrl(webUri)) {
                              await launchUrl(webUri, mode: LaunchMode.externalApplication);
                            }
                          }
                        },
                        icon: const Icon(Icons.navigation_rounded),
                        label: const Text("Naviguer vers"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => SalesPage(onBack: () => Navigator.pop(context))));
                        },
                        icon: const Icon(Icons.shopping_cart_rounded),
                        label: const Text("Créer Vente"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Carte Clients", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.5),
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : FlutterMap(
            options: MapOptions(
              initialCenter: _clients.isNotEmpty 
                  ? LatLng(double.tryParse(_clients.first['geo_lat'].toString()) ?? 36.752887, double.tryParse(_clients.first['geo_lng'].toString()) ?? 3.042048) 
                  : const LatLng(36.752887, 3.042048),
              initialZoom: 10.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.infinity.pos',
              ),
              MarkerLayer(
                markers: _clients.map((client) {
                  final lat = double.tryParse(client['geo_lat'].toString()) ?? 0.0;
                  final lng = double.tryParse(client['geo_lng'].toString()) ?? 0.0;
                  double balance = double.tryParse(client['balance']?.toString() ?? '0') ?? 0.0;
                  bool hasDebt = balance > 0;

                  return Marker(
                    point: LatLng(lat, lng),
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onTap: () => _showClientDetails(client),
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: hasDebt ? Colors.red : Colors.blue,
                        shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
    );
  }
}
