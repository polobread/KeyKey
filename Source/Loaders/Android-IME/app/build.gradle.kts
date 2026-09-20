import org.gradle.api.tasks.compile.JavaCompile

plugins {
    id("com.android.application")
}

val keyKeyVersionName = providers.gradleProperty("keykeyVersionName").getOrElse("1.2.9")
val keyKeyVersionCode = providers.gradleProperty("keykeyVersionCode")
    .map(String::toInt)
    .getOrElse(1_002_009)
val releaseKeystorePath = providers.environmentVariable("ANDROID_KEYSTORE_PATH")
val releaseKeystorePassword = providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = providers.environmentVariable("ANDROID_KEY_ALIAS")
val releaseKeyPassword = providers.environmentVariable("ANDROID_KEY_PASSWORD")
val releaseSigningValues = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword
)
val releaseSigningValueCount = releaseSigningValues.count { it.isPresent }
check(releaseSigningValueCount == 0 || releaseSigningValueCount == releaseSigningValues.size) {
    "ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, and " +
        "ANDROID_KEY_PASSWORD must be set together."
}
val hasReleaseSigning = releaseSigningValueCount == releaseSigningValues.size

android {
    namespace = "tw.chichi77.keykey.android"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "tw.chichi77.keykey.android"
        minSdk = 26
        targetSdk = 36
        versionCode = keyKeyVersionCode
        versionName = keyKeyVersionName

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath.get())
                storePassword = releaseKeystorePassword.get()
                keyAlias = releaseKeyAlias.get()
                keyPassword = releaseKeyPassword.get()
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets["main"].assets.directories.add("build/generated/bopomofoAssets")
    sourceSets["main"].assets.directories.add("build/generated/indexedDictionaryAssets")
}

val generateBopomofoAssets by tasks.registering(Copy::class) {
    from(layout.projectDirectory.file("../../../DataTables/bpmf-ext.cin"))
    from(layout.projectDirectory.file("../../../DataTables/bpmf-punctuations.cin"))
    into(layout.buildDirectory.dir("generated/bopomofoAssets"))
}

val categorizedCollectionDirectory =
    layout.projectDirectory.dir("../../../../DataSource/chichi77Collection")
val generatedCollectionDirectory =
    layout.buildDirectory.dir("generated/bopomofoAssets/collections")

val generateAssociatedPhraseAssets by tasks.registering(Sync::class) {
    from(layout.projectDirectory.file("../../../../DataSource/AssociatedPhraseCollectionNames.tsv")) {
        rename { "display-names.tsv" }
    }
    from(layout.projectDirectory.file("../../../../DataSource/McBopomofo/phrase.occ")) {
        rename { "McBopomofo.occ" }
    }
    from(categorizedCollectionDirectory) {
        include("phrase.*.tsv")
    }
    into(generatedCollectionDirectory)
}

val compileDictionaryCompiler by tasks.registering(JavaCompile::class) {
    source = fileTree("tools") { include("DictionaryCompiler.java") }
    classpath = files()
    destinationDirectory.set(layout.buildDirectory.dir("dictionaryCompiler/classes"))
    options.release.set(17)
}

val generatedIndexedDictionaryDirectory =
    layout.buildDirectory.dir("generated/indexedDictionaryAssets")

val generateIndexedDictionaryAssets by tasks.registering(JavaExec::class) {
    dependsOn(compileDictionaryCompiler)
    classpath = files(compileDictionaryCompiler.flatMap { it.destinationDirectory })
    mainClass.set("DictionaryCompiler")
    args(
        generatedIndexedDictionaryDirectory.get().asFile.absolutePath,
        layout.projectDirectory.file("../../../DataTables/bpmf-ext.cin").asFile.absolutePath,
        layout.projectDirectory.file("../../../DataTables/bpmf-punctuations.cin").asFile.absolutePath,
        layout.projectDirectory.file("../../../../DataSource/McBopomofo/phrase.occ").asFile.absolutePath,
        categorizedCollectionDirectory.asFile.absolutePath
    )
    inputs.files(
        layout.projectDirectory.file("../../../DataTables/bpmf-ext.cin"),
        layout.projectDirectory.file("../../../DataTables/bpmf-punctuations.cin"),
        layout.projectDirectory.file("../../../../DataSource/McBopomofo/phrase.occ"),
        categorizedCollectionDirectory.asFileTree.matching { include("phrase.*.tsv") }
    )
    outputs.dir(generatedIndexedDictionaryDirectory)
}

tasks.named("preBuild").configure {
    dependsOn(generateBopomofoAssets)
    dependsOn(generateAssociatedPhraseAssets)
    dependsOn(generateIndexedDictionaryAssets)
}

tasks.withType<Test>().configureEach {
    dependsOn(generateBopomofoAssets)
    dependsOn(generateAssociatedPhraseAssets)
    dependsOn(generateIndexedDictionaryAssets)
    systemProperty(
        "keykey.bopomofo.cin",
        layout.buildDirectory.file("generated/bopomofoAssets/bpmf-ext.cin").get().asFile.absolutePath
    )
    systemProperty(
        "keykey.bopomofo.punctuation",
        layout.buildDirectory.file("generated/bopomofoAssets/bpmf-punctuations.cin")
            .get().asFile.absolutePath
    )
    systemProperty(
        "keykey.associated.collections",
        generatedCollectionDirectory.get().asFile.absolutePath
    )
    systemProperty(
        "keykey.bopomofo.index",
        generatedIndexedDictionaryDirectory.get().file("bpmf-index.kki").asFile.absolutePath
    )
    systemProperty(
        "keykey.associated.indexes",
        generatedIndexedDictionaryDirectory.get().dir("collections").asFile.absolutePath
    )
}

dependencies {
    implementation("com.android.billingclient:billing:9.1.0")
    testImplementation("junit:junit:4.13.2")
}
