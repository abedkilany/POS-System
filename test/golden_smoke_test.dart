import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/widgets/empty_state_card.dart';
import 'package:ventio/widgets/summary_card.dart';

void main() {
  group('Golden visual regression smoke tests', () {
    testWidgets(
      'core dashboard cards keep their visual contract',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SummaryCard(title: 'Today\'s Sales', value: r'$125.00', icon: Icons.point_of_sale),
                    SizedBox(height: 12),
                    EmptyStateCard(icon: Icons.inventory_2_outlined, title: 'No products yet', subtitle: 'Add your first product to start selling.'),
                  ],
                ),
              ),
            ),
          ),
        );

        await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/core_cards.png'));
      },
      skip: !const bool.fromEnvironment('RUN_GOLDENS'),
    );
  });
}
