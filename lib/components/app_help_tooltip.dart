import 'package:flutter/material.dart';

/// A compact, accessible help affordance for static UI explanations.
///
/// [TooltipTriggerMode.tap] gives touch users a single-tap interaction while
/// Flutter still shows the tooltip on mouse hover for desktop users.
class AppHelpTooltip extends StatefulWidget {
  const AppHelpTooltip({super.key, required this.message});

  final String message;

  @override
  State<AppHelpTooltip> createState() => _AppHelpTooltipState();
}

class _AppHelpTooltipState extends State<AppHelpTooltip> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: _tooltipKey,
      message: widget.message,
      triggerMode: TooltipTriggerMode.tap,
      child: IconButton(
        onPressed: () => _tooltipKey.currentState?.ensureTooltipVisible(),
        icon: const Icon(Icons.help_outline),
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    );
  }
}
