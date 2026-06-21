import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../services/api_service.dart';

class SpotlightSearch extends SearchDelegate<Map<String, dynamic>?> {
  final ApiService _api = ApiService();
  final Function(int) onNavigateToTab;

  // Caches locaux
  List<dynamic> _products = [];
  List<dynamic> _clients = [];
  List<dynamic> _suppliers = [];
  bool _loaded = false;

  // Historique des recherches en RAM
  static final List<String> _recentSearches = [];

  SpotlightSearch({required this.onNavigateToTab})
      : super(
          searchFieldLabel: 'Rechercher partout...',
          searchFieldStyle: const TextStyle(fontSize: 16),
        );

  // ============================================
  // 📦 CHARGEMENT DES DONNÉES (UNE SEULE FOIS)
  // ============================================
  Future<void> _loadAllData() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? '';
      bool hasClientsPerm = false;
      bool hasSuppliersPerm = false;

      if (role == 'admin') {
        hasClientsPerm = true;
        hasSuppliersPerm = true;
      } else {
        final permsString = prefs.getString('user_permissions') ?? '[]';
        try {
          final List<dynamic> perms = json.decode(permsString);
          hasClientsPerm = perms.contains('mobile_clients');
          hasSuppliersPerm = perms.contains('mobile_suppliers');
        } catch (_) {}
      }

      final catalogRes = await _api.getMobileProductCatalog();
      _products = catalogRes['products'] ?? [];
      
      if (hasClientsPerm) {
        _clients = await _api.getTiersList('clients', '');
      }
      if (hasSuppliersPerm) {
        _suppliers = await _api.getTiersList('suppliers', '');
      }
      
      _loaded = true;
    } catch (_) {}
  }

  // ============================================
  // 🧠 ALGORITHME FUZZY MATCHING
  // ============================================

  static int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<List<int>> matrix = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => 0),
    );

    for (int i = 0; i <= a.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= b.length; j++) matrix[0][j] = j;

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        int cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce(min);
      }
    }
    return matrix[a.length][b.length];
  }

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[àâä]'), 'a')
        .replaceAll(RegExp(r'[ùûü]'), 'u')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '');
  }

  static double _matchScore(String query, List<String> fields) {
    final queryWords = _normalize(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (queryWords.isEmpty) return 0.0;

    double totalScore = 0;

    for (final word in queryWords) {
      double bestWordScore = 0;

      for (final field in fields) {
        final normField = _normalize(field);
        if (normField.isEmpty) continue;

        if (normField.contains(word)) {
          double score = normField.startsWith(word) ? 1.0 : 0.85;
          bestWordScore = max(bestWordScore, score);
          continue;
        }

        for (final fieldWord in normField.split(RegExp(r'\s+'))) {
          if (fieldWord.isEmpty) continue;
          int dist = _levenshtein(word, fieldWord);
          int maxLen = max(word.length, fieldWord.length);
          if (maxLen == 0) continue;
          double similarity = 1.0 - (dist / maxLen);

          if (similarity > 0.6) {
            bestWordScore = max(bestWordScore, similarity * 0.7);
          }
        }
      }

      if (bestWordScore == 0) return 0;
      totalScore += bestWordScore;
    }

    return totalScore / queryWords.length;
  }

  List<Map<String, dynamic>> _search(String query) {
    if (query.trim().isEmpty) return [];

    List<Map<String, dynamic>> results = [];

    // --- PRODUITS ---
    for (final p in _products) {
      final fields = [
        p['name']?.toString() ?? '',
        p['ref']?.toString() ?? '',
        p['reference']?.toString() ?? '',
        p['barcode']?.toString() ?? '',
      ];
      final score = _matchScore(query, fields);
      if (score > 0) {
        results.add({
          'type': 'product',
          'data': p,
          'score': score,
          'name': p['name'] ?? 'Produit',
          'subtitle': 'Stock: ${p['stock'] ?? 0} • ${p['ref'] ?? ''}',
          'icon': FontAwesomeIcons.box,
          'color': AppColors.primary,
        });
      }
    }

    // --- CLIENTS ---
    for (final c in _clients) {
      final fields = [
        c['name']?.toString() ?? '',
        c['phone']?.toString() ?? '',
        c['email']?.toString() ?? '',
        c['company']?.toString() ?? '',
      ];
      final score = _matchScore(query, fields);
      if (score > 0) {
        results.add({
          'type': 'client',
          'data': c,
          'score': score,
          'name': c['name'] ?? 'Client',
          'subtitle': c['phone'] ?? '',
          'icon': FontAwesomeIcons.userTie,
          'color': Colors.blue,
        });
      }
    }

    // --- FOURNISSEURS ---
    for (final s in _suppliers) {
      final fields = [
        s['name']?.toString() ?? '',
        s['phone']?.toString() ?? '',
        s['email']?.toString() ?? '',
      ];
      final score = _matchScore(query, fields);
      if (score > 0) {
        results.add({
          'type': 'supplier',
          'data': s,
          'score': score,
          'name': s['name'] ?? 'Fournisseur',
          'subtitle': s['phone'] ?? '',
          'icon': FontAwesomeIcons.truck,
          'color': Colors.orange,
        });
      }
    }

    results.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    return results.take(30).toList();
  }

  void _addRecentSearch(String term) {
    final t = term.trim();
    if (t.isEmpty) return;
    _recentSearches.remove(t);
    _recentSearches.insert(0, t);
    if (_recentSearches.length > 5) {
      _recentSearches.removeLast();
    }
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Theme.of(context).copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1C1C23) : Colors.white,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.grey[500]),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().isNotEmpty) {
      _addRecentSearch(query);
    }
    return _SpotlightResultsWrapper(delegate: this, query: query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _SpotlightResultsWrapper(delegate: this, query: query);
  }
}

class _SpotlightResultsWrapper extends StatefulWidget {
  final SpotlightSearch delegate;
  final String query;

  const _SpotlightResultsWrapper({required this.delegate, required this.query});

  @override
  State<_SpotlightResultsWrapper> createState() => _SpotlightResultsWrapperState();
}

class _SpotlightResultsWrapperState extends State<_SpotlightResultsWrapper> {
  Timer? _debounce;
  String _debouncedQuery = '';
  late Future<void> _dataFuture;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _debouncedQuery = widget.query;
    _dataFuture = widget.delegate._loadAllData();
  }

  @override
  void didUpdateWidget(_SpotlightResultsWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      
      setState(() {
        _isSearching = widget.query.trim().isNotEmpty;
      });

      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _debouncedQuery = widget.query;
            _isSearching = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder(
      future: _dataFuture,
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !widget.delegate._loaded) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        if (widget.query.trim().isEmpty) {
          return _buildEmptyState(isDark);
        }

        final results = widget.delegate._search(_debouncedQuery);

        return Column(
          children: [
            if (_isSearching)
              const LinearProgressIndicator(color: AppColors.primary, minHeight: 2),
            Expanded(
              child: results.isEmpty && !_isSearching
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 60, color: Colors.grey.withOpacity(0.3)),
                          const SizedBox(height: 15),
                          Text("Aucun résultat pour \"${_debouncedQuery}\"", style: const TextStyle(color: Colors.grey, fontSize: 16)),
                          const SizedBox(height: 8),
                          const Text("Essayez un autre terme ou vérifiez l'orthographe.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(15),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => Divider(color: Colors.grey.withOpacity(0.1), height: 1),
                      itemBuilder: (ctx, i) {
                        final r = results[i];
                        final score = ((r['score'] as double) * 100).toInt();
                        final typeLabel = r['type'] == 'product' ? 'Produit' : (r['type'] == 'client' ? 'Client' : 'Fournisseur');
                        final typeColor = r['color'] as Color;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          leading: Container(
                            width: 45, height: 45,
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(r['icon'] as IconData, color: typeColor, size: 20),
                          ),
                          title: Text(
                            r['name'],
                            style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: typeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(typeLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(r['subtitle'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("$score%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: score > 80 ? Colors.green : Colors.orange)),
                              const Text("match", style: TextStyle(fontSize: 9, color: Colors.grey)),
                            ],
                          ),
                          onTap: () {
                            widget.delegate._addRecentSearch(_debouncedQuery);
                            widget.delegate.close(context, r);
                            if (r['type'] == 'product') {
                              widget.delegate.onNavigateToTab(4); // Stock
                            } else if (r['type'] == 'client') {
                              widget.delegate.onNavigateToTab(6); // Clients
                            } else if (r['type'] == 'supplier') {
                              widget.delegate.onNavigateToTab(12); // Fournisseurs
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (SpotlightSearch._recentSearches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Recherches récentes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                TextButton(
                  onPressed: () => setState(() => SpotlightSearch._recentSearches.clear()),
                  child: const Text("Effacer", style: TextStyle(color: Colors.red)),
                )
              ],
            ),
          ),
        if (SpotlightSearch._recentSearches.isNotEmpty)
          ...SpotlightSearch._recentSearches.map((term) => ListTile(
                leading: const Icon(Icons.history, color: Colors.grey),
                title: Text(term, style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                trailing: const Icon(Icons.north_west, size: 16, color: Colors.grey),
                onTap: () {
                  widget.delegate.query = term;
                },
              )),
        
        const SizedBox(height: 30),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.search, size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              Text("Recherche Globale", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 8),
              Text("Produits • Clients • Fournisseurs", style: TextStyle(color: Colors.grey[500], fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 🔧 FUZZY SEARCH HELPER - Utilisable partout dans l'app
// =============================================================================
class FuzzySearchHelper {
  static List<T> filter<T>({
    required String query,
    required List<T> items,
    required List<String> Function(T item) getFields,
    double threshold = 0.4,
  }) {
    if (query.trim().isEmpty) return items;

    final scored = <MapEntry<T, double>>[];

    for (final item in items) {
      final fields = getFields(item);
      final score = SpotlightSearch._matchScore(query, fields);
      if (score >= threshold) {
        scored.add(MapEntry(item, score));
      }
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }
}
