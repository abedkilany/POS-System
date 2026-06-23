# Financial Settings & Multi-Currency Core

تمت إضافة طبقة أولية لنظام عملات احترافي بدل الاعتماد الصلب على USD/LBP فقط.

## ما تم تنفيذه

- إضافة نموذج `FinancialCurrency`:
  - code
  - name
  - symbol
  - decimalPlaces
  - cashDecimalPlaces
  - roundingStep
  - isBase
  - isActive

- إضافة نموذج `CurrencyExchangeRate`:
  - fromCurrency
  - toCurrency
  - rate
  - effectiveAt
  - source
  - isActive
  - note

- توسيع `StoreProfile` ليحتوي:
  - baseCurrency
  - priceStorageDecimals
  - currencies
  - exchangeRates
  - roundingDifferenceAccountId

- تحديث `currency_utils.dart`:
  - `normalizePriceAmount`
  - `normalizeAccountingAmount`
  - `normalizeCashAmount`
  - `exchangeRate`
  - `convertCurrency`
  - تنسيق العملة بناءً على تعريف العملة

- تحديث صفحة الإعدادات المالية:
  - عرض العملة الأساسية
  - عرض دقة تخزين الأسعار
  - إدارة العملات
  - إضافة/تعديل عملة
  - إدارة أسعار الصرف
  - إضافة/تعديل سعر صرف
  - اختيار العملة الافتراضية للمنتجات والمبيعات والدفع من العملات النشطة

- ربط `AccountingService` بسياسة المال من `StoreProfile`.
- تحسين ترحيل المبيعات والمشتريات بحيث يتم تقريب مبالغ القيد حسب سياسة المال الحالية قبل إنشاء القيد.

## ملاحظات مهمة

هذه دفعة أساس للنظام الجديد وليست نهاية مشروع العملات بالكامل.

ما زال يلزم لاحقًا:
- إزالة الاعتماد التدريجي على الحقول القديمة مثل `usdToLbpRate`.
- تعميم التحويل متعدد العملات داخل كل الشاشات القديمة.
- إضافة حساب فرق تقريب وحساب فروقات صرف.
- تحويل الحسابات الحساسة مستقبلًا من `double` إلى Decimal أو minor units.
- مراجعة التقارير المالية لتصبح متعددة العملات بالكامل.
