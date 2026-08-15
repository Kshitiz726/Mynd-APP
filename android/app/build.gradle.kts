plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ourmynd"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on older Android, which
        // it gets from desugaring rather than from raising minSdk. Without
        // this the build refuses outright.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.ourmynd"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // record (mic capture for voice input) needs API 23+, above Flutter's
        // default floor, so pin it here rather than let the merge fail.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Stated rather than inherited. AGP 9 turns both of these on for
            // release by default, so this block is a no-op - but the defaults
            // are invisible, and one of them already cost us a release-only
            // dead app: the resource shrinker dropped the notification icon,
            // which is looked up by name at runtime and so has no static
            // reference for it to find. What holds it in is
            // src/main/res/raw/keep.xml, three directories from here, and that
            // file only makes sense if you know shrinking runs at all.
            isMinifyEnabled = true
            isShrinkResources = true
            // Without these rules R8 strips the generic signatures Gson needs,
            // and flutter_local_notifications cannot persist a scheduled
            // notification - so reminders silently never fired in release.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
