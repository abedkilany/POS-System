# Patch Notes — Local Marketplace Server V4

هذه النسخة تضيف سيرفر محلي دائم للـ Marketplace بدل الاعتماد الكامل على Vercel/Neon.

## الجديد

- إضافة مجلد `local-server/`.
- السيرفر يعمل عبر Node.js و SQLite محلي.
- لا يحتاج `npm install` داخل `local-server` لأنه يستخدم مكتبات Node المدمجة.
- إضافة endpoints متوافقة مع بنية التطبيق الحالية:
  - `/health`
  - `/auth/register`
  - `/auth/login`
  - `/store/create`
  - `/store/link`
  - `/sync/push`
  - `/sync/pull`
  - `/sync/requests/push`
  - `/sync/requests/pull`
  - `/sync/requests/ack`
  - `/sync/host-heartbeat`
  - `/marketplace/stores`
  - `/marketplace/stores/:storeId/products`

## هدف النسخة

الفصل بين:

- قاعدة بيانات المتجر على جهاز المتجر.
- قاعدة بيانات Marketplace على السيرفر المحلي.
- الوصول الخارجي لاحقًا عبر Cloudflare Tunnel.

## طريقة التشغيل

من جذر المشروع:

```powershell
npm run local-server
```

أو:

```powershell
cd local-server
copy .env.example .env
npm start
```

ثم افتح:

```text
http://localhost:3000/health
```

## ملاحظة مهمة

هذه الخطوة تجهز السيرفر المحلي فقط. ربط تطبيق Flutter تلقائيًا بهذا السيرفر أو رابط Cloudflare يتم من إعدادات Cloud API URL داخل التطبيق، أو في خطوة لاحقة بتعديل `AppConfig.platformBaseUrl`.
