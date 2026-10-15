import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/cash_ledger_service.dart';
import 'package:ventio/core/services/payment_voucher_service.dart';
import 'package:ventio/core/storage/sqlite/ventio_drift_database.dart';
import 'package:ventio/models/payment_allocation.dart';
part 'payment_voucher_phase2_test_split_01.dart';
part 'payment_voucher_phase2_test_split_02.dart';

void main() => _definePaymentVoucherPhase2Tests();
