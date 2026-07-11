import 'package:flutter_test/flutter_test.dart';
import 'package:coran_karim/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CoranKarimApp());
    expect(find.byType(CoranKarimApp), findsOneWidget);
  });
}
