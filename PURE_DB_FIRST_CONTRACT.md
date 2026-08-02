# Pure DB-First Contract

SQLite is the only source of truth for runtime application state, business
data, and settings. SharedPreferences and legacy JSON blobs are used only for
one-time migration, backup/restore, compatibility, and tests.

Native startup must initialize the SQLite database before exposing the app as
ready. Heavy collections may hydrate lazily in production, but test stores
provide a deterministic hydration boundary before synchronous getters are
asserted.
