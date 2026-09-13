import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// リリース署名用のキーストア情報（android/key.properties、gitignore済み・非公開）。
// 実際のストア提出には key.properties（または環境変数）を用意する必要があり、
// 不足している場合はリリースビルドを明示的に停止します。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseSigningRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
fun getSigningValue(keys: List<String>): String? {
    val prop = keys.firstNotNullOfOrNull { key ->
        val envValue = System.getenv(key)
        if (!envValue.isNullOrBlank()) envValue else null
    }
    if (prop != null) return prop
    return keys.firstNotNullOfOrNull { key ->
        val fileValue = keystoreProperties[key]?.toString()
        if (!fileValue.isNullOrBlank()) fileValue else null
    }
}

val releaseStoreFile = getSigningValue(listOf("MINDSTOCK_KEY_STORE_FILE", "MINDSTOCK_KEYSTORE_FILE", "storeFile"))
val releaseStorePassword = getSigningValue(listOf("MINDSTOCK_KEY_STORE_PASSWORD", "MINDSTOCK_KEYSTORE_PASSWORD", "storePassword"))
val releaseKeyPassword = getSigningValue(listOf("MINDSTOCK_KEY_PASSWORD", "keyPassword"))
val releaseKeyAlias = getSigningValue(listOf("MINDSTOCK_KEY_ALIAS", "keyAlias"))
val releaseSigningComplete = releaseStoreFile != null &&
    releaseStorePassword != null &&
    releaseKeyPassword != null &&
    releaseKeyAlias != null
val releaseSigningMissingMessage = """
Release signing情報が不足しています。
APPのPlay提出に使うリリース署名を行うには、次のいずれかを設定してください。
1) key.properties（git管理外）に keyAlias / keyPassword / storePassword / storeFile を記載
2) 環境変数 MINDSTOCK_KEY_ALIAS, MINDSTOCK_KEY_PASSWORD,
   MINDSTOCK_KEY_STORE_PASSWORD, MINDSTOCK_KEY_STORE_FILE を設定
""".trimIndent()

android {
    namespace = "com.kanenosu.mindstock"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kanenosu.mindstock"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // recordパッケージ（音声入力）がAndroid 6.0 (API 23)以上を要求する
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningComplete) {
            create("release") {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = file(releaseStoreFile)
                storePassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            // リリースビルドをデバッグ鍵で署名して提出する事故を防ぐため、
            // 署名情報が無い場合は明示的に停止させる。
            signingConfig = if (releaseSigningComplete) {
                signingConfigs.getByName("release")
            } else if (releaseSigningRequested) {
                throw GradleException(releaseSigningMissingMessage)
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
