# Sync fixes applied

Applied requested Sync fixes 1, 2, 3, and 6:

1. Host Sync status/actions now handle LAN and Cloud independently where both are enabled.
2. Sync/setup messages use in-page status updates and friendlier user-facing errors instead of technical exception text for the modified flows.
3. LAN pairing controls use a LAN icon and explicit Show/Hide LAN Code and Show/Hide Cloud Code labels.
6. Cloud device pairing remains successful even if initial data download/snapshot retrieval fails after registration; post-registration issues are treated as initial data waiting/retry states.

Note: Flutter/Dart tools were not available in this environment, so run `flutter analyze` locally.
