import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'labels.dart';

/// Preferencias de impresión del DISPOSITIVO (cada caja puede tener su impresora).
class PrintSettings {
  const PrintSettings({this.paperMm = 80, this.labelFormat = LabelFormat.a4Sheet, this.autoPrint = false});
  final int paperMm;
  final LabelFormat labelFormat;

  /// Imprimir el ticket apenas se cobra (sin tocar "Imprimir").
  final bool autoPrint;

  PrintSettings copyWith({int? paperMm, LabelFormat? labelFormat, bool? autoPrint}) =>
      PrintSettings(paperMm: paperMm ?? this.paperMm, labelFormat: labelFormat ?? this.labelFormat, autoPrint: autoPrint ?? this.autoPrint);
}

class PrintSettingsController extends Notifier<PrintSettings> {
  @override
  PrintSettings build() {
    _load();
    return const PrintSettings();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = PrintSettings(
      paperMm: p.getInt('print.paperMm') ?? 80,
      labelFormat: LabelFormat.values.where((f) => f.name == p.getString('print.labelFormat')).firstOrNull ?? LabelFormat.a4Sheet,
      autoPrint: p.getBool('print.autoPrint') ?? false,
    );
  }

  Future<void> update(PrintSettings s) async {
    state = s;
    final p = await SharedPreferences.getInstance();
    await p.setInt('print.paperMm', s.paperMm);
    await p.setString('print.labelFormat', s.labelFormat.name);
    await p.setBool('print.autoPrint', s.autoPrint);
  }
}

final printSettingsProvider = NotifierProvider<PrintSettingsController, PrintSettings>(PrintSettingsController.new);
