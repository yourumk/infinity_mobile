import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

// ✅ Le nom de la classe doit correspondre à ce que vous appelez dans le Dashboard
class OfflineQueuePage extends StatefulWidget {
  const OfflineQueuePage({super.key});

  @override
  State<OfflineQueuePage> createState() => _OfflineQueuePageState();
}

class _OfflineQueuePageState extends State<OfflineQueuePage> {
  final ApiService _api = ApiService();
  bool _isSyncing = false;

  Future<void> _forceSync() async {
    setState(() => _isSyncing = true);
    // ✅ Maintenant cette méthode existe grâce à l'étape 2
    await _api.syncQueueNow();
    if (mounted) setState(() => _isSyncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final queue = _api.currentQueue;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7);

    // ✅ On ajoute un Scaffold car c'est une nouvelle page (Navigator.push)
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Synchronisation"),
        backgroundColor: isDark ? const Color(0xFF1C1C23) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("File d'attente (${queue.length})", 
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)
                ),
                if (queue.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _forceSync,
                    icon: _isSyncing 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync, size: 18, color: Colors.white),
                    label: Text(_isSyncing ? "Envoi..." : "Forcer l'envoi", style: const TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  )
              ],
            ),
          ),
          Expanded(
            child: queue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done, size: 80, color: Colors.green.withOpacity(0.5)),
                      const SizedBox(height: 20),
                      Text("Tout est synchronisé !", style: TextStyle(color: Colors.grey[500], fontSize: 18))
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(15),
                  itemCount: queue.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final item = queue[i];
                    // Gestion sécurisée de la date
                    DateTime date;
                    if (item['date'] is DateTime) {
                      date = item['date'];
                    } else if (item['date'] is String) {
                      date = DateTime.tryParse(item['date']) ?? DateTime.now();
                    } else {
                      date = DateTime.now();
                    }
                    
                    final total = item['total'] ?? 0.0;
                    final type = item['type'] ?? 'Vente';
                    
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.withOpacity(0.2),
                          child: const Icon(Icons.wifi_off, color: Colors.orange, size: 20),
                        ),
                        title: Text("$type - ${NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA').format(total)}",
                          style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)
                        ),
                        subtitle: Text(DateFormat('dd/MM HH:mm').format(date)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_forever, color: Colors.red),
                          onPressed: () {
                            // Optionnel : Supprimer manuellement de la file
                            setState(() {
                              _api.currentQueue.removeAt(i);
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}