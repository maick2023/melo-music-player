# Windows 电脑免本地环境、免 Mac 自动打包 Android `.apk` 与苹果 iOS `.ipa` 完整指南

## 一、 为什么你刚才解压 `.zip` 后只看到源码而没有看到 `.apk`？

1. **核心原因**：
   - 你刚才截图中的 `lib/`、`pubspec.yaml` 是 **Flutter 应用程序的源代码工程**。
   - `.apk`（安卓安装包）和 `.ipa`（苹果安装包）是编译后的二进制文件（通常体积在 **60MB ~ 120MB** 左右），需要调用 **Android SDK (Gradle)** 和 **苹果 macOS Xcode 工具链** 联网拉取底层音视频解码库（如 FFmpeg / `just_audio`）后编译生成，无法在不联网的沙盒里直接凭空生成二进制安装包。
2. **最省心的解决方案（电脑无需安装任何开发环境、也无需购买苹果 Mac 电脑）**：
   - 我已经为你写好了全自动的 **GitHub Actions 云端双端打包配置文件 (`.github/workflows/build_apk_and_ipa.yml`)**，并已内置到更新后的 `flutter_qq_music_player_project.zip` 中。
   - 你只需要在 Windows 电脑上把这个文件夹上传到你自己的 GitHub 仓库，**GitHub 官方免费的 Linux + macOS 云服务器**就会在大约 5~8 分钟内自动帮你把 **`MeloMusic_Android_Release.apk`**（安卓安装包）和 **`MeloMusic_iOS_Unsigned.ipa`**（苹果安装包）全部打包好，你直接点击下载就能装到手机上！

## 二、 三步拿走 `.apk`（安卓）和 `.ipa`（苹果）安装包（全程仅需浏览器）

### 第一步：在 GitHub 创建一个新仓库并上传代码
1. 打开浏览器登录 [GitHub](https://github.com/)（如果没有账号免费注册一个即可），点击右上角 **`+`** -> **`New repository`**。
2. 仓库名称随便填（比如 `melo-music-player`），点击底部的 **`Create repository`**。
3. 解压我发给你的最新 `flutter_qq_music_player_project.zip`，进入 `flutter_qq_music_player` 文件夹（此时你能看到 `.github`、`lib`、`pubspec.yaml` 等文件）。
4. 在 GitHub 新建好的仓库页面点击 **`uploading an existing file`**，把 `flutter_qq_music_player` 里面的所有文件和文件夹直接拖拽进去，点击底部的绿色按钮 **`Commit changes`**。

### 第二步：在 GitHub Actions 页面一键触发云端自动打包
1. 上传完成后，点击 GitHub 仓库顶部的 **`Actions`** 标签页。
2. 你会看到名为 **`Build Android APK & Apple iOS IPA`** 的工作流正在自动运行（或者你可以点击左侧的该工作流名称，再点击右侧的 **`Run workflow`** 按钮手动触发）。
3. GitHub 会同时启动两台云服务器：
   - **Ubuntu 云服务器**：自动配置 Java 17 + Flutter，自动注入安卓音乐扫描、蓝牙车载、麦克风权限，编译生成 **`MeloMusic_Android_Release.apk`**。
   - **macOS 14 云服务器（免去你买苹果电脑）**：自动配置 Xcode + Flutter，自动注入苹果后台播放、媒体库、局域网权限，编译并封装生成 **`MeloMusic_iOS_Unsigned.ipa`**。

### 第三步：下载 `.apk` 和 `.ipa` 并安装到你的手机
等待约 5~8 分钟，两个任务都变成绿色对勾 `✅` 后，点进这次运行记录的底部 **`Artifacts`** 区域，你会看到两个压缩包：

| 下载产物名称 | 适用手机 | 如何安装到手机 |
| :--- | :--- | :--- |
| **`MeloMusic-Android-APK`** | **所有安卓手机**（小米、华为、vivo、OPPO、三星等） | 下载解压后里面就是 **`MeloMusic_Android_Release.apk`**，通过微信/QQ/数据线发到安卓手机上直接点击安装即可！ |
| **`MeloMusic-iOS-IPA`** | **所有苹果 iPhone / iPad** | 下载解压后得到 **`MeloMusic_iOS_Unsigned.ipa`**。在你的 Windows 电脑上下载免费工具 **[Sideloadly](https://sideloadly.io/)** 或 **[爱思助手](https://www.i4.cn/)**，用数据线连接你的 iPhone，把 `.ipa` 拖进工具里，输入你自己的普通 Apple ID 账号即可免费完成签名并安装到苹果手机桌面！ |

## 三、 附：完整的 `.github/workflows/build_apk_and_ipa.yml` 配置文件源码

该文件已经放在最新压缩包的 `.github/workflows/build_apk_and_ipa.yml` 路径下，你也可以直接复制查阅：

```yaml
name: Build Android APK & Apple iOS IPA

on:
  push:
    branches: [ main, master ]
  workflow_dispatch: # 支持在 GitHub 页面手动一键点击触发打包

jobs:
  # =========================================================================
  # 任务一：云端自动编译 Android 安装包 (MeloMusic_Android_Release.apk)
  # =========================================================================
  build_android_apk:
    name: Build Android APK (免本地配置云端打包)
    runs-on: ubuntu-latest
    steps:
      - name: 1. 检出源码仓库
        uses: actions/checkout@v4

      - name: 2. 配置 Java 17 环境
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: 3. 配置 Flutter 稳定版环境
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: 4. 自动补全 Android 原生宿主目录并注入音乐/蓝牙/网络权限
        run: |
          if [ ! -d "android" ]; then
            flutter create --platforms=android --org com.melomusic.player .
          fi
          MANIFEST="android/app/src/main/AndroidManifest.xml"
          if ! grep -q "READ_MEDIA_AUDIO" "$MANIFEST"; then
            sed -i 's/<manifest[^>]*>/&\n    <uses-permission android:name="android.permission.INTERNET"\/>\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"\/>\n    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO"\/>\n    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"\/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"\/>\n    <uses-permission android:name="android.permission.BLUETOOTH"\/>\n    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"\/>\n    <uses-permission android:name="android.permission.RECORD_AUDIO"\/>/' "$MANIFEST"
          fi

      - name: 5. 下载 Flutter 依赖并编译正式版 APK
        run: |
          flutter pub get
          flutter build apk --release --no-tree-shake-icons
          cp build/app/outputs/flutter-apk/app-release.apk MeloMusic_Android_Release.apk

      - name: 6. 上传 Android APK 安装包产物 (供直接下载安装到安卓手机)
        uses: actions/upload-artifact@v4
        with:
          name: MeloMusic-Android-APK
          path: MeloMusic_Android_Release.apk
          if-no-files-found: error

  # =========================================================================
  # 任务二：使用 GitHub 免费 macOS 云服务器自动打包苹果 iOS 安装包 (.ipa)
  # =========================================================================
  build_ios_ipa:
    name: Build Apple iOS IPA (Windows 免 Mac 云端打包)
    runs-on: macos-14
    steps:
      - name: 1. 检出源码仓库
        uses: actions/checkout@v4

      - name: 2. 配置 Flutter 稳定版环境 (macOS)
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: 3. 自动补全 iOS 原生宿主工程并注入后台播放/媒体库/麦克风/局域网权限
        run: |
          if [ ! -d "ios" ]; then
            flutter create --platforms=ios --org com.melomusic.player .
          fi
          PLIST="ios/Runner/Info.plist"
          /usr/libexec/PlistBuddy -c "Add :NSAppleMusicUsageDescription string '需要访问您的媒体库以自动扫描并播放本地无损音乐'" "$PLIST" || true
          /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string '需要使用局域网开启 Wi-Fi 无线传歌服务'" "$PLIST" || true
          /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string '需要使用麦克风进行 AI 语音点歌与语音控制'" "$PLIST" || true
          /usr/libexec/PlistBuddy -c "Add :NSSpeechRecognitionUsageDescription string '需要语音识别以将您的语音转化为点歌指令'" "$PLIST" || true
          /usr/libexec/PlistBuddy -c "Add :UIFileSharingEnabled bool true" "$PLIST" || true
          /usr/libexec/PlistBuddy -c "Add :LSSupportsOpeningDocumentsInPlace bool true" "$PLIST" || true
          /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" "$PLIST" || true
          /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:0 string audio" "$PLIST" || true

      - name: 4. 安装依赖并编译免证书 iOS Release 归档包 (--no-codesign)
        run: |
          flutter pub get
          flutter build ios --release --no-codesign --no-tree-shake-icons

      - name: 5. 将 Runner.app 封装为标准苹果 .ipa 安装包 (支持爱思助手/Sideloadly/AltStore自签安装)
        run: |
          mkdir -p Payload
          cp -r build/ios/iphoneos/Runner.app Payload/
          zip -r -9 MeloMusic_iOS_Unsigned.ipa Payload
          rm -rf Payload

      - name: 6. 上传苹果 iOS IPA 安装包产物 (供下载后用爱思助手/Sideloadly装入iPhone)
        uses: actions/upload-artifact@v4
        with:
          name: MeloMusic-iOS-IPA
          path: MeloMusic_iOS_Unsigned.ipa
          if-no-files-found: error
```


---

# 悦听 (MeloMusic) — 仿 QQ 音乐跨平台本地音乐播放器 (Flutter)

一套代码同时支持 **Android** 与 **iOS** 的高颜值本地音乐播放器，深度还原 QQ 音乐视觉交互体验，并针对移动端本地曲库管理与苹果手机导歌痛点做了专门强化。

## 一、 核心特性

1. **三种经典播放页样式自由切换（实时无缝切换）**
   - **样式一：经典黑胶唱针模式**：仿真黑胶唱片匀速旋转，播放/暂停时机械唱针平滑起落，搭配封面色彩提取的呼吸感流光背景。
   - **样式二：沉浸式全屏大图模式**：高清封面全屏铺满，底部暗角渐变过渡，突出视觉冲击力与悬浮双行歌词。
   - **样式三：流光毛玻璃卡片模式**：大圆角磨砂玻璃悬浮卡片 + 实时动态音频频谱波形 + 精致光影边框。
2. **双端本地音乐扫描与管理**
   - **Android 端**：基于 `on_audio_query` 扫描系统 MediaStore，支持自动过滤小于 60 秒的铃声/语音片段，按单曲、歌手、专辑、文件夹自动归类。
   - **iOS 端**：支持通过系统“文件 (Files)”批量导入音频，或使用内置的 **Wi-Fi 局域网无线传歌** 从电脑浏览器直接拖拽上传歌曲与 `.lrc` 歌词。
3. **内置 Wi-Fi 局域网传歌服务器 (`shelf`)**
   - 手机端一键开启 HTTP 服务（如 `http://192.168.1.x:8080`），电脑端无需安装任何软件，打开浏览器输入地址即可批量拖拽上传 `.mp3 / .flac / .wav / .m4a / .lrc` 文件到手机沙盒曲库。
4. **专业音效与播放控制**
   - **5 段均衡器 + 预设音效**：内置流行、摇滚、古典、爵士、超重低音、人声清澈等预设，支持手动调节 60Hz ~ 14kHz 频段与银河环绕立体声开关。
   - **倍速播放**：支持 `0.5x ~ 2.0x` 无损变速不变调播放。
   - **睡眠定时关闭**：支持 15/30/45/60 分钟倒计时及“播完当前歌曲自动暂停”。
   - **LRC 歌词同步**：支持同名 `.lrc` 歌词自动匹配、逐行高亮滚动与点击歌词跳转进度。

## 二、 工程目录结构

```text
lib/
├── main.dart                        # 应用入口、深色/QQ音乐绿主题配置
├── models/
│   ├── song_model.dart              # 本地歌曲实体、LRC歌词行结构、播放样式枚举
│   └── eq_preset_model.dart         # 均衡器频段与预设音效模型
├── services/
│   ├── audio_player_service.dart    # Riverpod 全局播放控制、队列、倍速、均衡器与睡眠定时
│   ├── local_scanner_service.dart   # Android/iOS 本地音频扫描、LRC同名歌词匹配与文件导入
│   └── wifi_transfer_server.dart    # 内置 HTTP 局域网无线传歌服务器 (支持多文件 Multipart 上传)
├── screens/
│   ├── main_screen.dart             # 首页曲库、歌单分类、搜索过滤与底部悬浮胶囊 Mini 播放条
│   └── player_screen.dart           # 全屏播放抽屉（支持黑胶/大图/流光卡片三模式一键切换与歌词页）
└── widgets/
    ├── vinyl_turntable_view.dart    # 样式1：仿真黑胶唱盘与机械唱针动画组件
    ├── fullscreen_cover_view.dart   # 样式2：沉浸式全屏大图与悬浮双行歌词组件
    ├── glass_card_view.dart         # 样式3：流光毛玻璃卡片与动态频谱组件
    ├── equalizer_sheet.dart         # 均衡器音效与环绕声调节底部弹窗
    ├── sleep_timer_sheet.dart       # 睡眠定时与倍速调节底部弹窗
    └── wifi_transfer_dialog.dart    # Wi-Fi 局域网传歌状态与二维码/IP 指引弹窗
```

## 三、 Android 与 iOS 权限配置说明

### 1. Android (`android/app/src/main/AndroidManifest.xml`)
在 `<manifest>` 标签下添加以下权限：
```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.READ_MEDIA_音频" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### 2. iOS (`ios/Runner/Info.plist`)
添加本地媒体库、本地网络（用于 Wi-Fi 传歌）与后台音频保活配置：
```xml
<key>NSAppleMusicUsageDescription</key>
<string>需要访问您的媒体库以播放本地音乐</string>
<key>NSLocalNetworkUsageDescription</key>
<string>需要使用局域网开启 Wi-Fi 无线传歌服务，方便您从电脑导入音乐文件</string>
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

## 四、 编译与运行步骤

```bash
# 1. 获取依赖
flutter pub get

# 2. 连接真机或模拟器运行
flutter run

# 3. 打包 Android 正式版安装包
flutter build apk --release
```


## 五、 全能大模型 AI 网关与双向语音交互说明

- **统一多模型网关 (`lib/services/universal_llm_service.dart`)**：
  支持一键切换 **DeepSeek**、**火山引擎 (豆包 Ark)**、**阿里通义千问 (DashScope)**、**OpenAI (GPT)**、**Google Gemini**、**Meta Llama** 以及任何兼容 OpenAI `/v1/chat/completions` 协议的自定义 API 地址。
- **双向语音交互 (`lib/services/voice_assistant_service.dart`)**：
  结合 `speech_to_text` (STT 语音转文字) 与 `flutter_tts` (TTS 语音播报)，支持语音直接说出“帮我找周杰伦的歌”、“切换到黑胶模式”、“下一首”等指令操控播放器。

## 六、 关于 Android (`.apk`) 与苹果 iPhone (`.ipa`) 安装的重要说明

- **Android 手机**：使用安装包格式为 **`.apk`**（执行 `flutter build apk --release` 生成），可直接发到手机点击安装。
- **苹果 iPhone (iOS)**：**不能直接安装 `.apk` 文件**（`.apk` 是安卓专属格式），苹果手机的安装包格式为 **`.ipa`**。得益于本项目采用 **Flutter 跨平台架构**，同一套代码只需执行 `flutter build ipa` 即可生成苹果专属的 `.ipa` 安装包，并通过以下方式安装到 iPhone：
  1. **Xcode 数据线直装**：Mac 电脑连接 iPhone，用免费个人 Apple ID 签名直接运行安装。
  2. **AltStore / Sideloadly / 爱思助手自签安装**：在 Windows 或 Mac 上将生成的 `.ipa` 包用你自己的 Apple ID 免费签名装入手机（无需付费开发者账号）。
  3. **TestFlight / App Store 上架**：使用 Apple 开发者账号打包上传 TestFlight 分享链接安装。
