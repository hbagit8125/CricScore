import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing key for every build, so Google sign-in recognises the app.
// Read from CRICSCORE_KEY_PROPERTIES or android/key.properties; neither the
// key nor its passwords are kept in the repository. Without them, builds
// fall back to the throwaway debug key and Google sign-in will not work.
val keyProperties = Properties().apply {
    val path = System.getenv("CRICSCORE_KEY_PROPERTIES")
        ?: rootProject.file("key.properties").path
    val f = file(path)
    if (f.exists()) FileInputStream(f).use { load(it) }
}
val hasAppKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "com.cricscore.cric_score"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.cricscore.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("app") {
            if (hasAppKey) {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeType = "pkcs12"
            }
        }
    }

    buildTypes {
        val signing = signingConfigs.getByName(if (hasAppKey) "app" else "debug")
        debug {
            signingConfig = signing
        }
        release {
            signingConfig = signing
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
