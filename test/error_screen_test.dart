import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traccar_manager/error_screen.dart';

void main() {
  testWidgets('ErrorScreen muestra el error y permite reintentar', (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
      home: ErrorScreen(
        error: 'net::ERR_CONNECTION_REFUSED',
        onRetry: () => retries++,
      ),
    ));

    expect(find.text('No se pudo conectar con el servidor'), findsOneWidget);
    expect(find.text('net::ERR_CONNECTION_REFUSED'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    expect(retries, 1);
  });
}
