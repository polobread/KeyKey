plugins {
    id("com.android.application")
}

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
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets["main"].assets.directories.add("build/generated/bopomofoAssets")
}

val generateBopomofoAssets by tasks.registering(Copy::class) {
    from(layout.projectDirectory.file("../../../DataTables/bpmf-ext.cin"))
    from(layout.projectDirectory.file("../../../DataTables/bpmf-punctuations.cin"))
    into(layout.buildDirectory.dir("generated/bopomofoAssets"))
}

val privateCollectionDirectory = layout.projectDirectory.dir("../../../../../chichi77Collection")
val generatedCollectionDirectory =
    layout.buildDirectory.dir("generated/bopomofoAssets/collections")

val generateAssociatedPhraseAssets by tasks.registering(Sync::class) {
    from(layout.projectDirectory.file("../../../../DataSource/AssociatedPhraseCollectionNames.tsv")) {
        rename { "display-names.tsv" }
    }
    from(layout.projectDirectory.file("../../../../DataSource/McBopomofo/phrase.occ")) {
        rename { "McBopomofo.occ" }
    }
    from(privateCollectionDirectory) {
        include("phrase.*.tsv")
    }
    into(generatedCollectionDirectory)
}

tasks.named("preBuild").configure {
    dependsOn(generateBopomofoAssets)
    dependsOn(generateAssociatedPhraseAssets)
}

tasks.withType<Test>().configureEach {
    dependsOn(generateBopomofoAssets)
    dependsOn(generateAssociatedPhraseAssets)
    systemProperty(
        "keykey.bopomofo.cin",
        layout.buildDirectory.file("generated/bopomofoAssets/bpmf-ext.cin").get().asFile.absolutePath
    )
    systemProperty(
        "keykey.associated.collections",
        generatedCollectionDirectory.get().asFile.absolutePath
    )
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
