import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "space.kpax.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "space.kpax.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "app_name", "K-Pax")
        manifestPlaceholders["deepLinkScheme"] = "kpax"
    }

    flavorDimensions += "brand"
    productFlavors {
        create("kpax") {
            dimension = "brand"
            applicationId = "space.kpax.app"
            resValue("string", "app_name", "K-Pax")
            manifestPlaceholders["deepLinkScheme"] = "kpax"
        }
        create("xplm") {
            dimension = "brand"
            applicationId = "online.xplm.app"
            resValue("string", "app_name", "X-Plm")
            manifestPlaceholders["deepLinkScheme"] = "xplm"
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
            )
        }
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            // Emulator (x86_64) + device (arm64) for local visual checks.
            ndk {
                abiFilters.clear()
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            // Store/device APKs stay arm64-only.
            ndk {
                abiFilters.clear()
                abiFilters += listOf("arm64-v8a")
            }
            packaging {
                jniLibs {
                    excludes += setOf("lib/x86_64/**")
                }
            }
        }
    }
}

flutter {
    source = "../.."
}
