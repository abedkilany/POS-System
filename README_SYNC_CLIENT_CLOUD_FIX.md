# Client-Cloud sync fix

Fixed a deadlock in `lib/core/services/cloud_sync_service.dart`.

## Root cause
`_clientCloudHostWorkNeedsDrain()` used `store.hasOutstandingSyncWorkForTarget('cloud_host')`.
That method counts every non-synced row, including fresh `pending`, `failed`, and `rejected` rows.

On a Client-Cloud device, a new local change creates a `cloud_host` pending row. The cloud sync flow checked the drain guard before pushing, saw that row as "outstanding", and returned sync deferred. Result:

- pending changes were not sent to the Host
- pull from Host/Cloud was deferred too
- Client-Cloud looked stuck with pending changes

## Fix
The drain guard now only blocks when there are `submitted` `cloud_host` rows, meaning requests already reached Cloud and are waiting for Host confirmation.

Fresh `pending`/`failed` rows are allowed to be pushed. `rejected` rows no longer block pulling authoritative Host data.
