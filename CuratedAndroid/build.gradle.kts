plugins {
    id("com.android.application") version "9.4.1" apply false
    // AGP ships Kotlin built in; these pin the Kotlin version so it matches the Compose compiler.
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.20" apply false
}
