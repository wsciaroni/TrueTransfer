import 'package:flutter_test/flutter_test.dart';
import 'package:truetransfer/main.dart';

void main() {
  testWidgets('App initialization smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the title "TrueTransfer" is present on the screen
    expect(find.text('TrueTransfer'), findsOneWidget);

    // Verify that the Connection screen elements are shown (such as "SMB Connection")
    expect(find.text('SMB Connection'), findsOneWidget);
  });
}
