import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reference.dart';
import '../../services/admin_service.dart';
import '../../services/search_service.dart';

class AdminReferenceDataScreen extends StatefulWidget {
  const AdminReferenceDataScreen({super.key});
  @override
  State<AdminReferenceDataScreen> createState() => _AdminReferenceDataScreenState();
}

class _AdminReferenceDataScreenState extends State<AdminReferenceDataScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _adminService = AdminService();
  final _searchService = SearchService();
  Future<List<Country>>? _countriesFuture;
  Future<List<HSCode>>? _hsCodesFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _countriesFuture = _searchService.searchCountries('');
    _hsCodesFuture = _searchService.searchHSCodes('');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshCountries() => setState(() => _countriesFuture = _searchService.searchCountries(''));
  void _refreshHSCodes() => setState(() => _hsCodesFuture = _searchService.searchHSCodes(''));

  Future<void> _addCountry() async {
    final nameCtrl = TextEditingController();
    final iso2Ctrl = TextEditingController();
    final iso3Ctrl = TextEditingController();
    final regionCtrl = TextEditingController();
    bool restricted = false;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add Country', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: iso2Ctrl, decoration: const InputDecoration(labelText: 'ISO2'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: iso3Ctrl, decoration: const InputDecoration(labelText: 'ISO3'))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: regionCtrl, decoration: const InputDecoration(labelText: 'Region')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Restricted / Sanctioned'),
                value: restricted,
                onChanged: (v) => setSheetState(() => restricted = v),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await _adminService.createCountry(
        name: nameCtrl.text.trim(), iso2: iso2Ctrl.text.trim().toUpperCase(), iso3: iso3Ctrl.text.trim().toUpperCase(),
        region: regionCtrl.text.trim(), restricted: restricted,
      );
      _refreshCountries();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _addHSCode() async {
    final codeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final chapterCtrl = TextEditingController();
    final bcdCtrl = TextEditingController(text: '10');
    final igstCtrl = TextEditingController(text: '18');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add HS Code', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Code (e.g. 8517.13)')),
            const SizedBox(height: 12),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 12),
            TextField(controller: chapterCtrl, decoration: const InputDecoration(labelText: 'Chapter (e.g. 85)')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: bcdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'BCD %'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: igstCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'IGST %'))),
            ]),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
    if (confirmed != true || codeCtrl.text.trim().isEmpty) return;

    final bcd = double.tryParse(bcdCtrl.text.trim());
    final igst = double.tryParse(igstCtrl.text.trim());
    if (bcd == null || bcd < 0 || bcd > 100 || igst == null || igst < 0 || igst > 100) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('BCD % and IGST % must be numeric values between 0 and 100.'), backgroundColor: AppColors.error),
        );
      }
      return;
    }

    try {
      await _adminService.createHSCode(
        code: codeCtrl.text.trim(), description: descCtrl.text.trim(), chapter: chapterCtrl.text.trim(),
        bcd: bcd, igst: igst,
      );
      if (mounted) _refreshHSCodes();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Countries & HS Codes'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Countries'), Tab(text: 'HS Codes')]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _tabController.index == 0 ? _addCountry() : _addHSCode(),
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FutureBuilder<List<Country>>(
            future: _countriesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final countries = snapshot.data ?? [];
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: countries.length,
                itemBuilder: (context, i) {
                  final c = countries[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(c.name),
                      subtitle: Text('${c.iso2} · ${c.region}'),
                      trailing: c.isRestricted ? const Icon(Icons.block, color: AppColors.error) : null,
                    ),
                  );
                },
              );
            },
          ),
          FutureBuilder<List<HSCode>>(
            future: _hsCodesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final codes = snapshot.data ?? [];
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: codes.length,
                itemBuilder: (context, i) {
                  final h = codes[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(h.code),
                      subtitle: Text(h.description),
                      trailing: Text('BCD ${h.basicCustomsDutyPercent.toStringAsFixed(0)}%'),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
