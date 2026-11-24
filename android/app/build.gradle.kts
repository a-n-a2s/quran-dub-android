plugins {
    id("com.android.application")
    // يوم 5: Built-in Kotlin تبع AGP 9 (بدل plugin الـ Kotlin، تحذير Flutter).
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
        minSdk = 24
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
        // Flutter ما بيحط abiFilters على مكتبات الـ plugins بالـ debug.
        variant.packaging.jniLibs.excludes.addAll(listOf("**/x86_64/**", "**/x86/**"))
    }
}

flutter {
    source = "../.."
}

// يوم 8: Media3 (Transformer للتصدير + ExoPlayer تبع video_player) لازم كلها
// نفس النسخة، وإلا Gradle بياخد أعلى نسخة لكل وحدة لحالها وبيصير خلط.
val media3Version = "1.9.2"
configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.media3") {
            useVersion(media3Version)
            because("Media3 modules must share one version (day 8 export + video_player)")
        }
    }
}

dependencies {
    // يوم 6: FileProvider (مشاركة ملف الكاميرا مع تطبيق الكاميرا) +
    // ActivityCompat/ContextCompat (صلاحيات CAMERA/RECORD_AUDIO وقت الحاجة).
    // الطبقة فعلياً موجودة ضمن اعتماديات محرك Flutter، بس بنثبّتها هون
    // بشكل مباشر عشان ما نعتمد على ترتيب تبعيات غير مضمون.
    implementation("androidx.core:core-ktx:1.13.1")
    // يوم 8: تصدير الفيديو والنص محروق فيه (H.264 + AAC بـ MP4، overlay بـ GPU).
    // نفس نمط الأيام 4–6: dependency مباشرة بدون plugin Flutter. النسخة 1.9.2 =
    // نفس ExoPlayer تبع video_player_android، عشان كل وحدات Media3 بالتطبيق
    // تكون نسخة وحدة (فوق: resolutionStrategy). آخر stable هو 1.11.1، بس الخلط
    // بين نسختين من Media3 بالـ classpath ممكن يكسر وقت التشغيل.
    implementation("androidx.media3:media3-transformer:$media3Version")
    implementation("androidx.media3:media3-effect:$media3Version")
    implementation("androidx.media3:media3-common:$media3Version")
}
