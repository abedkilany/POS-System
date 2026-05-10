# Local Marketplace Server

هذا السيرفر المحلي يحوّل المزامنة من Vercel/Neon إلى سيرفر محلي دائم مع SQLite.

## المتطلبات

- Node.js 24 أو أحدث موجود عندك حاليًا.
- لا يحتاج `npm install` لأن السيرفر يستخدم مكتبات Node المدمجة فقط.

## التشغيل السريع على Windows PowerShell

```powershell
cd C:\Users\User\Desktop\Store\local-server
copy .env.example .env
npm start
```

بعد التشغيل افتح:

```text
http://localhost:3000/health
```

إذا ظهر `ok: true` فالسيرفر يعمل.

## الربط لاحقًا مع Cloudflare Tunnel

```powershell
cloudflared tunnel --url http://localhost:3000
```

ثم استخدم رابط `trycloudflare.com` داخل التطبيق كرابط API.

## أهم endpoints المتوافقة مبدئيًا مع النسخة الحالية

- `GET /health`
- `POST /auth/register`
- `POST /auth/login`
- `POST /store/create`
- `POST /store/link`
- `POST /sync/push`
- `GET /sync/pull`
- `POST /sync/requests/push`
- `GET /sync/requests/pull`
- `POST /sync/requests/ack`
- `POST /sync/host-heartbeat`
- `GET /marketplace/stores`
- `GET /marketplace/stores/:storeId/products`

## ملاحظات مهمة

- قاعدة بيانات المتجر تبقى داخل جهاز المتجر.
- قاعدة بيانات Marketplace المحلية موجودة في `local-server/data/marketplace.db`.
- السيرفر يسجل `sync_events` و `entity_snapshots` محليًا بدل Neon.
- لا تنسخ `data/marketplace.db` بين الأجهزة إلا إذا كنت تريد نقل قاعدة السيرفر نفسها.
