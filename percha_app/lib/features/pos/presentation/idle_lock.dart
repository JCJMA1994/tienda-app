import '../../../core/widgets/action_runner.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';
import '../../auth/application/session_controller.dart';

/// Bloqueo por inactividad del POS (seguridad en tablet compartida): si nadie toca la
/// pantalla durante [timeout], se cubre con una pantalla que pide PIN. Quien ingresa su PIN
/// queda como vendedor activo, así ninguna venta se registra a nombre de otra persona.
/// El ticket en curso se conserva.
class IdleLock extends ConsumerStatefulWidget {
  const IdleLock({super.key, required this.branchId, required this.child, this.timeout = const Duration(minutes: 3)});
  final String branchId;
  final Widget child;
  final Duration timeout;

  @override
  ConsumerState<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends ConsumerState<IdleLock> with WidgetsBindingObserver {
  Timer? _timer;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Si la app pasa a segundo plano, al volver se pide PIN.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _lock();
  }

  void _reset() {
    _timer?.cancel();
    if (!_locked) _timer = Timer(widget.timeout, _lock);
  }

  void _lock() {
    if (!mounted || _locked) return;
    _timer?.cancel();
    setState(() => _locked = true);
  }

  void _unlocked() {
    setState(() => _locked = false);
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reset(),
      child: Stack(
        children: [
          // Debajo del bloqueo nada responde a toques ni a lectores de pantalla.
          ExcludeSemantics(excluding: _locked, child: AbsorbPointer(absorbing: _locked, child: widget.child)),
          if (_locked) Positioned.fill(child: _LockScreen(branchId: widget.branchId, onUnlocked: _unlocked)),
        ],
      ),
    );
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen({required this.branchId, required this.onUnlocked});
  final String branchId;
  final VoidCallback onUnlocked;

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> with ActionRunner {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !RegExp(r'^\d{4,6}$').hasMatch(_pin.text)) return;
    final me = await runAction(() => ref.read(sessionProvider.notifier).switchByPin(branchId: widget.branchId, pin: _pin.text));
    if (me != null) {
      widget.onUnlocked();
    } else {
      _pin.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PerchaColors.palette;
    return PopScope(
      canPop: false,
      child: Material(
        color: c.ground.withValues(alpha: 0.97),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(child: PerchaLogo(size: 48, showName: false)),
                    const SizedBox(height: PerchaSpace.xl),
                    Text('POS bloqueado', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: PerchaSpace.sm),
                    Text('Ingresa tu PIN para seguir vendiendo. El ticket en curso se conserva.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: PerchaSpace.xl),
                    TextField(
                      controller: _pin,
                      autofocus: true,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: PerchaType.display, letterSpacing: 12, fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(labelText: 'PIN', counterText: ''),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (error != null) ...[const SizedBox(height: PerchaSpace.md), ErrorBanner(error!)],
                    const SizedBox(height: PerchaSpace.lg),
                    BusyButton(label: 'Desbloquear', busy: busy, onPressed: _submit),
                    const SizedBox(height: PerchaSpace.sm),
                    TextButton(onPressed: () => context.go('/home'), child: const Text('Salir del POS')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
