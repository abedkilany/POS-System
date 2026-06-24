import 'dart:convert';

import 'package:flutter/services.dart';

import '../services/local_database_service.dart';

enum ShortcutPage { sale, salePayment, purchases, purchaseDialog }

extension ShortcutPageInfo on ShortcutPage {
  String get id => switch (this) {
        ShortcutPage.sale => 'sale',
        ShortcutPage.salePayment => 'salePayment',
        ShortcutPage.purchases => 'purchases',
        ShortcutPage.purchaseDialog => 'purchaseDialog',
      };

  String get labelKey => switch (this) {
        ShortcutPage.sale => 'sale_page',
        ShortcutPage.salePayment => 'shortcut_page_sale_payment',
        ShortcutPage.purchases => 'purchases',
        ShortcutPage.purchaseDialog => 'shortcut_page_purchase_dialog',
      };
}

enum SaleShortcutAction {
  focusBarcode,
  searchProduct,
  holdCart,
  restoreHeldCarts,
  openPayment,
  clearCart,
}

extension SaleShortcutActionInfo on SaleShortcutAction {
  String get id => switch (this) {
        SaleShortcutAction.focusBarcode => 'focusBarcode',
        SaleShortcutAction.searchProduct => 'searchProduct',
        SaleShortcutAction.holdCart => 'holdCart',
        SaleShortcutAction.restoreHeldCarts => 'restoreHeldCarts',
        SaleShortcutAction.openPayment => 'openPayment',
        SaleShortcutAction.clearCart => 'clearCart',
      };

  String get labelKey => switch (this) {
        SaleShortcutAction.focusBarcode => 'shortcut_sale_focus_barcode',
        SaleShortcutAction.searchProduct => 'shortcut_sale_search_product',
        SaleShortcutAction.holdCart => 'shortcut_sale_hold_cart',
        SaleShortcutAction.restoreHeldCarts => 'shortcut_sale_restore_held_carts',
        SaleShortcutAction.openPayment => 'shortcut_sale_open_payment',
        SaleShortcutAction.clearCart => 'shortcut_sale_clear_cart',
      };

  static SaleShortcutAction? fromId(String id) {
    for (final action in SaleShortcutAction.values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

enum SalePaymentShortcutAction {
  confirmPayment,
  cancelPayment,
  focusDiscount,
  focusCashReceived,
  toggleCash,
  toggleCard,
  toggleCredit,
}

extension SalePaymentShortcutActionInfo on SalePaymentShortcutAction {
  String get id => switch (this) {
        SalePaymentShortcutAction.confirmPayment => 'confirmPayment',
        SalePaymentShortcutAction.cancelPayment => 'cancelPayment',
        SalePaymentShortcutAction.focusDiscount => 'focusDiscount',
        SalePaymentShortcutAction.focusCashReceived => 'focusCashReceived',
        SalePaymentShortcutAction.toggleCash => 'toggleCash',
        SalePaymentShortcutAction.toggleCard => 'toggleCard',
        SalePaymentShortcutAction.toggleCredit => 'toggleCredit',
      };

  String get labelKey => switch (this) {
        SalePaymentShortcutAction.confirmPayment => 'shortcut_payment_confirm',
        SalePaymentShortcutAction.cancelPayment => 'shortcut_payment_cancel',
        SalePaymentShortcutAction.focusDiscount => 'shortcut_payment_focus_discount',
        SalePaymentShortcutAction.focusCashReceived => 'shortcut_payment_focus_cash_received',
        SalePaymentShortcutAction.toggleCash => 'shortcut_payment_cash',
        SalePaymentShortcutAction.toggleCard => 'shortcut_payment_card',
        SalePaymentShortcutAction.toggleCredit => 'shortcut_payment_credit',
      };

  static SalePaymentShortcutAction? fromId(String id) {
    for (final action in SalePaymentShortcutAction.values) {
      if (action.id == id) return action;
    }
    return null;
  }
}


enum PurchasesShortcutAction {
  newPurchase,
  focusSearch,
  filterAll,
  filterDraft,
  filterReceived,
  clearSearch,
}

extension PurchasesShortcutActionInfo on PurchasesShortcutAction {
  String get id => switch (this) {
        PurchasesShortcutAction.newPurchase => 'newPurchase',
        PurchasesShortcutAction.focusSearch => 'focusSearch',
        PurchasesShortcutAction.filterAll => 'filterAll',
        PurchasesShortcutAction.filterDraft => 'filterDraft',
        PurchasesShortcutAction.filterReceived => 'filterReceived',
        PurchasesShortcutAction.clearSearch => 'clearSearch',
      };

  String get labelKey => switch (this) {
        PurchasesShortcutAction.newPurchase => 'shortcut_purchases_new_purchase',
        PurchasesShortcutAction.focusSearch => 'shortcut_purchases_focus_search',
        PurchasesShortcutAction.filterAll => 'shortcut_purchases_filter_all',
        PurchasesShortcutAction.filterDraft => 'shortcut_purchases_filter_draft',
        PurchasesShortcutAction.filterReceived => 'shortcut_purchases_filter_received',
        PurchasesShortcutAction.clearSearch => 'shortcut_purchases_clear_search',
      };

  static PurchasesShortcutAction? fromId(String id) {
    for (final action in PurchasesShortcutAction.values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

enum PurchaseDialogShortcutAction {
  chooseProduct,
  addLine,
  savePurchase,
  cancelPurchase,
  toggleReceiveNow,
  focusQuantity,
  focusCost,
  focusPaidAmount,
}

extension PurchaseDialogShortcutActionInfo on PurchaseDialogShortcutAction {
  String get id => switch (this) {
        PurchaseDialogShortcutAction.chooseProduct => 'chooseProduct',
        PurchaseDialogShortcutAction.addLine => 'addLine',
        PurchaseDialogShortcutAction.savePurchase => 'savePurchase',
        PurchaseDialogShortcutAction.cancelPurchase => 'cancelPurchase',
        PurchaseDialogShortcutAction.toggleReceiveNow => 'toggleReceiveNow',
        PurchaseDialogShortcutAction.focusQuantity => 'focusQuantity',
        PurchaseDialogShortcutAction.focusCost => 'focusCost',
        PurchaseDialogShortcutAction.focusPaidAmount => 'focusPaidAmount',
      };

  String get labelKey => switch (this) {
        PurchaseDialogShortcutAction.chooseProduct => 'shortcut_purchase_dialog_choose_product',
        PurchaseDialogShortcutAction.addLine => 'shortcut_purchase_dialog_add_line',
        PurchaseDialogShortcutAction.savePurchase => 'shortcut_purchase_dialog_save',
        PurchaseDialogShortcutAction.cancelPurchase => 'shortcut_purchase_dialog_cancel',
        PurchaseDialogShortcutAction.toggleReceiveNow => 'shortcut_purchase_dialog_toggle_receive',
        PurchaseDialogShortcutAction.focusQuantity => 'shortcut_purchase_dialog_focus_qty',
        PurchaseDialogShortcutAction.focusCost => 'shortcut_purchase_dialog_focus_cost',
        PurchaseDialogShortcutAction.focusPaidAmount => 'shortcut_purchase_dialog_focus_paid',
      };

  static PurchaseDialogShortcutAction? fromId(String id) {
    for (final action in PurchaseDialogShortcutAction.values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

class SaleShortcutSettings {
  const SaleShortcutSettings({required this.saleBindings, required this.paymentBindings, required this.purchasesBindings, required this.purchaseDialogBindings});

  static const storageKey = 'keyboard_shortcuts_sale_v3';
  static const noneKey = 'NONE';
  static const availableKeys = <String>[
    noneKey,
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
    'Enter',
    'Esc',
  ];

  static const defaultSaleBindings = <SaleShortcutAction, String>{
    SaleShortcutAction.focusBarcode: 'F1',
    SaleShortcutAction.searchProduct: 'F2',
    SaleShortcutAction.holdCart: 'F4',
    SaleShortcutAction.restoreHeldCarts: 'F5',
    SaleShortcutAction.openPayment: 'F7',
    SaleShortcutAction.clearCart: 'F12',
  };

  static const defaultPaymentBindings = <SalePaymentShortcutAction, String>{
    SalePaymentShortcutAction.confirmPayment: 'Enter',
    SalePaymentShortcutAction.cancelPayment: 'Esc',
    SalePaymentShortcutAction.focusDiscount: 'F8',
    SalePaymentShortcutAction.focusCashReceived: 'F6',
    SalePaymentShortcutAction.toggleCash: 'F9',
    SalePaymentShortcutAction.toggleCard: 'F10',
    SalePaymentShortcutAction.toggleCredit: 'F11',
  };

  static const defaultPurchasesBindings = <PurchasesShortcutAction, String>{
    PurchasesShortcutAction.newPurchase: 'F1',
    PurchasesShortcutAction.focusSearch: 'F2',
    PurchasesShortcutAction.filterAll: 'F3',
    PurchasesShortcutAction.filterDraft: 'F4',
    PurchasesShortcutAction.filterReceived: 'F5',
    PurchasesShortcutAction.clearSearch: 'Esc',
  };

  static const defaultPurchaseDialogBindings = <PurchaseDialogShortcutAction, String>{
    PurchaseDialogShortcutAction.chooseProduct: 'F2',
    PurchaseDialogShortcutAction.addLine: 'Enter',
    PurchaseDialogShortcutAction.savePurchase: 'F7',
    PurchaseDialogShortcutAction.cancelPurchase: 'Esc',
    PurchaseDialogShortcutAction.toggleReceiveNow: 'F4',
    PurchaseDialogShortcutAction.focusQuantity: 'F6',
    PurchaseDialogShortcutAction.focusCost: 'F8',
    PurchaseDialogShortcutAction.focusPaidAmount: 'F9',
  };

  final Map<SaleShortcutAction, String> saleBindings;
  final Map<SalePaymentShortcutAction, String> paymentBindings;
  final Map<PurchasesShortcutAction, String> purchasesBindings;
  final Map<PurchaseDialogShortcutAction, String> purchaseDialogBindings;

  factory SaleShortcutSettings.defaults() => const SaleShortcutSettings(
        saleBindings: defaultSaleBindings,
        paymentBindings: defaultPaymentBindings,
        purchasesBindings: defaultPurchasesBindings,
        purchaseDialogBindings: defaultPurchaseDialogBindings,
      );

  factory SaleShortcutSettings.load() {
    final oldRaw = LocalDatabaseService.getString('keyboard_shortcuts_sale_v2') ?? LocalDatabaseService.getString('keyboard_shortcuts_sale_v1');
    final raw = LocalDatabaseService.getString(storageKey) ?? oldRaw;
    if (raw == null || raw.trim().isEmpty) return SaleShortcutSettings.defaults();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final sale = <SaleShortcutAction, String>{};
      final payment = <SalePaymentShortcutAction, String>{};
      final purchases = <PurchasesShortcutAction, String>{};
      final purchaseDialog = <PurchaseDialogShortcutAction, String>{};

      final saleSource = decoded.containsKey('sale') ? decoded['sale'] : decoded;
      if (saleSource is Map<String, dynamic>) {
        for (final entry in saleSource.entries) {
          final action = SaleShortcutActionInfo.fromId(entry.key);
          final key = entry.value as String?;
          if (action != null && key != null && availableKeys.contains(key)) sale[action] = key;
        }
      }

      final paymentSource = decoded['salePayment'];
      if (paymentSource is Map<String, dynamic>) {
        for (final entry in paymentSource.entries) {
          final action = SalePaymentShortcutActionInfo.fromId(entry.key);
          final key = entry.value as String?;
          if (action != null && key != null && availableKeys.contains(key)) payment[action] = key;
        }
      }

      final purchasesSource = decoded['purchases'];
      if (purchasesSource is Map<String, dynamic>) {
        for (final entry in purchasesSource.entries) {
          final action = PurchasesShortcutActionInfo.fromId(entry.key);
          final key = entry.value as String?;
          if (action != null && key != null && availableKeys.contains(key)) purchases[action] = key;
        }
      }

      final purchaseDialogSource = decoded['purchaseDialog'];
      if (purchaseDialogSource is Map<String, dynamic>) {
        for (final entry in purchaseDialogSource.entries) {
          final action = PurchaseDialogShortcutActionInfo.fromId(entry.key);
          final key = entry.value as String?;
          if (action != null && key != null && availableKeys.contains(key)) purchaseDialog[action] = key;
        }
      }

      return SaleShortcutSettings(
        saleBindings: {...defaultSaleBindings, ...sale},
        paymentBindings: {...defaultPaymentBindings, ...payment},
        purchasesBindings: {...defaultPurchasesBindings, ...purchases},
        purchaseDialogBindings: {...defaultPurchaseDialogBindings, ...purchaseDialog},
      );
    } catch (_) {
      return SaleShortcutSettings.defaults();
    }
  }

  Future<void> save() async {
    await LocalDatabaseService.setString(storageKey, jsonEncode({
      'sale': {for (final entry in saleBindings.entries) entry.key.id: entry.value},
      'salePayment': {for (final entry in paymentBindings.entries) entry.key.id: entry.value},
      'purchases': {for (final entry in purchasesBindings.entries) entry.key.id: entry.value},
      'purchaseDialog': {for (final entry in purchaseDialogBindings.entries) entry.key.id: entry.value},
    }));
  }

  SaleShortcutAction? saleActionForKey(String keyName) {
    for (final entry in saleBindings.entries) {
      if (entry.value == keyName && entry.value != noneKey) return entry.key;
    }
    return null;
  }

  SalePaymentShortcutAction? paymentActionForKey(String keyName) {
    for (final entry in paymentBindings.entries) {
      if (entry.value == keyName && entry.value != noneKey) return entry.key;
    }
    return null;
  }

  PurchasesShortcutAction? purchasesActionForKey(String keyName) {
    for (final entry in purchasesBindings.entries) {
      if (entry.value == keyName && entry.value != noneKey) return entry.key;
    }
    return null;
  }

  PurchaseDialogShortcutAction? purchaseDialogActionForKey(String keyName) {
    for (final entry in purchaseDialogBindings.entries) {
      if (entry.value == keyName && entry.value != noneKey) return entry.key;
    }
    return null;
  }

  SaleShortcutSettings copyWithSaleActionKey(SaleShortcutAction action, String keyName) {
    final next = Map<SaleShortcutAction, String>.from(saleBindings);
    next[action] = keyName;
    return SaleShortcutSettings(saleBindings: next, paymentBindings: paymentBindings, purchasesBindings: purchasesBindings, purchaseDialogBindings: purchaseDialogBindings);
  }

  SaleShortcutSettings copyWithPaymentActionKey(SalePaymentShortcutAction action, String keyName) {
    final next = Map<SalePaymentShortcutAction, String>.from(paymentBindings);
    next[action] = keyName;
    return SaleShortcutSettings(saleBindings: saleBindings, paymentBindings: next, purchasesBindings: purchasesBindings, purchaseDialogBindings: purchaseDialogBindings);
  }


  SaleShortcutSettings copyWithPurchasesActionKey(PurchasesShortcutAction action, String keyName) {
    final next = Map<PurchasesShortcutAction, String>.from(purchasesBindings);
    next[action] = keyName;
    return SaleShortcutSettings(saleBindings: saleBindings, paymentBindings: paymentBindings, purchasesBindings: next, purchaseDialogBindings: purchaseDialogBindings);
  }

  SaleShortcutSettings copyWithPurchaseDialogActionKey(PurchaseDialogShortcutAction action, String keyName) {
    final next = Map<PurchaseDialogShortcutAction, String>.from(purchaseDialogBindings);
    next[action] = keyName;
    return SaleShortcutSettings(saleBindings: saleBindings, paymentBindings: paymentBindings, purchasesBindings: purchasesBindings, purchaseDialogBindings: next);
  }

  bool isSaleKeyUsedByAnotherAction(String keyName, SaleShortcutAction action) {
    if (keyName == noneKey) return false;
    return saleBindings.entries.any((entry) => entry.key != action && entry.value == keyName);
  }

  bool isPaymentKeyUsedByAnotherAction(String keyName, SalePaymentShortcutAction action) {
    if (keyName == noneKey) return false;
    return paymentBindings.entries.any((entry) => entry.key != action && entry.value == keyName);
  }

  bool isPurchasesKeyUsedByAnotherAction(String keyName, PurchasesShortcutAction action) {
    if (keyName == noneKey) return false;
    return purchasesBindings.entries.any((entry) => entry.key != action && entry.value == keyName);
  }

  bool isPurchaseDialogKeyUsedByAnotherAction(String keyName, PurchaseDialogShortcutAction action) {
    if (keyName == noneKey) return false;
    return purchaseDialogBindings.entries.any((entry) => entry.key != action && entry.value == keyName);
  }

  String? keyForSaleAction(SaleShortcutAction action) => saleBindings[action];
  String? keyForPaymentAction(SalePaymentShortcutAction action) => paymentBindings[action];
  String? keyForPurchasesAction(PurchasesShortcutAction action) => purchasesBindings[action];
  String? keyForPurchaseDialogAction(PurchaseDialogShortcutAction action) => purchaseDialogBindings[action];

  static String? keyNameForLogicalKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.f1) return 'F1';
    if (key == LogicalKeyboardKey.f2) return 'F2';
    if (key == LogicalKeyboardKey.f3) return 'F3';
    if (key == LogicalKeyboardKey.f4) return 'F4';
    if (key == LogicalKeyboardKey.f5) return 'F5';
    if (key == LogicalKeyboardKey.f6) return 'F6';
    if (key == LogicalKeyboardKey.f7) return 'F7';
    if (key == LogicalKeyboardKey.f8) return 'F8';
    if (key == LogicalKeyboardKey.f9) return 'F9';
    if (key == LogicalKeyboardKey.f10) return 'F10';
    if (key == LogicalKeyboardKey.f11) return 'F11';
    if (key == LogicalKeyboardKey.f12) return 'F12';
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) return 'Enter';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    return null;
  }
}
