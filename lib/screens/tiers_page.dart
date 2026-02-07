import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/api_service.dart';
import 'client_details_page.dart';
import 'supplier_details_page.dart';

class TiersPage extends StatefulWidget {
  final String initialTab; 
  final VoidCallback? onBack; 

  const TiersPage({super.key, this.initialTab = 'clients', this.onBack});

  @override
  State<TiersPage> createState() => _TiersPageState();
}

class _TiersPageState extends State<TiersPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  
  StreamSubscription? _syncSubscription;
  Timer? _debounce;
  
  late String _activeTab;
  List<dynamic> _list = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _fetchData();

    // Écoute automatique des mises à jour (Dès qu'on ajoute un tiers, ça refresh)
    _syncSubscription = _api.onDataUpdated.listen((_) {
      if (mounted) _fetchData(isSilent: true);
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData({bool isSilent = false}) async {
    if (!mounted) return;
    if (!isSilent) setState(() => _isLoading = true);
    
    try {
      // ✅ APPEL OPTIMISTE (Fusionne Local + Serveur)
      final res = await _api.getTiersWithQueue(_activeTab, _searchController.text);
      
      if (mounted) {
        setState(() {
          _list = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _fetchData(isSilent: true);
    });
  }

  void _openDetails(Map<String, dynamic> item) {
    Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => _activeTab == 'clients' 
        ? ClientDetailsPage(summary: item)
        : SupplierDetailsPage(summary: item)
      )
    ).then((_) => _fetchData(isSilent: true));
  }

  void _openAddModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddTierModal(
        type: _activeTab == 'clients' ? 'client' : 'supplier', 
        api: _api,
        onSuccess: () {
           // Plus besoin de recharger manuellement ici, le stream le fait
           // Mais on peut le garder par sécurité
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF2F2F7);
    final isClient = _activeTab == 'clients';

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- HEADER ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("GESTION", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent, letterSpacing: 1.5)),
                          Text(
                            "Partenaires", 
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _openAddModal,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient, 
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))
                            ]
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // --- ONGLETS ---
                  Container(
                    height: 50,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]
                    ),
                    child: Row(
                      children: [
                        _buildSegment("Clients", "clients", isDark),
                        _buildSegment("Fournisseurs", "suppliers", isDark),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),

                  // --- RECHERCHE ---
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!)
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        hintText: "Rechercher un ${isClient ? 'client' : 'fournisseur'}...",
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 13),
                        suffixIcon: _searchController.text.isNotEmpty 
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _fetchData(isSilent: true);
                              },
                            )
                          : null
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- LISTE ---
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) 
                : _list.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_off_outlined, size: 60, color: Colors.grey.withOpacity(0.3)),
                          const SizedBox(height: 10),
                          Text(
                            "Aucun ${isClient ? 'client' : 'fournisseur'} trouvé",
                            style: const TextStyle(color: Colors.grey),
                          )
                        ],
                      ),
                    )
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), 
                    itemCount: _list.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (ctx, i) {
                      final item = _list[i];
                      final balance = double.tryParse(item['balance']?.toString() ?? '0') ?? 0;
                      final isDebt = balance > 0;
                      final name = item['name'] ?? 'Inconnu';
                      final isLocal = item['is_local'] == true;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]
                        ),
                        child: ListTile(
                          onTap: () => _openDetails(item),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                          leading: Container(
                            width: 50, height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: isClient 
                                ? LinearGradient(colors: [Colors.blue, Colors.blueAccent.shade700])
                                : LinearGradient(colors: [Colors.orange, Colors.orangeAccent.shade700]),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: (isClient ? Colors.blue : Colors.orange).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))]
                            ),
                            child: isLocal 
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                                ),
                          ),
                          title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                          subtitle: Text(item['phone'] ?? 'Pas de numéro', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0).format(balance),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  color: isDebt ? Colors.redAccent : Colors.green, 
                                  fontSize: 15
                                ),
                              ),
                              Text(isDebt ? "Dette" : "Solde", style: const TextStyle(color: Colors.grey, fontSize: 10)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(String label, String value, bool isDark) {
    final isActive = _activeTab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeTab = value;
            _isLoading = true; 
          });
          _searchController.clear();
          _fetchData();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// MODALE D'AJOUT OPTIMISTE
// ==============================================================================

class AddTierModal extends StatefulWidget {
  final String type; // 'client' ou 'supplier'
  final ApiService api;
  final VoidCallback onSuccess;

  const AddTierModal({super.key, required this.type, required this.api, required this.onSuccess});

  @override
  State<AddTierModal> createState() => _AddTierModalState();
}

class _AddTierModalState extends State<AddTierModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController(); 

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Pas de loader, c'est instantané !
    
    try {
      final tierData = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
      };

      // ✅ APPEL OPTIMISTE
      await widget.api.createTierOptimistic(widget.type, tierData);

      if (mounted) {
        Navigator.pop(context); 
        widget.onSuccess(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajouté ! (Sync en cours...)"), backgroundColor: Colors.green));
      }
    } catch (e) {
        // Gérer erreur
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isClient = widget.type == 'client';
    final title = isClient ? "Nouveau Client" : "Nouveau Fournisseur";

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 20),
              Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 20),

              _buildInput("Nom complet", Icons.person, _nameController, isDark, true),
              const SizedBox(height: 15),
              
              _buildInput("Téléphone", Icons.phone, _phoneController, isDark, false, TextInputType.phone),
              const SizedBox(height: 15),

              _buildInput("Adresse (Optionnel)", Icons.location_on, _addressController, isDark, false),
              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                    shadowColor: AppColors.primary.withOpacity(0.4),
                  ),
                  child: const Text("ENREGISTRER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(String label, IconData icon, TextEditingController controller, bool isDark, bool required, [TextInputType type = TextInputType.text]) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      validator: required ? (v) => (v == null || v.isEmpty) ? "Champ requis" : null : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      ),
    );
  }
}