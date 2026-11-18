pluginManagement {
    // Daemon criteria match a major version; reject an older cached JDK 25
    // before resolving plugins (CVE-2026-114938).
    val runtime = Runtime.version()
    val patched = runtime.interim() > 0 || runtime.update() > 5 ||
        (runtime.update() == 5 && runtime.patch() >= 1)
    check(runtime.feature() == 25 && patched && runtime.pre().isEmpty &&
        System.getProperty("java.vendor").contains("Amazon")) {
        "Android builds require patched Amazon Corretto JDK 25.0.5.1.2 or later in the JDK 25 line. " +
            "Actual daemon: ${System.getProperty("java.vendor")} $runtime."
    }
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "KeyKeyAndroidIME"
include(":app")
