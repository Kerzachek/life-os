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
// file_picker 10.x собран под compileSdk 34, а его зависимости требуют 36.
// Новее версии не подходят: им нужен win32 6, а launch_at_startup держит win32 5.
subprojects {
    if (name == "file_picker") {
        afterEvaluate {
            extensions.getByName("android").withGroovyBuilder {
                "compileSdkVersion"(36)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
