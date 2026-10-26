import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Apariencia elegida por el usuario: sistema (por defecto), clara u oscura.
/// Se guarda en el dispositivo (no es un dato sensible, por eso no va en secure storage).
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'percha.themeMode';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = ThemeMode.values.where((m) => m.name == prefs.getString(_key)).firstOrNull;
    if (saved != null) state = saved;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
