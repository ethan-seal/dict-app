# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.kts.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Keep JNI bindings
-keep class org.example.dictapp.DictCore { *; }

# Data classes (SearchResult, FullDefinition, etc.) do NOT need -keep rules.
# They use kotlinx.serialization which generates serializers at compile time,
# so R8 can freely obfuscate field names without breaking deserialization.

# Keep zstd-jni classes (fields accessed via JNI from native code)
-keep class com.github.luben.zstd.** { *; }

# Keep Apache Commons Compress zstd wrapper
-keep class org.apache.commons.compress.compressors.zstandard.** { *; }

# kotlinx.serialization - keep the serializer lookup infrastructure
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keepclassmembers @kotlinx.serialization.Serializable class org.example.dictapp.** {
    *** Companion;
    *** serializer(...);
    kotlinx.serialization.KSerializer $$serializer(...);
}

# Uncomment this to preserve the line number information for
# debugging stack traces.
-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile
