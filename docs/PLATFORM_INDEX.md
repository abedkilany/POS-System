# Platform, Resource, and Configuration File Index

This catalog documents checked-in and non-ignored platform scaffolding and bundled resources. Flutter-generated build output, dependency caches, and ignored local files are intentionally excluded.
For Dart application and test files, use [FILE_INDEX.md](FILE_INDEX.md). For directory responsibilities, use [PROJECT_MAP.md](PROJECT_MAP.md).

## Documentation map

| File | Responsibility |
| --- | --- |
| [`README.md`](../README.md) | Canonical project overview, runtime architecture, and durable business rules. |
| [`AGENTS.md`](../AGENTS.md) | Repository-specific coding-agent context, task routing, and focused-reading rules. |
| [`PROJECT_MAP.md`](../docs/PROJECT_MAP.md) | Directory ownership, architecture path, feature map, and navigation guidance. |
| [`FILE_INDEX.md`](../docs/FILE_INDEX.md) | Generated searchable index of source and test files, declarations, and test cases. |
| [`PLATFORM_INDEX.md`](../docs/PLATFORM_INDEX.md) | Generated index of platform scaffolding, configuration, and bundled resources. |

## Root project configuration

| File | Responsibility |
| --- | --- |
| [`.gitignore`](../.gitignore) | Git ignore policy for local files, secrets, caches, and build output. |
| [`.metadata`](../.metadata) | Flutter project metadata used when managing platform scaffolds. |
| [`analysis_options.yaml`](../analysis_options.yaml) | Dart analyzer and lint policy. |
| [`dart_test.yaml`](../dart_test.yaml) | Default Dart test runner configuration. |
| [`package.json`](../package.json) | Node API package metadata, scripts, and dependencies. |
| [`package-lock.json`](../package-lock.json) | Resolved npm dependency lockfile. |
| [`pubspec.yaml`](../pubspec.yaml) | Flutter package metadata, dependencies, assets, and fonts. |
| [`pubspec.lock`](../pubspec.lock) | Resolved Dart/Flutter dependency lockfile. |

## `.github/workflows/`

| File | Responsibility |
| --- | --- |
| [`deploy-vps.yml`](../.github/workflows/deploy-vps.yml) | GitHub Actions workflow for `deploy vps`. |
| [`quality.yml`](../.github/workflows/quality.yml) | GitHub Actions workflow for `quality`. |

## `android/`

| File | Responsibility |
| --- | --- |
| [`.gitignore`](../android/.gitignore) | Ignore rules for generated and local `android` files. |
| [`build.gradle.kts`](../android/build.gradle.kts) | Gradle build configuration for `android`. |
| [`gradle.properties`](../android/gradle.properties) | Gradle/Android build properties for this platform project. |
| [`key.properties.example`](../android/key.properties.example) | Example Android signing properties; contains placeholders, not signing secrets. |
| [`settings.gradle.kts`](../android/settings.gradle.kts) | Gradle build configuration for `android`. |

## `android/app/`

| File | Responsibility |
| --- | --- |
| [`build.gradle.kts`](../android/app/build.gradle.kts) | Gradle build configuration for `android/app`. |
| [`proguard-rules.pro`](../android/app/proguard-rules.pro) | Android R8/ProGuard keep and obfuscation rules. |

## `android/app/src/debug/`

| File | Responsibility |
| --- | --- |
| [`AndroidManifest.xml`](../android/app/src/debug/AndroidManifest.xml) | Android manifest for the Android build variant: package, permissions, and components. |

## `android/app/src/main/`

| File | Responsibility |
| --- | --- |
| [`AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml) | Android manifest for the main app: package, permissions, and components. |

## `android/app/src/main/kotlin/com/kilany/ventio/`

| File | Responsibility |
| --- | --- |
| [`MainActivity.kt`](../android/app/src/main/kotlin/com/kilany/ventio/MainActivity.kt) | Android Flutter activity entry point. |

## `android/app/src/main/res/drawable/`

| File | Responsibility |
| --- | --- |
| [`launch_background.xml`](../android/app/src/main/res/drawable/launch_background.xml) | Native platform resource, launch UI, or component configuration. |

## `android/app/src/main/res/drawable-v21/`

| File | Responsibility |
| --- | --- |
| [`launch_background.xml`](../android/app/src/main/res/drawable-v21/launch_background.xml) | Native platform resource, launch UI, or component configuration. |

## `android/app/src/main/res/mipmap-hdpi/`

| File | Responsibility |
| --- | --- |
| [`ic_launcher.png`](../android/app/src/main/res/mipmap-hdpi/ic_launcher.png) | Android launcher icon image for the app's adaptive icon resource. |

## `android/app/src/main/res/mipmap-mdpi/`

| File | Responsibility |
| --- | --- |
| [`ic_launcher.png`](../android/app/src/main/res/mipmap-mdpi/ic_launcher.png) | Android launcher icon image for the app's adaptive icon resource. |

## `android/app/src/main/res/mipmap-xhdpi/`

| File | Responsibility |
| --- | --- |
| [`ic_launcher.png`](../android/app/src/main/res/mipmap-xhdpi/ic_launcher.png) | Android launcher icon image for the app's adaptive icon resource. |

## `android/app/src/main/res/mipmap-xxhdpi/`

| File | Responsibility |
| --- | --- |
| [`ic_launcher.png`](../android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png) | Android launcher icon image for the app's adaptive icon resource. |

## `android/app/src/main/res/mipmap-xxxhdpi/`

| File | Responsibility |
| --- | --- |
| [`ic_launcher.png`](../android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png) | Android launcher icon image for the app's adaptive icon resource. |

## `android/app/src/main/res/values/`

| File | Responsibility |
| --- | --- |
| [`styles.xml`](../android/app/src/main/res/values/styles.xml) | Native platform resource, launch UI, or component configuration. |

## `android/app/src/main/res/values-night/`

| File | Responsibility |
| --- | --- |
| [`styles.xml`](../android/app/src/main/res/values-night/styles.xml) | Native platform resource, launch UI, or component configuration. |

## `android/app/src/profile/`

| File | Responsibility |
| --- | --- |
| [`AndroidManifest.xml`](../android/app/src/profile/AndroidManifest.xml) | Android manifest for the Android build variant: package, permissions, and components. |

## `android/gradle/wrapper/`

| File | Responsibility |
| --- | --- |
| [`gradle-wrapper.properties`](../android/gradle/wrapper/gradle-wrapper.properties) | Gradle/Android build properties for this platform project. |

## `assets/branding/`

| File | Responsibility |
| --- | --- |
| [`ventio_app_icon_1024.png`](../assets/branding/ventio_app_icon_1024.png) | Ventio branding image: `ventio_app_icon_1024`. |
| [`ventio_symbol_transparent.png`](../assets/branding/ventio_symbol_transparent.png) | Ventio branding image: `ventio_symbol_transparent`. |
| [`ventio_wordmark_dark.png`](../assets/branding/ventio_wordmark_dark.png) | Ventio branding image: `ventio_wordmark_dark`. |
| [`ventio_wordmark_transparent.png`](../assets/branding/ventio_wordmark_transparent.png) | Ventio branding image: `ventio_wordmark_transparent`. |

## `assets/fonts/`

| File | Responsibility |
| --- | --- |
| [`DejaVuSans-Bold.ttf`](../assets/fonts/DejaVuSans-Bold.ttf) | Bundled font face `DejaVuSans-Bold`. |
| [`DejaVuSans.ttf`](../assets/fonts/DejaVuSans.ttf) | Bundled font face `DejaVuSans`. |
| [`Roboto-Medium.ttf`](../assets/fonts/Roboto-Medium.ttf) | Bundled font face `Roboto-Medium`. |
| [`Roboto-Regular.ttf`](../assets/fonts/Roboto-Regular.ttf) | Bundled font face `Roboto-Regular`. |
| [`Tahoma-Bold.ttf`](../assets/fonts/Tahoma-Bold.ttf) | Bundled font face `Tahoma-Bold`. |
| [`Tahoma.ttf`](../assets/fonts/Tahoma.ttf) | Bundled font face `Tahoma`. |

## `assets/sounds/`

| File | Responsibility |
| --- | --- |
| [`beep.wav`](../assets/sounds/beep.wav) | UI audio asset: `beep` sound. |
| [`error.wav`](../assets/sounds/error.wav) | UI audio asset: `error` sound. |

## `assets/translations/`

| File | Responsibility |
| --- | --- |
| [`ar.json`](../assets/translations/ar.json) | Localized UI text for the `ar` locale. |
| [`en.json`](../assets/translations/en.json) | Localized UI text for the `en` locale. |
| [`fr.json`](../assets/translations/fr.json) | Localized UI text for the `fr` locale. |

## `installer/`

| File | Responsibility |
| --- | --- |
| [`ventio.iss`](../installer/ventio.iss) | Inno Setup recipe for packaging the Windows application installer. |

## `ios/`

| File | Responsibility |
| --- | --- |
| [`.gitignore`](../ios/.gitignore) | Ignore rules for generated and local `ios` files. |

## `ios/Flutter/`

| File | Responsibility |
| --- | --- |
| [`AppFrameworkInfo.plist`](../ios/Flutter/AppFrameworkInfo.plist) | Apple-platform bundle, build, or signing metadata. |
| [`Debug.xcconfig`](../ios/Flutter/Debug.xcconfig) | Xcode/Flutter build configuration. |
| [`Release.xcconfig`](../ios/Flutter/Release.xcconfig) | Xcode/Flutter build configuration. |

## `ios/Runner/`

| File | Responsibility |
| --- | --- |
| [`AppDelegate.swift`](../ios/Runner/AppDelegate.swift) | Apple-platform Flutter application bootstrap. |
| [`Info.plist`](../ios/Runner/Info.plist) | Apple-platform bundle, build, or signing metadata. |
| [`Runner-Bridging-Header.h`](../ios/Runner/Runner-Bridging-Header.h) | Native Apple-platform source or plugin bridge for `ios/Runner`. |
| [`SceneDelegate.swift`](../ios/Runner/SceneDelegate.swift) | Native Apple-platform source or plugin bridge for `ios/Runner`. |

## `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

| File | Responsibility |
| --- | --- |
| [`Contents.json`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json) | Platform resource catalog or configuration. |
| [`Icon-App-1024x1024@1x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-20x20@1x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-20x20@2x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-20x20@3x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-29x29@1x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-29x29@2x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-29x29@3x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-40x40@1x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-40x40@2x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-40x40@3x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-60x60@2x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-60x60@3x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-76x76@1x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-76x76@2x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png) | Platform app icon or bundled image resource. |
| [`Icon-App-83.5x83.5@2x.png`](../ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png) | Platform app icon or bundled image resource. |

## `ios/Runner/Assets.xcassets/LaunchImage.imageset/`

| File | Responsibility |
| --- | --- |
| [`Contents.json`](../ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json) | Platform resource catalog or configuration. |
| [`LaunchImage.png`](../ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png) | Apple launch-screen image asset. |
| [`LaunchImage@2x.png`](../ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png) | Apple launch-screen image asset. |
| [`LaunchImage@3x.png`](../ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png) | Apple launch-screen image asset. |
| [`README.md`](../ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md) | Apple launch image asset-catalog instructions and required image variants. |

## `ios/Runner/Base.lproj/`

| File | Responsibility |
| --- | --- |
| [`LaunchScreen.storyboard`](../ios/Runner/Base.lproj/LaunchScreen.storyboard) | Native platform resource, launch UI, or component configuration. |
| [`Main.storyboard`](../ios/Runner/Base.lproj/Main.storyboard) | Native platform resource, launch UI, or component configuration. |

## `ios/Runner.xcodeproj/`

| File | Responsibility |
| --- | --- |
| [`project.pbxproj`](../ios/Runner.xcodeproj/project.pbxproj) | Xcode project targets, build settings, and file membership. |

## `ios/Runner.xcodeproj/project.xcworkspace/`

| File | Responsibility |
| --- | --- |
| [`contents.xcworkspacedata`](../ios/Runner.xcodeproj/project.xcworkspace/contents.xcworkspacedata) | Xcode workspace membership configuration. |

## `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/`

| File | Responsibility |
| --- | --- |
| [`IDEWorkspaceChecks.plist`](../ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist) | Apple-platform bundle, build, or signing metadata. |
| [`WorkspaceSettings.xcsettings`](../ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings) | Xcode workspace or project user settings. |

## `ios/Runner.xcodeproj/xcshareddata/xcschemes/`

| File | Responsibility |
| --- | --- |
| [`Runner.xcscheme`](../ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme) | Xcode build and launch scheme. |

## `ios/Runner.xcworkspace/`

| File | Responsibility |
| --- | --- |
| [`contents.xcworkspacedata`](../ios/Runner.xcworkspace/contents.xcworkspacedata) | Xcode workspace membership configuration. |

## `ios/Runner.xcworkspace/xcshareddata/`

| File | Responsibility |
| --- | --- |
| [`IDEWorkspaceChecks.plist`](../ios/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist) | Apple-platform bundle, build, or signing metadata. |
| [`WorkspaceSettings.xcsettings`](../ios/Runner.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings) | Xcode workspace or project user settings. |

## `ios/RunnerTests/`

| File | Responsibility |
| --- | --- |
| [`RunnerTests.swift`](../ios/RunnerTests/RunnerTests.swift) | Native Apple-platform source or plugin bridge for `ios/RunnerTests`. |

## `linux/`

| File | Responsibility |
| --- | --- |
| [`.gitignore`](../linux/.gitignore) | Ignore rules for generated and local `linux` files. |
| [`CMakeLists.txt`](../linux/CMakeLists.txt) | CMake build configuration for `linux`. |

## `linux/flutter/`

| File | Responsibility |
| --- | --- |
| [`CMakeLists.txt`](../linux/flutter/CMakeLists.txt) | CMake build configuration for `linux/flutter`. |
| [`generated_plugin_registrant.cc`](../linux/flutter/generated_plugin_registrant.cc) | Generated native plugin registration; do not edit by hand. |
| [`generated_plugin_registrant.h`](../linux/flutter/generated_plugin_registrant.h) | Generated native plugin registration; do not edit by hand. |
| [`generated_plugins.cmake`](../linux/flutter/generated_plugins.cmake) | Generated Flutter plugin registration for the native desktop runner. |

## `linux/runner/`

| File | Responsibility |
| --- | --- |
| [`CMakeLists.txt`](../linux/runner/CMakeLists.txt) | CMake build configuration for `linux/runner`. |
| [`main.cc`](../linux/runner/main.cc) | Native desktop runner entry point. |
| [`my_application.cc`](../linux/runner/my_application.cc) | Native desktop runner or plugin implementation for `linux/runner`. |
| [`my_application.h`](../linux/runner/my_application.h) | Native desktop runner or plugin implementation for `linux/runner`. |

## `macos/`

| File | Responsibility |
| --- | --- |
| [`.gitignore`](../macos/.gitignore) | Ignore rules for generated and local `macos` files. |

## `macos/Flutter/`

| File | Responsibility |
| --- | --- |
| [`Flutter-Debug.xcconfig`](../macos/Flutter/Flutter-Debug.xcconfig) | Xcode/Flutter build configuration. |
| [`Flutter-Release.xcconfig`](../macos/Flutter/Flutter-Release.xcconfig) | Xcode/Flutter build configuration. |
| [`GeneratedPluginRegistrant.swift`](../macos/Flutter/GeneratedPluginRegistrant.swift) | Generated native plugin registration; do not edit by hand. |

## `macos/Runner/`

| File | Responsibility |
| --- | --- |
| [`AppDelegate.swift`](../macos/Runner/AppDelegate.swift) | Apple-platform Flutter application bootstrap. |
| [`DebugProfile.entitlements`](../macos/Runner/DebugProfile.entitlements) | Apple-platform app capabilities and signing entitlements. |
| [`Info.plist`](../macos/Runner/Info.plist) | Apple-platform bundle, build, or signing metadata. |
| [`MainFlutterWindow.swift`](../macos/Runner/MainFlutterWindow.swift) | Native Apple-platform source or plugin bridge for `macos/Runner`. |
| [`Release.entitlements`](../macos/Runner/Release.entitlements) | Apple-platform app capabilities and signing entitlements. |

## `macos/Runner/Assets.xcassets/AppIcon.appiconset/`

| File | Responsibility |
| --- | --- |
| [`app_icon_1024.png`](../macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png) | Platform app icon or bundled image resource. |
| [`app_icon_128.png`](../macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png) | Platform app icon or bundled image resource. |
| [`app_icon_16.png`](../macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png) | Platform app icon or bundled image resource. |
| [`app_icon_256.png`](../macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png) | Platform app icon or bundled image resource. |
| [`app_icon_32.png`](../macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png) | Platform app icon or bundled image resource. |
| [`app_icon_512.png`](../macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png) | Platform app icon or bundled image resource. |
| [`app_icon_64.png`](../macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png) | Platform app icon or bundled image resource. |
| [`Contents.json`](../macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json) | Platform resource catalog or configuration. |

## `macos/Runner/Base.lproj/`

| File | Responsibility |
| --- | --- |
| [`MainMenu.xib`](../macos/Runner/Base.lproj/MainMenu.xib) | Native platform resource, launch UI, or component configuration. |

## `macos/Runner/Configs/`

| File | Responsibility |
| --- | --- |
| [`AppInfo.xcconfig`](../macos/Runner/Configs/AppInfo.xcconfig) | Xcode/Flutter build configuration. |
| [`Debug.xcconfig`](../macos/Runner/Configs/Debug.xcconfig) | Xcode/Flutter build configuration. |
| [`Release.xcconfig`](../macos/Runner/Configs/Release.xcconfig) | Xcode/Flutter build configuration. |
| [`Warnings.xcconfig`](../macos/Runner/Configs/Warnings.xcconfig) | Xcode/Flutter build configuration. |

## `macos/Runner.xcodeproj/`

| File | Responsibility |
| --- | --- |
| [`project.pbxproj`](../macos/Runner.xcodeproj/project.pbxproj) | Xcode project targets, build settings, and file membership. |

## `macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/`

| File | Responsibility |
| --- | --- |
| [`IDEWorkspaceChecks.plist`](../macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist) | Apple-platform bundle, build, or signing metadata. |

## `macos/Runner.xcodeproj/xcshareddata/xcschemes/`

| File | Responsibility |
| --- | --- |
| [`Runner.xcscheme`](../macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme) | Xcode build and launch scheme. |

## `macos/Runner.xcworkspace/`

| File | Responsibility |
| --- | --- |
| [`contents.xcworkspacedata`](../macos/Runner.xcworkspace/contents.xcworkspacedata) | Xcode workspace membership configuration. |

## `macos/Runner.xcworkspace/xcshareddata/`

| File | Responsibility |
| --- | --- |
| [`IDEWorkspaceChecks.plist`](../macos/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist) | Apple-platform bundle, build, or signing metadata. |

## `macos/RunnerTests/`

| File | Responsibility |
| --- | --- |
| [`RunnerTests.swift`](../macos/RunnerTests/RunnerTests.swift) | Native Apple-platform source or plugin bridge for `macos/RunnerTests`. |

## `web/`

| File | Responsibility |
| --- | --- |
| [`favicon.png`](../web/favicon.png) | Platform app icon or bundled image resource. |
| [`index.html`](../web/index.html) | Web app bootstrap and browser integration. |
| [`manifest.json`](../web/manifest.json) | Installable web app metadata or web resource manifest. |

## `web/icons/`

| File | Responsibility |
| --- | --- |
| [`Icon-192.png`](../web/icons/Icon-192.png) | Platform app icon or bundled image resource. |
| [`Icon-512.png`](../web/icons/Icon-512.png) | Platform app icon or bundled image resource. |
| [`Icon-maskable-192.png`](../web/icons/Icon-maskable-192.png) | Platform app icon or bundled image resource. |
| [`Icon-maskable-512.png`](../web/icons/Icon-maskable-512.png) | Platform app icon or bundled image resource. |

## `web/releases/`

| File | Responsibility |
| --- | --- |
| [`latest.json`](../web/releases/latest.json) | Installable web app metadata or web resource manifest. |

## `web/releases/windows/`

| File | Responsibility |
| --- | --- |
| [`index.json`](../web/releases/windows/index.json) | Installable web app metadata or web resource manifest. |
| [`VentioSetup-1.0.64-build64.exe`](../web/releases/windows/VentioSetup-1.0.64-build64.exe) | Published Windows installer download bundled with web release files. |

## `windows/`

| File | Responsibility |
| --- | --- |
| [`.gitignore`](../windows/.gitignore) | Ignore rules for generated and local `windows` files. |
| [`CMakeLists.txt`](../windows/CMakeLists.txt) | CMake build configuration for `windows`. |

## `windows/flutter/`

| File | Responsibility |
| --- | --- |
| [`CMakeLists.txt`](../windows/flutter/CMakeLists.txt) | CMake build configuration for `windows/flutter`. |
| [`generated_plugin_registrant.cc`](../windows/flutter/generated_plugin_registrant.cc) | Generated native plugin registration; do not edit by hand. |
| [`generated_plugin_registrant.h`](../windows/flutter/generated_plugin_registrant.h) | Generated native plugin registration; do not edit by hand. |
| [`generated_plugins.cmake`](../windows/flutter/generated_plugins.cmake) | Generated Flutter plugin registration for the native desktop runner. |

## `windows/runner/`

| File | Responsibility |
| --- | --- |
| [`CMakeLists.txt`](../windows/runner/CMakeLists.txt) | CMake build configuration for `windows/runner`. |
| [`flutter_window.cpp`](../windows/runner/flutter_window.cpp) | Native desktop runner or plugin implementation for `windows/runner`. |
| [`flutter_window.h`](../windows/runner/flutter_window.h) | Native desktop runner or plugin implementation for `windows/runner`. |
| [`main.cpp`](../windows/runner/main.cpp) | Native desktop runner entry point. |
| [`resource.h`](../windows/runner/resource.h) | Native desktop runner or plugin implementation for `windows/runner`. |
| [`runner.exe.manifest`](../windows/runner/runner.exe.manifest) | Native desktop app resource or application manifest. |
| [`Runner.rc`](../windows/runner/Runner.rc) | Native desktop app resource or application manifest. |
| [`utils.cpp`](../windows/runner/utils.cpp) | Native desktop runner or plugin implementation for `windows/runner`. |
| [`utils.h`](../windows/runner/utils.h) | Native desktop runner or plugin implementation for `windows/runner`. |
| [`win32_window.cpp`](../windows/runner/win32_window.cpp) | Native desktop runner or plugin implementation for `windows/runner`. |
| [`win32_window.h`](../windows/runner/win32_window.h) | Native desktop runner or plugin implementation for `windows/runner`. |

## `windows/runner/resources/`

| File | Responsibility |
| --- | --- |
| [`app_icon.ico`](../windows/runner/resources/app_icon.ico) | Native desktop app resource or application manifest. |
