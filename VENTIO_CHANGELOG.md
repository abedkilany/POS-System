# Ventio build notes

Implemented in this package:

- Rebranded app name from Store Manager Pro to Ventio across Android, iOS, Web, macOS, Windows, and Linux metadata where applicable.
- Updated Android application ID / namespace to `com.kilany.ventio`.
- Added generated Ventio logo assets under `assets/branding/`.
- Replaced default launcher icons on Android, iOS, macOS, and Web with the Ventio V + speed-lines symbol.
- Updated app theme seed colors toward the Ventio blue/purple visual identity.
- Removed default credential hints from UI translations.
- Added first-run admin setup: fresh installs must create a private admin username and password before entering the app.
- Added `flutter_secure_storage` and migrated the Hive encryption key from SharedPreferences to secure storage while keeping the existing Hive box name for update compatibility.
- Added Android `key.properties.example` and release signing config support. If `android/key.properties` is not present, release builds still fall back to debug signing for local testing only.

Important:

- Run `flutter pub get` before building because a new dependency was added.
- For Google Play production upload, create a real release keystore and fill `android/key.properties` from the example file.
- I could not run `flutter analyze` or a release build in this environment because Flutter/Dart is not installed here.
