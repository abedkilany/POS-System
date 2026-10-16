import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/currency_utils.dart';
import 'package:ventio/core/contracts/application_session.dart';
import '../../models/catalog_item.dart';
import '../../models/product.dart';
import '../../models/product_pricing.dart';
import '../../models/store_profile.dart';
import '../../models/supplier.dart';
import '../../models/supplier_product_price.dart';
import '../../models/user_role.dart';
import '../../core/services/page_timing_scope.dart';
import '../../core/services/price_list_pdf_service.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/page_data_load_indicator.dart';
import '../barcode/barcode_scanner_page.dart';
part 'products_page_methods_01.dart';
part 'products_page_methods_02.dart';
part 'products_page_methods_03.dart';

part 'products_page_components_01.dart';
part 'products_page_components_02.dart';
part 'products_page_components_03.dart';
part 'products_page_components_04.dart';
