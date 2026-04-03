import 'package:flutter_test/flutter_test.dart';

import 'package:offlineaudiosherpa/src/app.dart';

void main() {
  testWidgets('App renders voice translation shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OfflineVoiceApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Control Deck'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Activity Log'), findsOneWidget);
    expect(find.text('Live Monitor'), findsOneWidget);
  });
}
