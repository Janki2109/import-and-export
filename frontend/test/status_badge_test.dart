import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebharat_app/widgets/status_badge.dart';

void main() {
  testWidgets('StatusBadge renders the human-readable status label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatusBadge(status: 'payment_held'))),
    );

    expect(find.text('Payment Held'), findsOneWidget);
  });

  testWidgets('StatusBadge updates when the status prop changes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatusBadge(status: 'created'))),
    );
    expect(find.text('Created'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatusBadge(status: 'delivered'))),
    );
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('Created'), findsNothing);
  });
}
