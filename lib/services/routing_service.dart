import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  /// Récupère la route entre plusieurs points (minimum 2) en utilisant OSRM
  Future<List<LatLng>> getRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return [];

    try {
      // Construction de la chaîne de coordonnées : lng,lat;lng,lat...
      final coordString = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
      
      final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/$coordString?geometries=geojson&overview=full'
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          
          if (geometry != null && geometry['coordinates'] != null) {
            final List<dynamic> coords = geometry['coordinates'];
            // GeoJSON retourne [longitude, latitude]
            return coords.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
          }
        }
      }
      return [];
    } catch (e) {
      print("Erreur OSRM Routing: $e");
      return [];
    }
  }
}
