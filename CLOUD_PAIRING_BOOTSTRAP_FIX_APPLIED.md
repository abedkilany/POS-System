# Cloud Pairing Bootstrap Fix Applied

This update makes Cloud pairing perform a real initial bootstrap instead of stopping after the pairing code is consumed.

Changes:
- After a Client successfully claims a Cloud pairing code, the app first attempts to pull the current Cloud materialized snapshot immediately.
- If no Store data is available yet, the Client sends a `request_snapshot` command to the Host relay.
- The Client then retries Cloud pull several times while the Host processes the request and publishes a fresh `restore_snapshot`.
- Provisioning is marked complete only after Store data is actually pulled/restored.

This separates:
- Pairing consumed / device registered
- Initial Store data downloaded / applied
