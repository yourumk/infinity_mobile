import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RequirePermission extends StatelessWidget {
  final String permission;
  final Widget child;
  final Widget? fallback;

  const RequirePermission({
    Key? key,
    required this.permission,
    required this.child,
    this.fallback,
  }) : super(key: key);

  Future<bool> _hasPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';
    
    // 👑 L'admin a accès à TOUT
    if (role.toLowerCase() == 'admin') return true;

    final permsString = prefs.getString('user_permissions') ?? '[]';
    try {
      final List<dynamic> perms = json.decode(permsString);
      return perms.contains(permission);
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasPermission(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink(); // Gère gracieusement le chargement sans faire clignoter l'UI
        }

        if (snapshot.hasError) {
          return fallback ?? const SizedBox.shrink();
        }

        if (snapshot.data == true) {
          return child;
        }

        // Si l'accès est refusé, on montre le fallback (ou rien)
        return fallback ?? const SizedBox.shrink();
      },
    );
  }
}
