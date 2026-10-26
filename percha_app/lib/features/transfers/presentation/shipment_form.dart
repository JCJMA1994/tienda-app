import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/app_form.dart';
import '../../../core/forms/validators.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../lookup/lookup_api.dart';

/// Datos del traslado para la guía de remisión. Va dentro del Form de la transferencia,
/// así se valida junto con todo lo demás.
class ShipmentController {
  String mode = 'private';
  bool lightVehicle = true;
  final plate = TextEditingController();
  final driverDni = TextEditingController();
  final driverFirst = TextEditingController();
  final driverLast = TextEditingController();
  final license = TextEditingController();
  final carrierRuc = TextEditingController();
  final carrierName = TextEditingController();
  final weight = TextEditingController();
  final packages = TextEditingController(text: '1');

  void dispose() {
    for (final c in [plate, driverDni, driverFirst, driverLast, license, carrierRuc, carrierName, weight, packages]) {
      c.dispose();
    }
  }

  Map<String, Object?> toJson() => {
        'mode': mode,
        'lightVehicle': lightVehicle,
        'weightKg': double.parse(weight.text.replaceAll(',', '.')),
        'packages': int.parse(packages.text),
        if (mode == 'private') ...{
          'vehiclePlate': plate.text.trim(),
          'driver': {
            'dni': driverDni.text.trim(),
            'firstName': driverFirst.text.trim(),
            'lastName': driverLast.text.trim(),
            if (license.text.trim().isNotEmpty) 'license': license.text.trim(),
          },
        },
        if (mode == 'public') 'carrier': {'ruc': carrierRuc.text.trim(), 'name': carrierName.text.trim()},
      };
}

class ShipmentForm extends ConsumerStatefulWidget {
  const ShipmentForm({super.key, required this.controller, required this.units});
  final ShipmentController controller;
  final int units;

  @override
  ConsumerState<ShipmentForm> createState() => _ShipmentFormState();
}

class _ShipmentFormState extends ConsumerState<ShipmentForm> {
  ShipmentController get c => widget.controller;

  @override
  void didUpdateWidget(covariant ShipmentForm old) {
    super.didUpdateWidget(old);
    // Peso sugerido: ~0,3 kg por prenda (editable; debe ser el real aproximado).
    if (c.weight.text.isEmpty && widget.units > 0) c.weight.text = (widget.units * 0.3).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (c.weight.text.isEmpty && widget.units > 0) c.weight.text = (widget.units * 0.3).toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.local_shipping_outlined, color: PerchaColors.accentInk),
            const SizedBox(width: 8),
            Expanded(child: Text('Guía de remisión', style: text.titleMedium)),
          ],),
          Text('SUNAT la exige para mover mercadería entre tus tiendas. Se emite al enviar.', style: text.bodySmall),
          const SizedBox(height: PerchaSpace.md),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'private', label: Text('Auto propio / taxi')),
              ButtonSegment(value: 'public', label: Text('Empresa de transporte')),
            ],
            selected: {c.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => c.mode = s.first),
          ),
          const SizedBox(height: PerchaSpace.md),
          if (c.mode == 'private') ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: c.lightVehicle,
              onChanged: (v) => setState(() => c.lightVehicle = v),
              title: const Text('Vehículo liviano (auto, taxi o moto)'),
              subtitle: const Text('No pide brevete'),
            ),
            AppTextField(controller: c.plate, label: 'Placa', hint: 'ABC-123', kind: FieldKind.upper, maxLength: 8, validator: (v) => RegExp(r'^[A-Z0-9]{5,8}$').hasMatch((v ?? '').toUpperCase().replaceAll(RegExp(r'[\s-]'), '')) ? null : 'Placa inválida'),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: c.driverDni, label: 'DNI de quien conduce', kind: FieldKind.dni, validator: V.dni()),
            const SizedBox(height: PerchaSpace.md),
            Row(children: [
              Expanded(child: AppTextField(controller: c.driverFirst, label: 'Nombres', kind: FieldKind.name, validator: V.minLength(2, 'Requerido'))),
              const SizedBox(width: 8),
              Expanded(child: AppTextField(controller: c.driverLast, label: 'Apellidos', kind: FieldKind.name, validator: V.minLength(2, 'Requerido'))),
            ],),
            if (!c.lightVehicle) ...[
              const SizedBox(height: PerchaSpace.md),
              AppTextField(controller: c.license, label: 'Brevete', kind: FieldKind.upper, maxLength: 15, validator: V.minLength(5, 'Ingresa el brevete')),
            ],
          ] else ...[
            AppTextField(
              controller: c.carrierRuc,
              label: 'RUC de la empresa de transporte',
              kind: FieldKind.ruc,
              validator: V.ruc(),
              suffix: IconButton(
                tooltip: 'Buscar en SUNAT',
                icon: const Icon(Icons.search),
                onPressed: () async {
                  try {
                    final r = await ref.read(lookupApiProvider).ruc(c.carrierRuc.text.trim());
                    setState(() => c.carrierName.text = r.name);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
                  }
                },
              ),
            ),
            const SizedBox(height: PerchaSpace.md),
            AppTextField(controller: c.carrierName, label: 'Razón social', validator: V.minLength(2, 'Requerido')),
          ],
          const SizedBox(height: PerchaSpace.md),
          Row(children: [
            Expanded(
              child: AppTextField(
                controller: c.weight,
                label: 'Peso total (kg)',
                kind: FieldKind.money,
                prefixText: '',
                validator: (v) {
                  final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                  return n == null || n <= 0 ? 'Ingresa el peso' : null;
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: AppTextField(controller: c.packages, label: 'Bultos', kind: FieldKind.integer, validator: V.intRange(min: 1, max: 1000), last: true)),
          ],),
        ],),
      ),
    );
  }
}
