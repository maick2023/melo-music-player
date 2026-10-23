@echo off
chcp 65001 >nul
echo ====================================================================
echo   悦听 (MeloMusic) - Windows 一键生成 Android APK 安装包脚本
echo ====================================================================
echo.

where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo [提示] 检测到您的电脑尚未安装 Flutter SDK。
    echo 如果您不想在电脑上安装几 GB 的开发环境，请直接使用本目录下的：
    echo 【GitHub Actions 云端零配置自动打包方案】（详见 README.md），
    echo 把本文件夹上传到 GitHub，云端会自动为您生成 .apk 和苹果 .ipa 安装包！
    echo.
    pause
    exit /b 1
)

echo [1/3] 正在自动补全 Android 原生宿主目录...
if not exist "android" (
    call flutter create --platforms=android,ios --org com.melomusic.player .
)

echo [2/3] 正在拉取音频解码、车载互联与 AI 语音插件依赖...
call flutter pub get

echo [3/3] 正在编译生成正式版 Android 安装包 (.apk)...
call flutter build apk --release --no-tree-shake-icons

echo.
echo ====================================================================
echo   编译完成！您的 APK 安装包已生成在：
echo   build\app\outputs\flutter-apk\app-release.apk
echo ====================================================================
pause
