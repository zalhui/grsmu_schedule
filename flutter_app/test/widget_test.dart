import 'package:flutter_test/flutter_test.dart';
import 'package:grsmu_schedule/main.dart';

void main() {
  testWidgets('application starts', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('Расписание'), findsOneWidget);
  });
}
