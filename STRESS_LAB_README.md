# Ventio Temporary Stress Lab

This temporary build adds a real-app stress simulation page to the main drawer.

Open: Drawer -> Stress Lab

It uses the real AppStore service methods, not direct database writes:
- addOrUpdateSupplier
- addOrUpdateCustomer
- addOrUpdateProduct
- createSale
- UnifiedSyncFactory cloud/lan syncNow
- exportBackupJson as a backup-size probe

Suggested runs:

## HOST
Products: 1000
Customers: 500
Suppliers: 100
Sales: 500
Progress every: 25
Click: Run Real App Stress Simulation
Then click Copy Log and send the log.

## Client LAN
After pairing the client through LAN:
Products: 0 or 100
Customers: 0 or 50
Suppliers: 0 or 20
Sales: 100-300
Click: Run Real App Stress Simulation
Then check the HOST and run Sync Now if needed.
Copy logs from both client and host.

## Client Cloud
After pairing the client through Cloud:
Products: 0 or 100
Customers: 0 or 50
Suppliers: 0 or 20
Sales: 100-300
Click: Run Real App Stress Simulation
Then run/verify sync on the HOST.
Copy logs from both client and host.

Important:
- Use a temporary test copy/database only.
- The page is intentionally visible in the drawer for this temporary test build.
- Generated records include [STRESS] in names and a unique batch id in logs.
