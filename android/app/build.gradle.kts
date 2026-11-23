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
        release {
            // توقيع مؤقت بمفتاح debug لحد ما نجهز مفتاح release حقيقي
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// يوم 4 (حجم APK التجريبي بعد sherpa-onnx): بالـ debug بس، المكتبات native
// مضغوطة جوا APK (أصغر للتنزيل والتجربة). اختيار المعالجات (arm64-v8a +
// armeabi-v7a بس، بدون x86_64 تبع المحاكي) بيصير بـ --target-platform بالـ CI،
// لأنه Flutter بيكتب abiFilters لحاله. الـ release ما بيتأثر: بالنشر AAB
// وجوجل بلاي بتقسّم حسب المعالج (أو flutter build apk --split-per-abi).
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
