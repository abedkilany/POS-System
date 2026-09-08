# Ventio — Unified Batch repair report — 2026-09-08

## المشكلة
تم العثور في قاعدة البيانات على حركات مخزون حدثت بعد تفعيل `unified_batch_cutovers` لمستودع **سيارة رابيد** ولكن بدون `batch_id`. أدى ذلك إلى اختلاف `warehouse_inventory` عن صافي أرصدة الـBatch، وبالتالي منع عمليات النقل وإظهار `error_batch_cutover_mismatch`.

## إصلاح قاعدة البيانات
- تم إصلاح 81 حركة post-cutover كانت بدون Batch:
  - 49 حركة بيع.
  - 19 حركة Transfer Out.
  - 13 حركة Transfer In.
- تمت إعادة ربط حركات النقل بالدفعات الصحيحة مع المحافظة على كميات `warehouse_inventory` كما هي دون تعديل يدوي.
- تمت إعادة بناء تخصيصات Batch لـ 49 بند بيع تاريخي مع الحفاظ على تكلفة البيع التاريخية المسجلة.
- نتج 51 Batch allocation لبنود البيع؛ بندان فقط احتاجا تقسيم الكمية على دفعتين.
- تمت تسوية 10 سجلات Negative Stock Deficit من الحركات الواردة التاريخية.
- توجد تسوية تكلفة فعلية واحدة فقط: فرق خام `0.213333... USD`، وتم تسجيل قيد محاسبي مدوّر بقيمة `0.21 USD` تحت رقم `JE-2026-000329`، مدين COGS ودائن مخزون البضائع وفق إعدادات الحسابات الحالية.

## النتيجة بعد الإصلاح
- حالات عدم تطابق warehouse/batch: **27 → 0**.
- حركات post-cutover بدون `batch_id`: **81 → 0**.
- مجموع كميات `stock_movements` لكل منتج/مستودع لم يتغير.
- جدول `warehouse_inventory` لم يتغير.
- Transfer batch quantity traceability نجح للمجموعات التاريخية الخمس المتأثرة.
- لا توجد Batch references يتيمة ضمن الحركات المصححة.
- لا توجد أرصدة Batch فعلية سالبة.
- `PRAGMA integrity_check = ok`.
- `PRAGMA foreign_key_check` أعاد 0 مشاكل.

## تعديل التطبيق لمنع تكرار المشكلة
تم تعديل المصدر في المسارات التالية:
- `lib/core/services/stock_transaction_service.dart`
  - منع أي stock movement بعد Unified Batch cutover لمنتج stock-tracked إذا كان `batch_id` فارغًا.
- `lib/data/app_store_sync_apply.dart`
  - تطبيق نفس الحماية على حركات المخزون الواردة من المزامنة.
- `lib/core/localization/localized_domain_exception.dart`
  - إذا كان مفتاح الترجمة غير موجود، يتم عرض fallback مفهوم بدل المفتاح الخام مثل `error_batch_cutover_mismatch`.
- `lib/core/services/batch_inventory_service.dart`
  - تحسين fallback الخاص بخطأ عدم مطابقة Batch/warehouse بالعربية.

## فحوص المصدر
- Phase 7 static verifier: **14/14 PASS**.
- Phase 8 static verifier: **26/26 PASS**.
- Phase 9 static verifier: **39/40 PASS**؛ الفشل الوحيد لأن أداة الفحص القديمة تتوقع schema 31 بينما المصدر الحالي يستخدم schema 33، وليس بسبب إصلاح Unified Batch.
- Phase 12 static verifier: **30/31 PASS** للسبب نفسه (schema 31 مقابل 33).
- Phase 10 لم يعمل لأن ملفات `assets/translations/*.json` غير موجودة أصلًا داخل نسخة source ZIP المرفوعة.
- بيئة التنفيذ الحالية لا تحتوي Flutter/Dart SDK، لذلك لم يتم تشغيل `flutter analyze` أو `flutter test` أو بناء EXE.

## ملفات التسليم
- قاعدة البيانات المصححة تحمل اسم `ventio.sqlite` داخل ZIP لتكون جاهزة للاستبدال.
- نسخة التطبيق هي **Source Code معدلة** وليست EXE compiled.

يفضل إغلاق Ventio وأخذ نسخة احتياطية من قاعدة البيانات الحالية قبل الاستبدال.
