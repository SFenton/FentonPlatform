# Android foundation pilot

This is a bounded Kotlin/Jetpack Compose Material 3 foundation library plus a
small harness app, not a consumer UI rewrite. The `:foundation`
`com.android.library` module owns `FoundationScope`, `RouteRegistry`, and
`FoundationModalHost`; the `:app` `com.android.application` module references
it and supplies only the harness screen.

The pilot uses Java 17, Gradle 8.14.3, Android Gradle Plugin 8.11.0, Kotlin
2.2.10, and the Compose BOM `2025.10.01`. Unit tests prove scope and route
contracts. The Compose UI test is an instrumented native test and requires an
owned emulator; it is not claimed by a JVM build.

Direct dependencies are AndroidX Activity Compose 1.10.1, Compose Material 3
1.4.0 (via the BOM), Compose UI 1.9.4 (via the BOM), Lifecycle Runtime Compose
2.9.4, and kotlinx-coroutines-android 1.10.2. The resolved graph also includes
Kotlin stdlib 2.2.10, AndroidX Core/Annotation/Collection/Lifecycle/Activity
support, Compose Runtime/Foundation/Animation/Material Ripple, and their
transitives from Google Maven. The Gradle wrapper was generated from the
existing cached Gradle 8.14.3 distribution on `SFenton-Music`; it uses the
standard services.gradle.org distribution URL. Resolved dependency checksums
are recorded in `platforms/android/gradle/verification-metadata.xml`.
Wrapper SHA-256: `gradle-wrapper.jar`
`7d3a4ac4de1c32b59bc6a4eb8ecb8e612ccd0cf1ae1e99f66902da64df296172`;
`gradle-wrapper.properties`
`7e0821d895908883350587c74476b717016ab416320c44dc82a10def916c6fb5`.

The verification metadata is machine-readable dependency integrity evidence,
not a license manifest. SPDX IDs/URLs for the full transitive Maven graph were
not generated in this pilot; the parent-owned Android license-manifest workflow
must perform that review before reuse.
