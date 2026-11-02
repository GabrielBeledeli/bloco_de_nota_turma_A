import 'package:flutter_test/flutter_test.dart';

import 'package:bloco_de_nota_turma_a/main.dart';

void main() {
  testWidgets('exibe tela de erro quando o Firebase não inicializa', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(firebaseReady: false));

    expect(find.textContaining('Não foi possível conectar'), findsOneWidget);
  });
}
