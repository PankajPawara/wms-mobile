import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wms_mobile/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: WmsApp()));

    // Verify that the login screen is displayed by looking for AppFullName or login button text
    expect(find.text('Warehouse Management System'), findsOneWidget); // Router has not initialised frame
  });
}
