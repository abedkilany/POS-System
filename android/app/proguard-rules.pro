# Ventio release rules
# Keep Flutter embedding classes used by generated code.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter embedding contains optional Play Store deferred-component hooks.
# This app does not use deferred components, so suppress R8 warnings for the
# optional Play Core classes that are not packaged in a regular APK build.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# mobile_scanner uses native Android CameraX and ML Kit Barcode Scanning.
# Keep these classes from being stripped/renamed by R8; otherwise some devices
# can start the scanner with a native null-object crash instead of a preview.
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class androidx.camera.** { *; }
-keep class androidx.camera.camera2.** { *; }
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.lifecycle.** { *; }
-keep class androidx.camera.view.** { *; }
-keep class androidx.lifecycle.** { *; }
-keep class com.google.common.util.concurrent.** { *; }

-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**
-dontwarn com.google.android.gms.internal.mlkit_vision_common.**
-dontwarn androidx.camera.**
-dontwarn com.google.common.util.concurrent.**
