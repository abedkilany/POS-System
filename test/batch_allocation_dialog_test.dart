import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/localization/app_localizations.dart';
import 'package:ventio/features/inventory/batch_allocation_dialog.dart';
import 'package:ventio/models/product.dart';

class _FakeLocalizations extends AppLocalizations {
  _FakeLocalizations() : super(const Locale('en'));

  @override
  String text(String key) =>
      const <String, String>{
        'expiry_batches': 'Expiry batches',
        'quantity': 'Quantity',
        'batch_number': 'Batch number',
        'expiration_date': 'Expiration date',
        'delete': 'Delete',
        'add_batch': 'Add batch',
        'cancel': 'Cancel',
        'save': 'Save',
      }[key] ??
      key;
}

void main() {
  testWidgets('batch allocation dialog lets the user split one quantity',
      (tester) async {
    final product = Product(
      id: 'food',
      name: 'Food',
      code: 'FOOD',
      price: 2,
      cost: 1,
      stock: 0,
      category: 'Food',
      expiryTrackingEnabled: true,
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showBatchAllocationDialog(
              context,
              product: product,
              expectedQuantity: 10,
              sourceId: 'test',
              localizations: _FakeLocalizations(),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Expiry batches — Food'), findsOneWidget);
    expect(find.text('Add batch'), findsOneWidget);
    await tester.tap(find.text('Add batch'));
    await tester.pump();
    expect(find.byType(Card), findsNWidgets(2));
  });
}
