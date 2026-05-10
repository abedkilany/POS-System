# Marketplace Server Binding V5

هذه النسخة تضيف ربط فعلي بين تطبيق Flutter والـ Local Marketplace Server.

## الإضافات

- إضافة `MarketplaceApiService` داخل Flutter.
- شاشة Marketplace أصبحت تقرأ المتاجر من:
  - `GET /marketplace/stores`
- صفحة متجر جديدة تقرأ المنتجات من:
  - `GET /marketplace/stores/:id/products`
- إضافة Cart بسيط داخل صفحة المتجر.
- إضافة إرسال طلب إلى السيرفر المحلي عبر:
  - `POST /marketplace/orders`
- عرض طلبات الزبون عبر:
  - `GET /marketplace/orders?customerUserId=...`
- إضافة صفحة إعداد رابط السيرفر من حساب الزبون.
- جعل الـ Local Server يقبل مسارات `/api/*` وبدون `/api/*` حتى يعمل مع كود Vercel السابق.
- جعل المتاجر تظهر من `platform_stores` وأيضًا من `store_profile` snapshots المنشورة بالمزامنة.

## طريقة الاستخدام

1. شغل السيرفر المحلي:

```powershell
npm run local-server
```

2. شغل Cloudflare Tunnel:

```powershell
cloudflared tunnel --url http://localhost:3000
```

3. افتح التطبيق كزبون.
4. من إعدادات الحساب افتح “رابط سيرفر الـ Marketplace”.
5. ضع رابط Cloudflare مثل:

```text
https://xxxxx.trycloudflare.com
```

6. اضغط حفظ ثم ارجع للـ Marketplace واضغط تحديث.

## ملاحظة

حتى تظهر المنتجات، يجب أن يكون جهاز المتجر مضبوطًا على نفس رابط السيرفر، وأن يعمل بمزامنة Marketplace/Cloud حتى يرسل المنتجات كـ sync snapshots إلى السيرفر المحلي.
