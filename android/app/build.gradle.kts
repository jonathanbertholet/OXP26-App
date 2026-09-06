import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

val sharedAssets by tasks.registering(Sync::class) {
    from("../../OXP/Resources") { include("catalog.json") }
    into(layout.buildDirectory.dir("generated/oxpAssets"))
}
val uploadProperties = Properties().apply {
    val localFile = rootProject.file(".secrets/upload.properties")
    if (localFile.isFile) localFile.inputStream().use { load(it) }
}
fun uploadSetting(key: String, environment: String): String? =
    providers.environmentVariable(environment).orNull?.takeIf { it.isNotBlank() }
        ?: uploadProperties.getProperty(key)?.takeIf { it.isNotBlank() }
val uploadStoreFile = uploadSetting("storeFile", "OXP_UPLOAD_STORE_FILE")
val uploadStorePassword = uploadSetting("storePassword", "OXP_UPLOAD_STORE_PASSWORD")
val uploadKeyAlias = uploadSetting("keyAlias", "OXP_UPLOAD_KEY_ALIAS")
val uploadKeyPassword = uploadSetting("keyPassword", "OXP_UPLOAD_KEY_PASSWORD")
val uploadSigningReady = listOf(uploadStoreFile, uploadStorePassword, uploadKeyAlias, uploadKeyPassword).all { it != null }

android {
    namespace = "be.oxp.app"
    compileSdk { version = release(36) { minorApiLevel = 1 } }
    defaultConfig {
        applicationId = "be.oxp.app"
        minSdk = 26
        targetSdk = 36
        versionCode = providers.gradleProperty("oxpVersionCode").orElse("1").get().toInt().also { require(it > 0) }
        versionName = providers.gradleProperty("oxpVersionName").orElse("1.0").get()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets.getByName("main").assets.srcDir("build/generated/oxpAssets")
    sourceSets.getByName("test").resources.srcDir("../../OXP/Resources")
    signingConfigs {
        if (uploadSigningReady) create("upload") {
            storeFile = rootProject.file(uploadStoreFile!!)
            storePassword = uploadStorePassword
            keyAlias = uploadKeyAlias
            keyPassword = uploadKeyPassword
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
dependencies {
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui:1.9.0")
    implementation("androidx.compose.foundation:foundation:1.9.0")
    implementation("androidx.compose.material3:material3:1.3.2")
    implementation("androidx.compose.material:material-icons-extended:1.7.8")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.0")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("io.coil-kt:coil-compose:2.7.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

tasks.named("preBuild") { dependsOn(sharedAssets) }
