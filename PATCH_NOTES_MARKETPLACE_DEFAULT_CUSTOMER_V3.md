# Marketplace Default Customer V3

## What changed

- First screen remains Login / Register.
- New signup now creates the account as `customer` by default.
- After signup/login, customer accounts go directly to the Marketplace home.
- The Marketplace home now has:
  - Search bar
  - Category chips
  - Available stores section
  - My orders section
  - Settings shortcut
- Customer settings now include:
  - Account info
  - Activate Store Mode / link existing store
  - Placeholder for Delivery Driver activation
- Server-side public registration now allows `customer` accounts, not only `platform_user`.

## Intended flow

1. User opens app.
2. User logs in or creates a new account.
3. New account is a customer automatically.
4. Customer lands on Marketplace.
5. From Settings, user can activate Store Mode or later request Driver Mode.
