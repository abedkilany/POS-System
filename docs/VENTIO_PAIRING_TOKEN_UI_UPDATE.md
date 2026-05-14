# Ventio Pairing / Device Token UI Update

Implemented in this build:

- Host UI now presents pairing as the main way to add Clients.
- Host can create a one-time pairing code for Cloud or LAN Clients.
- Client UI no longer asks for the Cloud deployment token in the Cloud pairing card.
- Client joins by Cloud API URL + Pairing Code.
- Pairing claim assigns storeId, branchId, hostDeviceId, deviceToken, role=client, and transport.
- The Cloud pairing claim endpoint no longer requires the deployment token.
- Cloud sync settings can be considered configured with API URL only; paired Clients send device credentials in headers.
- Server auth now allows paired device credentials when REQUIRE_DEVICE_TOKEN_AUTH=true, while Host deployment token remains supported for Host/admin actions.
- Legacy LAN host secret is moved to an advanced/fallback label and no longer appears as “Pairing token”.

Recommended deployment:

1. Deploy API changes.
2. Pair Clients from the Host UI.
3. After all Clients are paired, set REQUIRE_DEVICE_TOKEN_AUTH=true in Vercel.
4. Keep CLOUD_SYNC_TOKEN only on Host/admin devices.
