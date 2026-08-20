# R8/ProGuard rules for release builds.
#
# Why this file exists: without it, every SCHEDULED notification failed in
# release with `PlatformException(error, Missing type parameter.)` while an
# immediate one worked fine. flutter_local_notifications persists each pending
# notification as JSON through Gson, and Gson's TypeToken reads the *generic*
# type signature at runtime. R8 strips those signatures by default, so
# `TypeToken<ArrayList<NotificationDetails>>` decayed to a raw type and Gson
# refused it. Nothing in the Dart code was wrong - reminders simply could never
# be stored, so none of them ever fired, on any release build.

# Gson needs generic signatures and annotations intact.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# The plugin's model classes are serialised by name; renaming them breaks the
# stored payload as surely as dropping the signature does.
-keep class com.dexterous.** { *; }

# Gson's own reflective machinery.
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn sun.misc.**
