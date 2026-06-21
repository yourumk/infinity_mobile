import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';
import 'package:geolocator/geolocator.dart';

import '../core/constants.dart';
import '../services/api_service.dart';
import '../services/gps_service.dart';
import '../widgets/glass_card.dart';

class TransferReceptionPage extends StatefulWidget {
  final dynamic transferId;
  const TransferReceptionPage({super.key, required this.transferId});

  @override
  State<TransferReceptionPage> createState() => _TransferReceptionPageState();
}

class _TransferReceptionPageState extends State<TransferReceptionPage> {
  final ApiService _api = ApiService();
  final FocusNode _scanFocusNode = FocusNode();
  final TextEditingController _manualBarcodeCtrl = TextEditingController();

  Map<String, dynamic> _transfer = {};
  List<Map<String, dynamic>> _items = []; // Expected items from transfer
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _scanBuffer = ''; // For Bluetooth HID scanner
  
  bool _geofenceLocked = false;
  double _distanceToDest = 0.0;
  final GpsTrackingService _gps = GpsTrackingService();

  @override
  void initState() {
    super.initState();
    _loadTransferDetails();
  }

  @override
  void dispose() {
    _scanFocusNode.dispose();
    _manualBarcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTransferDetails() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.getTransferDetails(widget.transferId);
      if (mounted) {
        final rawItems = (data['items'] as List<dynamic>?) ?? [];
        setState(() {
          _transfer = data;
          _items = rawItems.map((item) {
            return <String, dynamic>{
              'product_id': item['product_id'],
              'variant_id': item['variant_id'],
              'product_name': item['product_name'] ?? item['name'] ?? 'Article',
              'barcode': item['barcode'] ?? '',
              'expected_qty': _parseDouble(item['quantity'] ?? item['expected_qty'] ?? item['qty']),
              'scanned_qty': 0.0,
            };
          }).toList();
          _isLoading = false;
        });
        
        // 🔒 GEOFENCING LOGIC
        _checkGeofence();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur chargement: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  double _parseDouble(dynamic val) => double.tryParse(val?.toString() ?? '0') ?? 0;

  Future<void> _checkGeofence() async {
    try {
      final toLat = _parseDouble(_transfer['to_lat']);
      final toLng = _parseDouble(_transfer['to_lng']);
      
      if (toLat != 0 && toLng != 0) {
        final pos = await _gps.getCurrentPosition();
        if (pos != null) {
          final distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, toLat, toLng);
          if (mounted) {
            setState(() {
              _distanceToDest = distance;
              _geofenceLocked = distance > 200.0;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Geofence check failed: $e");
    }
  }

  // ═══════════════════════════════════════
  // SCAN LOGIC
  // ═══════════════════════════════════════

  /// Process a scanned barcode (from camera or HID scanner)
  void _processBarcode(String barcode) {
    if (barcode.isEmpty) return;
    final cleanBarcode = barcode.trim();

    // Find the item matching this barcode
    int matchIndex = _items.indexWhere((item) =>
        item['barcode']?.toString() == cleanBarcode ||
        item['product_id']?.toString() == cleanBarcode);

    if (matchIndex >= 0) {
      setState(() {
        double scanned = _items[matchIndex]['scanned_qty'] as double;
        double expected = _items[matchIndex]['expected_qty'] as double;
        if (scanned < expected) {
          _items[matchIndex]['scanned_qty'] = scanned + 1;
          HapticFeedback.lightImpact(); // ✅ Vibration feedback
        } else {
          HapticFeedback.heavyImpact(); // ⚠️ Over-scan
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('⚠️ ${_items[matchIndex]['product_name']} — Quantité max atteinte ($expected)'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ));
        }
      });
    } else {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Code-barres "$cleanBarcode" non trouvé dans ce transfert'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  /// Open camera scanner (ai_barcode_scanner)
  Future<void> _openCameraScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => AiBarcodeScanner(
          onDetect: (BarcodeCapture capture) {
            final String? value = capture.barcodes.firstOrNull?.rawValue;
            if (value != null && value.isNotEmpty) {
              _processBarcode(value);
            }
          },
          onDispose: () {},
          controller: MobileScannerController(detectionSpeed: DetectionSpeed.normal),
        ),
      ),
    );
  }

  /// Handle keyboard input from Bluetooth HID scanner
  void _onHidKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        // HID scanners send Enter at end of barcode
        _processBarcode(_scanBuffer);
        _scanBuffer = '';
      } else {
        final char = event.character;
        if (char != null && char.isNotEmpty) {
          _scanBuffer += char;
        }
      }
    }
  }

  /// Manual barcode entry
  void _showManualEntryDialog() {
    _manualBarcodeCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(FontAwesomeIcons.keyboard, size: 18, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Saisie Manuelle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: TextField(
          controller: _manualBarcodeCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Code-barres ou référence',
            border: OutlineInputBorder(),
            prefixIcon: Icon(FontAwesomeIcons.barcode, size: 16),
          ),
          onSubmitted: (val) {
            _processBarcode(val);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              _processBarcode(_manualBarcodeCtrl.text);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Valider', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // RECEPTION LOGIC
  // ═══════════════════════════════════════
  int get _totalExpected => _items.fold(0, (sum, it) => sum + (it['expected_qty'] as double).round());
  int get _totalScanned => _items.fold(0, (sum, it) => sum + (it['scanned_qty'] as double).round());
  double get _progress => _totalExpected > 0 ? _totalScanned / _totalExpected : 0;

  Future<void> _submitReception() async {
    final missing = <Map<String, dynamic>>[];
    for (var item in _items) {
      double expected = item['expected_qty'] as double;
      double scanned = item['scanned_qty'] as double;
      if (scanned < expected) {
        missing.add({
          'product_id': item['product_id'],
          'variant_id': item['variant_id'],
          'qty': (expected - scanned).round(),
        });
      }
    }

    if (missing.isNotEmpty) {
      // Show confirmation dialog for partial reception
      final totalMissing = missing.fold(0, (sum, m) => sum + (m['qty'] as int));
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(FontAwesomeIcons.triangleExclamation, color: Colors.orange, size: 28),
          ),
          title: const Text('Réception Partielle', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(fontSize: 14, color: Theme.of(ctx).textTheme.bodyMedium?.color, height: 1.5),
                  children: [
                    const TextSpan(text: 'Attention, il manque '),
                    TextSpan(text: '$totalMissing article(s)', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.orange)),
                    const TextSpan(text: '.\n\nIls seront déclarés en '),
                    const TextSpan(text: 'Perte / Casse', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red)),
                    const TextSpan(text: '.\n\nConfirmez-vous la réception partielle ?'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Missing items summary
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                ),
                constraints: const BoxConstraints(maxHeight: 120),
                child: ListView(
                  shrinkWrap: true,
                  children: missing.map((m) {
                    final item = _items.firstWhere(
                      (it) => it['product_id'] == m['product_id'],
                      orElse: () => {'product_name': 'Produit'},
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                          const SizedBox(width: 6),
                          Expanded(child: Text(item['product_name'], style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text('−${m['qty']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Confirmer la réception', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // Submit
    setState(() => _isSubmitting = true);
    try {
      final ok = await _api.receiveTransfer(widget.transferId, missing);
      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Réception validée avec succès !'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ));
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ Erreur lors de la validation. Réessayez.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erreur: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return KeyboardListener(
      focusNode: _scanFocusNode,
      autofocus: true,
      onKeyEvent: _onHidKey,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7),
        body: Column(
          children: [
            _buildHeader(isDark),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : _items.isEmpty
                      ? _buildEmptyItems(isDark)
                      : SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              const SizedBox(height: 16),
                              if (_geofenceLocked) _buildGeofenceAlert(isDark),
                              if (_geofenceLocked) const SizedBox(height: 12),
                              _buildProgressCard(isDark),
                              const SizedBox(height: 12),
                              if (!_geofenceLocked) _buildScanActions(isDark),
                              if (!_geofenceLocked) const SizedBox(height: 16),
                              _buildItemsTable(isDark),
                              const SizedBox(height: 16),
                              _buildSubmitButton(isDark),
                              const SizedBox(height: 120),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════
  Widget _buildHeader(bool isDark) {
    final ref = _transfer['reference'] ?? 'TRF-${widget.transferId}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade700, Colors.teal.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.teal.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("RÉCEPTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 2)),
                const SizedBox(height: 2),
                Text(ref.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                if (_transfer['van_name'] != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(FontAwesomeIcons.truckFast, size: 10, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text('${_transfer['van_name']} (${_transfer['driver_name'] ?? 'Chauffeur'})', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: Text('$_totalScanned / $_totalExpected', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // PROGRESS CARD
  // ═══════════════════════════════════════
  Widget _buildProgressCard(bool isDark) {
    final pct = (_progress * 100).round();
    final isComplete = _totalScanned >= _totalExpected;
    final progressColor = isComplete ? AppColors.success : (_progress > 0.5 ? Colors.orange : AppColors.primary);

    return GlassCard(
      isDark: isDark,
      borderRadius: 18,
      padding: const EdgeInsets.all(18),
      borderColor: isComplete ? AppColors.success.withValues(alpha: 0.5) : null,
      child: Column(
        children: [
          Row(
            children: [
              Icon(isComplete ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.spinner, color: progressColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isComplete ? 'Réception Complète !' : 'Scan en cours...',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black),
                ),
              ),
              Text('$pct%', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: progressColor)),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 10,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$_totalScanned scannés', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: progressColor)),
              Text('$_totalExpected attendus', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // SCAN ACTIONS
  // ═══════════════════════════════════════
  Widget _buildScanActions(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _openCameraScanner,
              icon: const Icon(FontAwesomeIcons.camera, size: 16),
              label: const Text('Scanner', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _showManualEntryDialog,
              icon: Icon(FontAwesomeIcons.keyboard, size: 14, color: isDark ? Colors.white70 : AppColors.primary),
              label: Text('Saisie manuelle', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: isDark ? Colors.white70 : AppColors.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // ITEMS TABLE
  // ═══════════════════════════════════════
  Widget _buildItemsTable(bool isDark) {
    return GlassCard(
      isDark: isDark,
      borderRadius: 16,
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 4, child: Text('Produit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                SizedBox(width: 44, child: Text('Att.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                SizedBox(width: 44, child: Text('Scan', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                SizedBox(width: 36, child: Text('', textAlign: TextAlign.center)),
              ],
            ),
          ),
          // Rows
          ..._items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final expected = (item['expected_qty'] as double).round();
            final scanned = (item['scanned_qty'] as double).round();
            final isComplete = scanned >= expected;
            final isPartial = scanned > 0 && scanned < expected;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isComplete
                    ? AppColors.success.withValues(alpha: 0.06)
                    : isPartial
                        ? Colors.orange.withValues(alpha: 0.04)
                        : Colors.transparent,
                border: Border(bottom: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['product_name'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if ((item['barcode'] ?? '').toString().isNotEmpty)
                          Text(item['barcode'], style: TextStyle(fontSize: 9, color: isDark ? Colors.white30 : Colors.grey)),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('$expected', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? Colors.white54 : Colors.grey.shade700)),
                  ),
                  GestureDetector(
                    onTap: () {
                      // Tap to manually increment
                      if (scanned < expected) {
                        setState(() => _items[i]['scanned_qty'] = (item['scanned_qty'] as double) + 1);
                        HapticFeedback.selectionClick();
                      }
                    },
                    onLongPress: () {
                      // Long press to reset
                      setState(() => _items[i]['scanned_qty'] = 0.0);
                    },
                    child: Container(
                      width: 44,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isComplete
                            ? AppColors.success.withValues(alpha: 0.15)
                            : isPartial
                                ? Colors.orange.withValues(alpha: 0.15)
                                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$scanned',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isComplete ? AppColors.success : isPartial ? Colors.orange : (isDark ? Colors.white38 : Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Center(
                      child: Icon(
                        isComplete ? FontAwesomeIcons.circleCheck : isPartial ? FontAwesomeIcons.circleHalfStroke : FontAwesomeIcons.circle,
                        size: 16,
                        color: isComplete ? AppColors.success : isPartial ? Colors.orange : (isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // SUBMIT BUTTON
  // ═══════════════════════════════════════
  Widget _buildSubmitButton(bool isDark) {
    final isComplete = _totalScanned >= _totalExpected;
    final hasScans = _totalScanned > 0;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isSubmitting || !hasScans || _geofenceLocked ? null : _submitReception,
        icon: _isSubmitting
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(isComplete ? FontAwesomeIcons.check : FontAwesomeIcons.triangleExclamation, size: 18),
        label: Text(
          _isSubmitting
              ? 'Envoi en cours...'
              : isComplete
                  ? 'CLÔTURER — Réception Complète'
                  : 'CLÔTURER — $_totalScanned/$_totalExpected scannés',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isComplete ? AppColors.success : Colors.orange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: isComplete ? 4 : 0,
          shadowColor: isComplete ? AppColors.success.withValues(alpha: 0.4) : Colors.transparent,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════
  Widget _buildEmptyItems(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(FontAwesomeIcons.boxOpen, color: Colors.teal, size: 40),
          ),
          const SizedBox(height: 16),
          Text('Aucun article dans ce transfert', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadTransferDetails,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Recharger'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
  }
  
  // ═══════════════════════════════════════
  // GEOFENCE ALERT
  // ═══════════════════════════════════════
  Widget _buildGeofenceAlert(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(FontAwesomeIcons.locationDot, color: AppColors.error, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GEOFENCING : ACCÈS BLOQUÉ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.error, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('Vous êtes à ${_distanceToDest.toStringAsFixed(0)}m du dépôt de destination. Vous devez être à moins de 200m pour réceptionner ce transfert.', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
