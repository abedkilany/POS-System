import '../../models/commerce_overview.dart';
import '../../models/credit_note.dart';
import '../../models/customer.dart';
import '../../models/delivery_note.dart';
import '../../models/expense.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../../models/sale_quotation.dart';
import '../../models/supplier.dart';
import '../../models/supplier_purchase_price.dart';
import 'dart:collection';

/// Session-local cache state. SQLite remains authoritative.
class CommerceState {
  final List<Customer> customers = [];
  final List<Sale> sales = [];
  final List<CreditNote> creditNotes = [];
  final List<SaleQuotation> saleQuotations = [];
  final List<DeliveryNote> deliveryNotes = [];
  final List<Supplier> suppliers = [];
  final List<Expense> expenses = [];
  final List<Purchase> purchases = [];
  final Map<String, int> purchaseIndexById = <String, int>{};
  final Map<String, int> expenseIndexById = <String, int>{};
  final Map<String, int> customerIndexById = <String, int>{};
  final Map<String, String> customerIdByNormalizedName = <String, String>{};
  final Map<String, int> supplierIndexById = <String, int>{};
  final Map<String, String> supplierIdByNormalizedName = <String, String>{};
  final Map<String, List<SupplierPurchasePrice>> purchaseHistoryByProductCache =
      <String, List<SupplierPurchasePrice>>{};
  final Map<String, ProductPurchaseMetrics> purchaseMetricsByProductCache =
      <String, ProductPurchaseMetrics>{};
  bool purchaseInsightsCacheDirty = true;
  UnmodifiableListView<Sale>? cachedSales;
  int cachedSalesGeneration = -1;
  int invoiceCounter = 0;
  int purchaseCounter = 0;
  UnmodifiableListView<SaleQuotation>? cachedSaleQuotations;
  UnmodifiableListView<DeliveryNote>? cachedDeliveryNotes;
  Map<String, DeliveryNote>? cachedDeliveryNoteBySaleId;
  UnmodifiableListView<Supplier>? cachedSuppliers;
  PurchasesOverview? cachedPurchasesOverview;
  int cachedPurchasesOverviewRevision = -1;
  String cachedPurchasesOverviewMonthKey = '';
  ExpensesOverview? cachedExpensesOverview;
  int cachedExpensesOverviewRevision = -1;
  int cachedSaleQuotationsGeneration = -1;
  int cachedDeliveryNotesGeneration = -1;
  int cachedDeliveryNoteBySaleIdGeneration = -1;
  int cachedSuppliersGeneration = -1;
}

class ProductPurchaseMetrics {
  const ProductPurchaseMetrics({
    this.lastCost,
    this.averageCost = 0,
    this.supplierCount = 0,
  });

  final double? lastCost;
  final double averageCost;
  final int supplierCount;
}
