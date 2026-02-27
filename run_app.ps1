# 设置 Java 环境变量
$env:JAVA_HOME = "d:\java\java21"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# 验证 Java 版本
Write-Host "Java version:"
java -version

# 运行 Flutter 应用
Write-Host "Running Flutter app..."
flutter run