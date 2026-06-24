import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:set_new_version/main.dart';

void main() {
  testWidgets('renders the updater shell', (tester) async {
    await tester.pumpWidget(const SetNewVersionApp());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
