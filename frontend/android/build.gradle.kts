allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// flutter_native_splash ships a hardcoded old compileSdk (31) in its own android/build.gradle,
// lower than what other, newer plugins already in this app require transitively
// (androidx.fragment/androidx.window need compileSdk 33-34+). Scoped to just this one module
// (not all subprojects — a blanket override broke sqflite_android, which compiles fine as-is)
// so this only touches the actual mismatched plugin.
subprojects {
    if (project.name == "flutter_native_splash") {
        afterEvaluate {
            val androidExt = project.extensions.findByName("android")
            if (androidExt is com.android.build.gradle.BaseExtension) {
                androidExt.compileSdkVersion(35)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
