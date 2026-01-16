# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.kts.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Keep JNI bindings
-keep class org.example.dictapp.DictCore { *; }

# Keep data classes used for JSON deserialization
-keep class org.example.dictapp.SearchResult { *; }
-keep class org.example.dictapp.FullDefinition { *; }
-keep class org.example.dictapp.Definition { *; }
-keep class org.example.dictapp.Pronunciation { *; }
-keep class org.example.dictapp.Translation { *; }

# Keep Gson serialization
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Uncomment this to preserve the line number information for
# debugging stack traces.
-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile
