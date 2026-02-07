// lib/core/smart_search.dart

class SmartSearch {
  
  // Fonction principale qui filtre et trie intelligemment
  static List<dynamic> search(List<dynamic> items, String query) {
    if (query.isEmpty) return items;

    final cleanQuery = _normalize(query);
    final queryTokens = cleanQuery.split(' '); // Sépare les mots "Yaourt Fraise" -> ["yaourt", "fraise"]

    // 1. Calculer un score pour chaque produit
    final List<Map<String, dynamic>> scoredItems = items.map((item) {
      int score = 0;

      // Extraction des données
      final name = _normalize(item['name'] ?? '');
      final ref = _normalize(item['ref'] ?? '');
      final barcode = _normalize(item['barcode'] ?? '');
      final category = _normalize(item['category'] ?? '');

      // --- ALGORITHME DE SCORING "IA" ---

      // A. Priorité ABSOLUE : Code Barre ou Réf exact (Scan)
      if (barcode == cleanQuery) score += 1000;
      if (ref == cleanQuery) score += 900;

      // B. Correspondance forte (Commence par...)
      if (name.startsWith(cleanQuery)) score += 500;
      if (ref.startsWith(cleanQuery)) score += 400;

      // C. Correspondance des mots clés (Intelligence contextuelle)
      int wordsMatched = 0;
      for (var token in queryTokens) {
        if (token.isEmpty) continue;
        if (name.contains(token)) {
          score += 100;
          wordsMatched++;
        }
        if (category.contains(token)) score += 50; // Recherche par catégorie aussi
        if (ref.contains(token)) score += 80;
      }

      // Bonus si tous les mots sont trouvés (ex: "Jus Orange" trouve bien "Jus d'orange")
      if (wordsMatched == queryTokens.length) score += 200;

      // On retourne l'objet original + son score
      return {'data': item, 'score': score};
    }).toList();

    // 2. Ne garder que ceux qui ont un score > 0
    final filtered = scoredItems.where((i) => (i['score'] as int) > 0).toList();

    // 3. Trier par pertinence (Le plus gros score en premier)
    filtered.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    // 4. Retourner la liste propre
    return filtered.map((i) => i['data']).toList();
  }

  // Petit nettoyeur de texte (enlève accents et majuscules)
  static String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[àâ]'), 'a')
        .replaceAll(RegExp(r'[ùû]'), 'u')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ô]'), 'o')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .trim();
  }
}