# Flutter engine + embedding.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_local_notifications persists its pending-notification cache as JSON
# via Gson, using an anonymous `TypeToken<ArrayList<NotificationDetails>>`
# subclass to recover the element type at runtime.
#
# Gson reads that type argument out of the class's `Signature` attribute. R8 in
# full mode (the AGP 8 default) discards generic signatures and merges the
# anonymous subclass unless told not to, which makes every call that touches the
# cache — `cancel`, `cancelAll`, `pendingNotificationRequests` — throw
# "TypeToken must be created with a type argument". The plugin surfaces that as
# a PlatformException, and because scheduling cancels before it schedules, the
# app silently stops scheduling anything at all in release builds.
#
# Attributes are listed in one directive: repeated `-keepattributes` lines are
# meant to accumulate, but keeping them together makes the set auditable.
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Gson's own documented rules. The `extends TypeToken` rule is the one that
# actually fixes the failure above; the rest keep serialised model fields from
# being renamed or stripped.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn sun.misc.**

# WorkManager / AlarmManager entry points invoked reflectively.
# Both plugins instantiate their Worker / BroadcastReceiver by class name from
# Android, so R8 cannot see the reference and would strip them — breaking
# background work in release builds only.
-keep class androidx.work.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
# workmanager moved from `be.tramckrijte` (0.5.x) to `dev.fluttercommunity`
# when it became a federated plugin in 0.9. Keeping the old package name only
# would have matched nothing.
-keep class dev.fluttercommunity.workmanager.** { *; }

# androidx.window probes for OEM foldable/large-screen extensions at runtime and
# degrades gracefully when they are absent, so these classes are deliberately
# not on the compile classpath. Without these rules R8 treats the dangling
# references as a hard error.
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# Speech recognition + TTS platform bridges.
-keep class com.csdcorp.speech_to_text.** { *; }

# Play Core is referenced by Flutter deferred components but not bundled.
-dontwarn com.google.android.play.core.**
