import 'package:flutter_test/flutter_test.dart';
import 'package:percha_app/features/reports/data/reports_api.dart';

void main() {
  final now = DateTime(2026, 10, 25, 23, 30);

  test('los períodos se calculan en fechas locales e inclusivas', () {
    expect(PeriodPreset.today.resolve(now), (from: '2026-10-25', to: '2026-10-25'));
    expect(PeriodPreset.week.resolve(now), (from: '2026-10-19', to: '2026-10-25'));
    expect(PeriodPreset.month.resolve(now), (from: '2026-09-26', to: '2026-10-25'));
    expect(PeriodPreset.thisMonth.resolve(now), (from: '2026-10-01', to: '2026-10-25'));
  });
}
