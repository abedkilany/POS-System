# Windows flutter test fix

If `flutter test` stops at `ventio_widget_test.dart` with errors such as:

- `PathNotFoundException: Deletion failed ... flutter_test_listener...`
- `Cannot open file ... flutter_test_compiler... output.dill`

run tests through the Windows script:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\run_tests_windows.ps1
```

The script forces Flutter's `TEMP`/`TMP` directories into `.dart_tool\flutter_test_temp` inside the project, then runs:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test -r expanded --concurrency=1
```

The tests also store Hive test data under `.dart_tool\ventio_test_data` instead of Windows `%TEMP%`, and they no longer delete Hive files during test finalization. This avoids Windows cleanup/file-lock races while Flutter is finalizing widget tests.
