import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/widgets/app_section_header.dart';
import 'package:ventio/widgets/empty_state_card.dart';
import 'package:ventio/widgets/report_card.dart';
import 'package:ventio/widgets/summary_card.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('Reusable widget smoke tests', () {
    testWidgets('AppSectionHeader renders title and subtitle', (tester) async {
      await tester.pumpWidget(wrap(const AppSectionHeader(title: 'Inventory', subtitle: 'Track stock')));
      expect(find.text('Inventory'), findsOneWidget);
      expect(find.text('Track stock'), findsOneWidget);
    });

    testWidgets('EmptyStateCard renders icon, title, and message', (tester) async {
      await tester.pumpWidget(wrap(const EmptyStateCard(icon: Icons.inventory_2_outlined, title: 'No products', subtitle: 'Add your first product')));
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
      expect(find.text('No products'), findsOneWidget);
      expect(find.text('Add your first product'), findsOneWidget);
    });

    testWidgets('SummaryCard renders label and value', (tester) async {
      await tester.pumpWidget(wrap(const SummaryCard(title: 'Sales', value: r'$120.00', icon: Icons.receipt_long)));
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text(r'$120.00'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long), findsOneWidget);
    });

    testWidgets('ReportCard renders label and value', (tester) async {
      await tester.pumpWidget(wrap(const ReportCard(title: 'Gross Profit', subtitle: r'$55.00')));
      expect(find.text('Gross Profit'), findsOneWidget);
      expect(find.text(r'$55.00'), findsOneWidget);
      expect(find.byIcon(Icons.insert_chart_outlined), findsOneWidget);
    });
  });
}
