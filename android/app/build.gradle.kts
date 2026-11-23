plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ayahstudio.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // اسم الحزمة النهائي (قرار أنس، ملف المواصفات). ما بيتغيّر بعد أول نشر.
        applicationId = "com.ayahstudio.app"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // يوم 4 (حجم APK التجريبي بعد sherpa-onnx): بس معالجات الجوالات
            // الحقيقية (بدون x86_64 تبع المحاكي)، والمكتبات native مضغوطة جوا
            // APK. الـ release ما بيتأثر: بالنشر AAB وجوجل بلاي بتقسّم حسب
            // المعالج لحالها (أو flutter build apk --split-per-abi).
            ndk {
                abiFilters += listOf("arm64-v8a", "armeabi-v7a")
            }
        }
        release {
            // توقيع مؤقت بمفتاح debug لحد ما نجهز مفتاح release حقيقي
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// debug بس: المكتبات native مضغوطة جوا APK (أصغر للتنزيل والتجربة).
androidComponents {
    onVariants(selector().withBuildType("debug")) { variant ->
        variant.packaging.jniLibs.useLegacyPackaging.set(true)
    }
}

kotlin {
    jvmToolchain(17)
}

flutter {
    source = "../.."
}
