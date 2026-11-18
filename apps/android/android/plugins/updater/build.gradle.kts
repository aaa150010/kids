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
    compileOnly("org.godotengine:godot:4.7.2-stable")
}
