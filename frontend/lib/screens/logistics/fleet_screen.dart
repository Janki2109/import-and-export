import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/platform.dart';
import '../../services/platform_service.dart';

class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key});
  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  final _fleetService = FleetService();
  late Future<List<FleetVehicle>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fleetService.listMine();
  }

  void _refresh() => setState(() => _future = _fleetService.listMine());

  Future<void> _addVehicle() async {
    final typeCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    final capacityCtrl = TextEditingController();
    final routeCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add Vehicle', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Vehicle Type (e.g. truck, cargo_plane)')),
            const SizedBox(height: 12),
            TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Registration Number')),
            const SizedBox(height: 12),
            TextField(controller: capacityCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity (kg, optional)')),
            const SizedBox(height: 12),
            TextField(controller: routeCtrl, decoration: const InputDecoration(labelText: 'Service Route (e.g. Mumbai -> Dubai)')),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add Vehicle')),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
    if (confirmed != true || typeCtrl.text.trim().isEmpty || regCtrl.text.trim().isEmpty) return;

    try {
      await _fleetService.create(
        vehicleType: typeCtrl.text.trim(),
        registrationNumber: regCtrl.text.trim(),
        capacityKg: double.tryParse(capacityCtrl.text),
        serviceRoute: routeCtrl.text.trim().isEmpty ? null : routeCtrl.text.trim(),
      );
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Fleet')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addVehicle, icon: const Icon(Icons.add), label: const Text('Add Vehicle')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<FleetVehicle>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final vehicles = snapshot.data ?? [];
            if (vehicles.isEmpty) {
              return const Center(child: Text('No vehicles added yet.', style: TextStyle(color: AppColors.textSecondary)));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: vehicles.length,
              itemBuilder: (context, i) {
                final v = vehicles[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.local_shipping_outlined, color: AppColors.primary),
                    title: Text('${v.vehicleType} · ${v.registrationNumber}'),
                    subtitle: Text([
                      if (v.capacityKg != null) '${v.capacityKg!.toStringAsFixed(0)} kg',
                      if (v.serviceRoute != null) v.serviceRoute!,
                    ].join(' · ')),
                    trailing: Chip(label: Text(v.status), backgroundColor: AppColors.success.withValues(alpha: 0.1)),
                    onLongPress: () async {
                      await _fleetService.delete(v.id);
                      _refresh();
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
