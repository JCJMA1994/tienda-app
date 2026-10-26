import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reglas de arquitectura de la app, verificadas en cada `flutter test`.
List<File> _dart(String dir) => Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();
List<String> _imports(File f) => RegExp(r"^import '([^']+)';", multiLine: true).allMatches(f.readAsStringSync()).map((m) => m.group(1)!).toList();

void main() {
  final files = _dart('lib');

  test('las pantallas no hablan HTTP directamente (usan la capa data/ o un controlador)', () {
    final screens = files.where((f) => f.path.contains('/presentation/') || RegExp(r'_pages?\.dart$').hasMatch(f.path));
    final offenders = [
      for (final f in screens)
        if (_imports(f).any((i) => i.endsWith('network/api_client.dart') || i.startsWith('package:dio')) || f.readAsStringSync().contains('apiClientProvider')) f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('la lógica pura no depende de Flutter (se prueba sin widgets)', () {
    const pure = [
      'lib/core/money.dart',
      'lib/core/catalogs.dart',
      'lib/core/forms/validators.dart',
      'lib/features/einvoice/domain/customer_rules.dart',
      'lib/features/printing/ticket.dart',
      'lib/features/printing/labels.dart',
    ];
    final offenders = [
      for (final p in pure)
        for (final i in _imports(File(p)))
          if (i.startsWith('package:flutter/') || i.startsWith('package:flutter_riverpod')) '$p → $i',
    ];
    expect(offenders, isEmpty);
  });

  test('las capas apuntan hacia adentro: domain ← application ← presentation', () {
    final offenders = <String>[];
    for (final f in files) {
      final path = f.path;
      final layer = path.contains('/domain/') ? 'domain' : path.contains('/application/') ? 'application' : null;
      if (layer == null) continue;
      for (final i in _imports(f)) {
        if (i.contains('/presentation/')) offenders.add('$path → $i');
        if (layer == 'domain' && (i.contains('/data/') || i.contains('/application/') || i.contains('package:flutter'))) offenders.add('$path → $i');
      }
    }
    expect(offenders, isEmpty);
  });

  test('ningún archivo supera las 500 líneas (se parte en widgets o en part files)', () {
    final big = [
      for (final f in files)
        if (f.readAsLinesSync().length > 500) '${f.path} (${f.readAsLinesSync().length})',
    ];
    expect(big, isEmpty);
  });
}
