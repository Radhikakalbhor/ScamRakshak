import 'package:flutter/material.dart';

import 'tokens.dart';

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

/// Flat pastel card: large radius, no shadow. [color] must be one of the pastel tokens
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

/// Small dark circular badge holding an icon (top-left of cards).
class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color background;
  final Color foreground;
  const IconBadge(this.icon, {super.key, this.size = kDsTouch, this.background = DsColors.ink, this.foreground = DsColors.onDark});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.46, color: foreground),
      );
}

/// Circular outline arrow (top-right of cards). Decorative inside a tappable card; pass [onTap]
/// and [semanticLabel] to make it a standalone 44 x 44 button.
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
        Text(label, style: DsType.label.copyWith(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
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

/// Screen header: brand badge + name on the left, actions (44 x 44) on the right, then an optional
/// small muted greeting line and a very large light title.
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
            Expanded(child: Text(brand!, style: DsType.title.copyWith(fontWeight: FontWeight.w600), maxLines: 1))
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
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  const PrimaryButton({super.key, required this.label, this.icon, this.onPressed, this.filled = true});

  @override
  Widget build(BuildContext context) {
    final fg = filled ? DsColors.onDark : DsColors.ink;
    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(DsRadius.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.xl),
        decoration: BoxDecoration(
          color: filled ? DsColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(DsRadius.pill),
          border: Border.all(color: DsColors.ink, width: 1.2),
        ),
        child: ExcludeSemantics(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: DsSpace.s)],
            Flexible(child: Text(label, style: DsType.label.copyWith(color: fg, fontSize: 16), textAlign: TextAlign.center)),
          ]),
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
