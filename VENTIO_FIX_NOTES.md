# Ventio fix notes

Fixed in this package:

- Cloud Sync settings on Windows/Android now have an explicit HOST / CLIENT selector.
- Saving Cloud Sync now updates the device role to the selected value and restarts auto sync callbacks.
- Windows executable name changed to `Ventio.exe` to avoid accidentally opening an old cached `runner.exe`/`ventio.exe`.
- Windows icon resource already points to `windows/runner/resources/app_icon.ico` with the Ventio icon. If Explorer still shows Flutter icon, delete the old build folder and rebuild clean; Windows may cache executable icons.

Recommended Windows rebuild:

```powershell
flutter clean
Remove-Item -Recurse -Force build\windows -ErrorAction SilentlyContinue
flutter pub get
flutter build windows --release
```

Run:

```text
build\windows\x64\runner\Release\Ventio.exe
```
