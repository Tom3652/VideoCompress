import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = "https://jitpack.io")
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    layout.buildDirectory.value(newBuildDir.dir(name))
}

subprojects {
    evaluationDependsOn(":app")
}

// gallery_saver and its JNI dependencies target Java 11 but do not declare a
// Kotlin JVM target. Without this, Kotlin defaults to the host JDK (21) and
// AGP 9 rejects the resulting mixed bytecode targets.
subprojects {
    if (name in setOf("gallery_saver", "jni", "jni_flutter")) {
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_11)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
