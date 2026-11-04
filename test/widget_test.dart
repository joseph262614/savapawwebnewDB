import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saveapawsadminpc/main.dart';

void main() {
  testWidgets('Admin app initial splash gate smoke test', (WidgetTester tester) async {
    // Build the admin application entry gate
    await tester.pumpWidget(const FirebaseInitGate());

    // Verify initial splash state displays the app title and branding
    expect(find.text('SAVE A PAW'), findsOneWidget);
    expect(find.text('Admin Portal'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
