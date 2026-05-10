# Store Publish Marketplace V6

This build adds the missing publishing step between the store device and the local Marketplace server.

## Added

- Local server endpoint:
  - `POST /marketplace/publish-store`
- Local SQLite table:
  - `marketplace_products`
- Store publishing button in the store app top bar:
  - cloud upload icon
- Publishes:
  - store profile
  - active products
  - prices
  - quantities
  - product categories
- Customer Marketplace now shows only stores actually published to the server.
- The demo/default `My Store` seed was removed from the local server.

## Flow

1. Start `local-server`.
2. Start Cloudflare Tunnel.
3. In the app, set the Marketplace API URL to the Tunnel URL.
4. Login as a store account.
5. Click the cloud upload button to publish the store.
6. Login as a customer and refresh Marketplace.
7. The real store and products should appear.

## Notes

The current `trycloudflare.com` URL is temporary. If it changes, update it in Marketplace Server settings.
