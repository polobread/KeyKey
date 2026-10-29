import org.gradle.api.tasks.compile.JavaCompile
import org.gradle.api.tasks.Exec
import org.gradle.process.CommandLineArgumentProvider
import org.gradle.api.provider.Provider
import org.gradle.api.file.Directory
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity

plugins {
    id("com.android.application")
}

class GuanyinmaNdkArguments(
    @get:InputDirectory @get:PathSensitive(PathSensitivity.NONE)
    val directory: Provider<Directory>
) : CommandLineArgumentProvider {
    override fun asArguments(): Iterable<String> = listOf("--ndk", directory.get().asFile.absolutePath)
}

val keyKeyVersionName = providers.gradleProperty("keykeyVersionName").getOrElse("1.5.0")
val keyKeyVersionCode = providers.gradleProperty("keykeyVersionCode")
    .map(String::toInt)
    .getOrElse(1_005_000)
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
    ndkVersion = "27.2.12479018"
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
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
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86") }
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DGUANYINMA_RUST_ROOT=" + layout.buildDirectory.dir("generated/guanyinma-rust").get().asFile.absolutePath,
                    "-DANDROID_STL=c++_static",
                    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON"
                )
            }
        }
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
    sourceSets["main"].assets.directories.add("build/generated/smartMandarinAssets")
    sourceSets["main"].assets.directories.add("build/generated/guanyinmaLicenseAssets")
}

val guanyinmaCoreDirectory = layout.projectDirectory.dir("../../../Guanyinma")
val guanyinmaRustDirectory = layout.buildDirectory.dir("generated/guanyinma-rust")
val guanyinmaHostDirectory = layout.buildDirectory.dir("guanyinma-host-jni")
val guanyinmaPython = providers.environmentVariable("PYTHON3").orNull?.let { listOf(it) }
    ?: if (System.getProperty("os.name").startsWith("Windows", ignoreCase = true)) listOf("py", "-3") else listOf("python3")
val guanyinmaHostLibrary = guanyinmaHostDirectory.map { it.file(System.mapLibraryName("keykey_guanyinma")) }

val generateGuanyinmaNotices by tasks.registering(Exec::class) {
    argumentProviders.add(GuanyinmaNdkArguments(androidComponents.sdkComponents.ndkDirectory))
    commandLine(guanyinmaPython + listOf(
        guanyinmaCoreDirectory.file("tools/package-runtime-notices.py").asFile.absolutePath,
        "--output", layout.buildDirectory.file("generated/guanyinmaLicenseAssets/licenses/Guanyinma-Notices.txt").get().asFile.absolutePath
    ))
    inputs.files(guanyinmaCoreDirectory.asFileTree.matching {
        include("Cargo.toml", "Cargo.lock", "rust-toolchain.toml", "LICENSE.txt", "LICENSES/**", "tools/package-runtime-notices.py")
    })
    inputs.files(layout.projectDirectory.dir("../../../..").asFileTree.matching {
        include("LICENSE.txt", "LICENSING.md", "THIRD-PARTY-NOTICES.md", "LICENSES/**",
                "DataSource/McBopomofo/LICENSE.txt", "DataSource/AISyntheticBigram/LICENSE.txt",
                "DataSource/chichi77Collection/LICENSE.txt", "Source/Loaders/Android-IME/LICENSE.txt")
    })
    outputs.file(layout.buildDirectory.file("generated/guanyinmaLicenseAssets/licenses/Guanyinma-Notices.txt"))
}

val buildGuanyinmaAndroid by tasks.registering(Exec::class) {
    commandLine(guanyinmaPython + listOf(
        guanyinmaCoreDirectory.file("tools/build-android-core.py").asFile.absolutePath,
        "--output", guanyinmaRustDirectory.get().asFile.absolutePath, "--api", "26"
    ))
    argumentProviders.add(GuanyinmaNdkArguments(androidComponents.sdkComponents.ndkDirectory))
    inputs.files(guanyinmaCoreDirectory.asFileTree.matching {
        include("Cargo.toml", "Cargo.lock", "rust-toolchain.toml", "build.rs", "src/**", "include/**", "tools/build-android-core.py")
    })
    inputs.files(layout.projectDirectory.dir("../../../Shared").asFileTree.matching { include("Cangjie*Data.h") })
    outputs.files(listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86").map {
        guanyinmaRustDirectory.get().file("$it/libguanyinma.a")
    })
}

val buildGuanyinmaHostJNI by tasks.registering(Exec::class) {
    inputs.property("jniJavaHome", System.getProperty("java.home"))
    inputs.property("jniHostOS", System.getProperty("os.name"))
    inputs.property("jniHostArchitecture", System.getProperty("os.arch"))
    commandLine(guanyinmaPython + listOf(
        guanyinmaCoreDirectory.file("tools/build-android-host-jni.py").asFile.absolutePath,
        "--output", guanyinmaHostDirectory.get().asFile.absolutePath,
        "--java-home", System.getProperty("java.home")
    ))
    inputs.files(guanyinmaCoreDirectory.asFileTree.matching {
        include("Cargo.toml", "Cargo.lock", "rust-toolchain.toml", "build.rs", "src/**", "include/**", "tools/build-android-host-jni.py")
    })
    inputs.file(layout.projectDirectory.file("src/main/cpp/guanyinma_jni.cpp"))
    inputs.files(layout.projectDirectory.dir("../../../Shared").asFileTree.matching { include("Cangjie*Data.h") })
    outputs.file(guanyinmaHostLibrary)
}

// Unit tests prepare only the host JNI library. Device archives are required
// solely by AGP's native configure/build tasks, keeping JVM checks independent.
tasks.configureEach {
    if (name.startsWith("configureCMake") || name.startsWith("buildCMake") || name.startsWith("externalNativeBuild")) {
        dependsOn(buildGuanyinmaAndroid)
    }
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

val smartMandarinDatabase =
    layout.projectDirectory.file("../../../Distributions/Takao/CookedDatabase/KeyKey.db")
val smartMandarinVerifier =
    layout.projectDirectory.file(
        "../../../Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py"
    )
val smartMandarinModelHelper =
    layout.projectDirectory.file(
        "../../../Distributions/Takao/DatabaseCooker/smart_mandarin_model.py"
    )
val smartMandarinModelManifest =
    layout.projectDirectory.file(
        "../../../../DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json"
    )

val verifySmartMandarinDatabase by tasks.registering(Exec::class) {
    val python = providers.environmentVariable("PYTHON3").orNull
    if (python != null) {
        commandLine(python, smartMandarinVerifier.asFile, smartMandarinDatabase.asFile)
    } else if (System.getProperty("os.name").startsWith("Windows", ignoreCase = true)) {
        commandLine("py", "-3", smartMandarinVerifier.asFile, smartMandarinDatabase.asFile)
    } else {
        commandLine("python3", smartMandarinVerifier.asFile, smartMandarinDatabase.asFile)
    }
    inputs.files(
        smartMandarinDatabase,
        smartMandarinVerifier,
        smartMandarinModelHelper,
        smartMandarinModelManifest,
    )
}

val generateSmartMandarinAssets by tasks.registering(Sync::class) {
    dependsOn(verifySmartMandarinDatabase)
    from(smartMandarinDatabase)
    into(layout.buildDirectory.dir("generated/smartMandarinAssets"))
}

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
    dependsOn(generateGuanyinmaNotices)
    dependsOn(generateBopomofoAssets)
    dependsOn(generateAssociatedPhraseAssets)
    dependsOn(generateIndexedDictionaryAssets)
    dependsOn(generateSmartMandarinAssets)
}

tasks.withType<Test>().configureEach {
    dependsOn(buildGuanyinmaHostJNI)
    inputs.file(guanyinmaHostLibrary).withPropertyName("guanyinmaHostLibrary").withPathSensitivity(PathSensitivity.NONE)
    inputs.file(smartMandarinDatabase).withPropertyName("guanyinmaSharedModel").withPathSensitivity(PathSensitivity.NONE)
    systemProperty("keykey.guanyinma.library", guanyinmaHostLibrary.get().asFile.absolutePath)
    systemProperty("keykey.guanyinma.python", guanyinmaPython.first())
    systemProperty("keykey.guanyinma.integration", "true")
    dependsOn(generateBopomofoAssets)
    dependsOn(generateAssociatedPhraseAssets)
    dependsOn(generateIndexedDictionaryAssets)
    dependsOn(generateSmartMandarinAssets)
    systemProperty("keykey.smart.database", smartMandarinDatabase.asFile.absolutePath)
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
    constraints {
        implementation("androidx.fragment:fragment:1.9.0") {
            because("Billing's Play Services dependencies otherwise resolve obsolete Fragment 1.1.0")
        }
    }
    testImplementation("junit:junit:4.13.2")
    // Android supplies org.json in production; host JVM tests need real parsing.
    testImplementation("org.json:json:20260814")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}

// Shared macOS-baseline cases are also exercised against Android SQLite on device.
android.sourceSets.getByName("androidTest").assets.srcDir("../../../../tests/fixtures/mobile-table-input")

// Manual Rust migration references only; instrumentation is gated by migrationBaseline=true.
android.sourceSets.getByName("androidTest").assets.directories.add("../../../../tests/fixtures/core-functional")
