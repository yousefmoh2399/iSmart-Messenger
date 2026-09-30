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

# Scanner activity, views, and native processing
-keep class com.example.mobile_app.scanner.** { *; }
-keepclassmembers class com.example.mobile_app.scanner.** { *; }
