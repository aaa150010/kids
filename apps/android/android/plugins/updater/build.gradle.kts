plugins {
    id("com.android.library") version "8.7.3"
}

android {
    namespace = "xyz.lynote.kidsplayground.updater"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

}

base {
    archivesName.set("updater")
}

dependencies {
    val godotAar = providers.environmentVariable("GODOT_LIB_AAR")
        .orElse("../../build/libs/release/godot-lib.template_release.aar")
    compileOnly(files(godotAar))
}
