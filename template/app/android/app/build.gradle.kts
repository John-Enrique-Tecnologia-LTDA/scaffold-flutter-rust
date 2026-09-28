import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "{= android_id =}"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "{= android_id =}"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // O id do app do Discord (o mesmo DISCORD_CLIENT_ID do servidor): a volta da autorização
        // feita no app do Discord chega pelo esquema `discord-{id}:` (AndroidManifest.xml). Vem de
        // `-PdiscordClientId=` ou de android/gradle.properties.
        manifestPlaceholders["discordClientId"] = (project.findProperty("discordClientId") as String?) ?: "0"
    }

    // A chave de release fica fora do repositório (android/key.properties aponta para ela; o
    // padrão é ~/.config/{= name =}/android-release.properties). Sem ela, o release sai com a chave
    // de debug, que serve para testar mas não abre os links dos emails (o assetlinks.json do
    // domínio só confia na de release).
    val keyProps = Properties().apply {
        val local = rootProject.file("key.properties")
        val home = File(System.getProperty("user.home"), ".config/{= name =}/android-release.properties")
        val file = if (local.exists()) local else home
        if (file.exists()) file.inputStream().use { load(it) }
    }
    signingConfigs {
        if (keyProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
