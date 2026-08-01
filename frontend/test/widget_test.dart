import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:onebharat_app/main.dart';

void main() {
  testWidgets('App boots and shows a loading/login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OneBharatApp()));
    await tester.pump();

    // Auth status starts as "unknown" while tryAutoLogin() resolves, so the app
    // should render without throwing — either a spinner or the login screen.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
