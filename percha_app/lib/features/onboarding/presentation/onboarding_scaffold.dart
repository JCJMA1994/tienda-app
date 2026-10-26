import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/percha_widgets.dart';

/// Estructura común de los pasos: progreso, "Después", título y acción fija abajo.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.action,
    required this.onSkip,
    this.onBack,
  });

  final int step;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget action;
  final VoidCallback onSkip;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: onBack == null ? null : IconButton(tooltip: 'Volver', icon: const Icon(Icons.arrow_back), onPressed: onBack),
        title: Text('Paso $step de 5', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
        centerTitle: true,
        actions: [TextButton(onPressed: onSkip, child: const Text('Después'))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StepsBar(current: step),
                        const SizedBox(height: PerchaSpace.xl),
                        Text(title, style: text.headlineMedium),
                        const SizedBox(height: PerchaSpace.sm),
                        Text(subtitle, style: text.bodyMedium?.copyWith(color: PerchaColors.muted)),
                        const SizedBox(height: PerchaSpace.xl),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: action),
            ),
          ],
        ),
      ),
    );
  }
}
