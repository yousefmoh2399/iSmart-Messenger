-dontwarn javax.annotation.**
-dontwarn okio.**
-dontwarn okhttp3.**
-keep class javax.annotation.** { *; }
-keep class okio.** { *; }
-keep class okhttp3.** { *; }
-keep class kotlin.Metadata { *; }

# OpenCV Java & JNI keep rules
-keep class org.opencv.** { *; }
-keepclassmembers class org.opencv.** { *; }
-dontwarn org.opencv.**

# Native application code & scanner
-keep class com.ismart.messenger.** { *; }
-keepclassmembers class com.ismart.messenger.** { *; }

# Keep native methods across all classes
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter & plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.**

# CameraX
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
