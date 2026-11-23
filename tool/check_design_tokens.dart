// Flags hard-coded colours, fonts, font sizes/weights, radii and spacing in lib/.
//
//   dart run tool/check_design_tokens.dart        (exit code 1 when something is found)
//
// Also run by test/core/design_lint_test.dart, so `flutter test` fails on a violation.
// Only lib/core/design/tokens.dart and lib/core/theme.dart may hold raw values.
// A line that genuinely needs a raw value can end with `// ds-ignore: <reason>`.
import 'dart:io';

class DesignRule {
  final String name;
  final RegExp pattern;
  final String fix;
  const DesignRule(this.name, this.pattern, this.fix);
}

class DesignViolation {
  final String path;
  final int line;
  final String rule;
  final String fix;
  final String source;
  const DesignViolation(this.path, this.line, this.rule, this.fix, this.source);

  @override
  String toString() => '$path:$line  [$rule] $fix\n    $source';
}

final designRules = <DesignRule>[
  DesignRule('raw-color', RegExp(r'\bColor\(0x|\bColor\.fromA?RGBO?\('), 'use a DsColors token'),
  DesignRule('material-color', RegExp(r'(?<![A-Za-z_])Colors\.(?!transparent\b)'), 'use a DsColors token'),
  DesignRule('font-weight', RegExp(r'\bFontWeight\.'), 'use DsWeight'),
  DesignRule('font-family', RegExp(r'\bfontFamily\s*:'), 'fonts come from the theme (DsFont)'),
  DesignRule('font-size', RegExp(r'\bfontSize\s*:'), 'use a DsType style'),
  DesignRule('radius', RegExp(r'\b(?:BorderRadius|Radius)\.circular\(\s*[0-9]'), 'use DsRadius'),
  DesignRule('spacing', RegExp(r'\bEdgeInsets\.(?:all|symmetric|only|fromLTRB)\([^)]*?(?<![\w.])[1-9][0-9]*(?:\.[0-9]+)?(?![\w.])'),
      'use DsSpace'),
  DesignRule('legacy-theme', RegExp(r'\bAppTheme\.(?!lightTheme\b)'), 'AppTheme.* is a legacy alias; use the Ds tokens'),
];

const _allowedFiles = {'lib/core/design/tokens.dart', 'lib/core/theme.dart'};

/// Scans every .dart file under [root] (default lib/) and returns the violations.
List<DesignViolation> checkDesignTokens({String root = 'lib'}) {
  final out = <DesignViolation>[];
  final files = Directory(root).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  for (final f in files) {
    final path = f.path.replaceAll('\\', '/');
    if (_allowedFiles.contains(path)) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final code = line.trimLeft();
      if (code.startsWith('//') || line.contains('ds-ignore')) continue;
      final stripped = line.replaceAll(RegExp(r"'[^']*'"), "''"); // ignore text inside string literals
      for (final r in designRules) {
        if (r.pattern.hasMatch(stripped)) out.add(DesignViolation(path, i + 1, r.name, r.fix, code));
      }
    }
  }
  return out;
}

void main(List<String> args) {
  final found = checkDesignTokens(root: args.isEmpty ? 'lib' : args.first);
  if (found.isEmpty) {
    stdout.writeln('design tokens: OK (no hard-coded colours, fonts, weights, radii or spacing)');
    return;
  }
  for (final v in found) {
    stdout.writeln(v);
  }
  stdout.writeln('\n${found.length} hard-coded style value(s). See design/DESIGN_SYSTEM.md.');
  exitCode = 1;
}
