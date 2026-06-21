import 'package:flutter/material.dart';
import '../providers/feature_provider.dart';

class FeatureGuard extends StatefulWidget {
  final String feature;
  final Widget child;
  final Widget fallback;

  const FeatureGuard({
    Key? key,
    required this.feature,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  }) : super(key: key);

  @override
  State<FeatureGuard> createState() => _FeatureGuardState();
}

class _FeatureGuardState extends State<FeatureGuard> {
  @override
  void initState() {
    super.initState();
    FeatureProvider.instance.addListener(_onFeatureChanged);
  }

  @override
  void dispose() {
    FeatureProvider.instance.removeListener(_onFeatureChanged);
    super.dispose();
  }

  void _onFeatureChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isAllowed = false;

    switch (widget.feature) {
      case 'feature_cash_manager_unlocked':
        isAllowed = FeatureProvider.instance.hasCashManager;
        break;
      case 'feature_fleet_management':
        isAllowed = FeatureProvider.instance.hasFleetManagement;
        break;
      case 'feature_gps_tracking':
        isAllowed = FeatureProvider.instance.hasGpsTracking;
        break;
      default:
        isAllowed = false;
    }

    return isAllowed ? widget.child : widget.fallback;
  }
}
