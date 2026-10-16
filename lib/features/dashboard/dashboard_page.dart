import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/startup_timing_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import 'package:ventio/core/contracts/application_session.dart';
import '../../widgets/page_data_load_indicator.dart';
import '../accounting/accounting_page.dart';
import '../expenses/expenses_page.dart';
import '../products/products_page.dart';
import '../purchases/purchases_page.dart';
import '../reports/reports_page.dart';
import '../sales/sales_page.dart';
import 'dashboard_snapshot_service.dart';
import 'dashboard_service.dart';
part 'dashboard_page_split_01.dart';
part 'dashboard_page_split_02.dart';
part 'dashboard_page_split_03.dart';
