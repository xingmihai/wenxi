import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asterlink/domain/appearance.dart';
import 'package:asterlink/ui/app_theme.dart';
import 'package:asterlink/ui/liquid_glass.dart';

Widget _host({
  required Widget child,
  GlassStyle style = GlassStyle.clear,
  Brightness brightness = Brightness.light,
}) =>
    MaterialApp(
      theme: appTheme(
        brightness,
        palette: AppPalette.blue,
        glassStyle: style,
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('renders its child and exposes the theme appearance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(child: const LiquidGlass(child: Text('inside'))),
    );

    expect(find.text('inside'), findsOneWidget);
    expect(
      AppAppearance.of(tester.element(find.text('inside'))).glassStyle,
      GlassStyle.clear,
    );
  });

  testWidgets('samples the backdrop for clear and frosted glass', (
    WidgetTester tester,
  ) async {
    for (final style in <GlassStyle>[GlassStyle.clear, GlassStyle.frosted]) {
      await tester.pumpWidget(
        _host(style: style, child: const LiquidGlass(child: SizedBox())),
      );
      expect(
        find.byType(BackdropFilter),
        findsOneWidget,
        reason: '$style should blur the backdrop',
      );
    }
  });

  testWidgets('solid glass skips the blur pass entirely', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        style: GlassStyle.solid,
        child: const LiquidGlass(child: SizedBox()),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      usesLiquidGlass(tester.element(find.byType(LiquidGlass))),
      isFalse,
    );
  });

  testWidgets('an enabled button forwards the tap', (
    WidgetTester tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        child: LiquidGlassButton(
          onPressed: () => taps++,
          child: const Text('解析'),
        ),
      ),
    );

    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a disabled button installs no tap handler', (
    WidgetTester tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        child: LiquidGlassButton(
          enabled: false,
          onPressed: () => taps++,
          child: const Text('解析'),
        ),
      ),
    );

    // A disabled surface installs no recognizer at all, so ask the tap not to
    // fail on a miss: the point of the assertion is that nothing fires.
    await tester.tap(find.text('解析'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(taps, 0);
  });
}
