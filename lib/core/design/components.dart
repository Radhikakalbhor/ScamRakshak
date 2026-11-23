import 'package:flutter/material.dart';

import 'tokens.dart';

// ---------------------------------------------------------------------------------------------
// Interaction
// ---------------------------------------------------------------------------------------------

/// Gentle press feedback used by every tappable surface: scales to [DsMotion.pressScale].
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool button;
  final BorderRadius borderRadius;
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.button = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(DsRadius.card)),
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      container: true,
      button: widget.button && enabled,
      label: widget.semanticLabel,
      child: AnimatedScale(
        scale: _down ? DsMotion.pressScale : 1,
        duration: DsMotion.fast,
        curve: DsMotion.curve,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: enabled ? _set : null,
            borderRadius: widget.borderRadius,
            splashFactory: NoSplash.splashFactory,
            highlightColor: DsColors.ink.withValues(alpha: 0.04),
            hoverColor: DsColors.ink.withValues(alpha: 0.03),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------------------------

/// Flat pastel card: large radius, no shadow. [color] must be a pastel token
/// (or [DsColors.alert] for the single alert card).
class PastelCard extends StatelessWidget {
  final Color color;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;
  const PastelCard({
    super.key,
    required this.color,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(DsSpace.xl),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final card = DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(DsRadius.card)),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, semanticLabel: semanticLabel, child: card);
  }
}

/// White rounded panel on the off-white page (hairline border, no shadow). Tappable with [onTap].
class SurfacePanel extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final Color color;
  const SurfacePanel({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(DsSpace.xl),
    this.color = DsColors.surface,
  });

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(DsRadius.card),
        border: Border.all(color: DsColors.line),
      ),
      child: child,
    );
    if (onTap == null) return panel;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: semanticLabel == null ? panel : ExcludeSemantics(child: panel),
    );
  }
}

/// Feature entry card: icon badge + arrow, title and short description on a pastel.
class FeatureCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const FeatureCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => PastelCard(
        color: color,
        onTap: onTap,
        padding: const EdgeInsets.all(DsSpace.l),
        semanticLabel: '$title. $subtitle',
        child: ExcludeSemantics(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [IconBadge(icon), const Spacer(), const ArrowButton()]),
            const SizedBox(height: DsSpace.xxl),
            Text(title, style: DsType.cardTitle.copyWith(fontSize: 20)),
            const SizedBox(height: DsSpace.xs),
            Text(subtitle, style: DsType.small),
          ]),
        ),
      );
}

/// Two equal-height children side by side (feature grid rows).
class PairRow extends StatelessWidget {
  final Widget left;
  final Widget right;
  const PairRow({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: left),
          const SizedBox(width: DsSpace.m),
          Expanded(child: right),
        ]),
      );
}

// ---------------------------------------------------------------------------------------------
// Small parts
// ---------------------------------------------------------------------------------------------

/// Small dark circular badge holding an icon (top-left of cards).
class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color background;
  final Color foreground;
  const IconBadge(this.icon,
      {super.key, this.size = kDsTouch, this.background = DsColors.ink, this.foreground = DsColors.onDark});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.46, color: foreground),
      );
}

/// Circular outline arrow (top-right of cards). Decorative inside a tappable card; pass [onTap]
/// and [semanticLabel] to make it a standalone 48 x 48 icon button (e.g. the bell).
class ArrowButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color color;
  final IconData icon;
  const ArrowButton({
    super.key,
    this.onTap,
    this.semanticLabel,
    this.color = DsColors.ink,
    this.icon = Icons.north_east_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: kDsTouch,
      height: kDsTouch,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.2)),
      child: Icon(icon, size: 20, color: color),
    );
    if (onTap == null) return ExcludeSemantics(child: circle);
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      borderRadius: BorderRadius.circular(DsRadius.pill),
      child: circle,
    );
  }
}

/// Soft pill chip. [selected] fills it with the brand teal.
class PillChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final Color background;
  final Color? foreground;
  final String? semanticLabel;
  const PillChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.background = DsColors.surface,
    this.foreground,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? (selected ? DsColors.onDark : DsColors.ink);
    final chip = AnimatedContainer(
      duration: DsMotion.normal,
      curve: DsMotion.curve,
      constraints: const BoxConstraints(minHeight: kDsTouch, minWidth: kDsTouch),
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.l),
      decoration: BoxDecoration(
        color: selected ? DsColors.brand : background,
        borderRadius: BorderRadius.circular(DsRadius.pill),
        border: Border.all(color: selected ? DsColors.brand : DsColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: DsSpace.s)],
        Flexible(child: Text(label, style: DsType.label.copyWith(color: fg))),
      ]),
    );
    if (onTap == null) return chip;
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        borderRadius: BorderRadius.circular(DsRadius.pill),
        // With a semanticLabel the visible text is not read twice ("English", not "English EN").
        child: semanticLabel == null ? chip : ExcludeSemantics(child: chip),
      ),
    );
  }
}

/// Screen header: brand badge + name on the left, actions (48 x 48) on the right, then an optional
/// small muted greeting line and a very large title.
class ScreenHeader extends StatelessWidget {
  final Widget? leading;
  final String? brand;
  final List<Widget> actions;
  final String? greeting;
  final String? title;
  const ScreenHeader({super.key, this.leading, this.brand, this.actions = const [], this.greeting, this.title});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: DsSpace.m)],
          if (brand != null)
            Expanded(child: Text(brand!, style: DsType.title.copyWith(fontSize: 18), maxLines: 1))
          else
            const Spacer(),
          for (final a in actions) Padding(padding: const EdgeInsets.only(left: DsSpace.s), child: a),
        ]),
        if (greeting != null) ...[
          const SizedBox(height: DsSpace.xxl),
          Text(greeting!, style: DsType.greeting),
        ],
        if (title != null) ...[
          const SizedBox(height: DsSpace.xs),
          Text(title!, style: DsType.display),
        ],
      ]);
}

/// Full-width pill button. [filled]: ink background (primary); otherwise outlined.
/// [color] overrides the ink (e.g. [DsColors.alert] for a destructive / report action).
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  final Color color;
  final bool busy;
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.filled = true,
    this.color = DsColors.ink,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final base = filled ? color : Colors.transparent;
    final fg = filled ? DsColors.onDark : color;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        semanticLabel: label,
        borderRadius: BorderRadius.circular(DsRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.xl, vertical: DsSpace.s),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(DsRadius.pill),
            border: Border.all(color: color, width: 1.2),
          ),
          child: ExcludeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else if (icon != null)
                Icon(icon, size: 20, color: fg),
              if (busy || icon != null) const SizedBox(width: DsSpace.s),
              Flexible(child: Text(label, style: DsType.label.copyWith(color: fg), textAlign: TextAlign.center)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Thin rounded progress bar; [value] 0..1.
class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final String? semanticLabel;
  const ProgressBar({super.key, required this.value, this.color = DsColors.ink, this.semanticLabel});

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        value: '${(value.clamp(0, 1) * 100).round()}%',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DsRadius.pill),
          child: SizedBox(
            height: 8,
            child: Stack(fit: StackFit.expand, children: [
              const ColoredBox(color: DsColors.track),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
                duration: DsMotion.normal,
                curve: DsMotion.curve,
                builder: (_, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: ColoredBox(color: color),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------------------------
// Inputs, lists, tabs
// ---------------------------------------------------------------------------------------------

/// Rounded text input (white fill, hairline border, brand focus ring).
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  const AppTextField({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        autofocus: autofocus,
        style: DsType.body.copyWith(fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          labelText: label,
          hintStyle: DsType.body.copyWith(color: DsColors.muted),
          contentPadding: const EdgeInsets.symmetric(horizontal: DsSpace.l, vertical: DsSpace.m),
        ),
      );
}

/// List row: optional leading badge, title, subtitle, optional trailing widget; 48 dp minimum.
class DsListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;
  const DsListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: kDsTouch + DsSpace.l),
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.l, vertical: DsSpace.m),
      decoration: BoxDecoration(
        color: color ?? DsColors.surface,
        borderRadius: BorderRadius.circular(DsRadius.tile),
        border: Border.all(color: DsColors.line),
      ),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: DsSpace.m)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: DsType.title),
            if (subtitle != null) ...[const SizedBox(height: DsSpace.xxs), Text(subtitle!, style: DsType.small)],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: DsSpace.s), trailing!],
      ]),
    );
    if (onTap == null) return row;
    return Pressable(onTap: onTap, borderRadius: BorderRadius.circular(DsRadius.tile), child: row);
  }
}

/// Segmented pill tabs (scrolls horizontally when they do not fit).
class DsTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const DsTabs({super.key, required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : DsSpace.s),
              child: PillChip(label: labels[i], selected: i == selected, onTap: () => onSelect(i)),
            ),
        ]),
      );
}

// ---------------------------------------------------------------------------------------------
// Feedback: verdicts, dialogs, toasts, empty and loading states
// ---------------------------------------------------------------------------------------------

/// Risk level of a verdict; maps to the semantic colors.
enum DsVerdict { danger, caution, safe }

Color verdictColor(DsVerdict v) => switch (v) {
      DsVerdict.danger => DsColors.alert,
      DsVerdict.caution => DsColors.caution,
      DsVerdict.safe => DsColors.safe,
    };

/// Big verdict box (scam / medium / safe): solid semantic color, white text, icon badge.
class VerdictBanner extends StatelessWidget {
  final DsVerdict verdict;
  final IconData icon;
  final String title;
  final List<String> lines;
  const VerdictBanner({super.key, required this.verdict, required this.icon, required this.title, this.lines = const []});

  @override
  Widget build(BuildContext context) => PastelCard(
        color: verdictColor(verdict),
        child: Row(children: [
          IconBadge(icon, background: DsColors.onDark, foreground: verdictColor(verdict)),
          const SizedBox(width: DsSpace.l),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: DsType.cardTitle.copyWith(color: DsColors.onDark)),
              for (final l in lines) Text(l, style: DsType.body.copyWith(color: DsColors.onDark)),
            ]),
          ),
        ]),
      );
}

/// Shows a rounded dialog in the design style. Returns what [actions] pop with.
Future<T?> showDsDialog<T>(
  BuildContext context, {
  required String title,
  Widget? content,
  required List<Widget> Function(BuildContext dialogContext) actions,
}) =>
    showDialog<T>(
      context: context,
      barrierColor: DsColors.scrim,
      builder: (ctx) => Dialog(
        backgroundColor: DsColors.page,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(DsSpace.xl),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DsRadius.card)),
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.xl),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: DsType.cardTitle),
            if (content != null) ...[const SizedBox(height: DsSpace.m), content],
            const SizedBox(height: DsSpace.xl),
            ...[
              for (final (i, a) in actions(ctx).indexed) ...[if (i > 0) const SizedBox(height: DsSpace.s), a],
            ],
          ]),
        ),
      ),
    );

/// Floating rounded toast (theme snackBarTheme). Returns the controller like showSnackBar.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showDsToast(BuildContext context, String message,
        {Duration duration = const Duration(seconds: 4)}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: duration));

/// Empty state: soft pastel badge, title, optional message and action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color color;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.color = DsColors.powder,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(DsSpace.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          IconBadge(icon, size: 64, background: color, foreground: DsColors.ink),
          const SizedBox(height: DsSpace.l),
          Text(title, style: DsType.section, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: DsSpace.s),
            Text(message!, style: DsType.small, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: DsSpace.l), action!],
        ]),
      );
}

/// Loading state: small ink spinner with an optional caption.
class LoadingState extends StatelessWidget {
  final String? message;
  const LoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.l),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
            if (message != null) ...[
              const SizedBox(height: DsSpace.m),
              Text(message!, style: DsType.small, textAlign: TextAlign.center),
            ],
          ]),
        ),
      );
}
