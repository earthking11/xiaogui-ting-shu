# 小龟听书 `xiaogui-ting-shu`

`小龟听书` 是一个 Android TXT 小说阅读器 + MiMo TTS 听书 App。它的目标不是做一个功能堆满的大而全阅读器，而是先把一个核心体验做好：

`把 TXT 小说导入手机 -> 舒服阅读 -> 需要时一键听书 -> 尽快听到声音 -> 后台准备下一段 -> 回来还能接着上次进度读`

当前 App 已经实现真实可运行的主流程，支持本地 TXT 导入、系统分享导入、阅读进度恢复、书签、主题/字号/行距、MiMo API Key 设置、API 连通性测试、TTS 分段生成、播放当前段、预生成下一段、底部听书播放器、右下角阅读百分比。

## 下载 APK

正式测试版安装包放在 GitHub Release：

- `v1.0`：首个可用版本，包含 TXT 导入、阅读、MiMo TTS 听书、API 连通性测试、快速起播段、下一段预生成、听书播放器和阅读进度恢复。

如果是本地开发构建，debug APK 默认输出到：

```text
outputs/novel_tts_reader-debug.apk
```

## 软件目的

这个 App 面向“已经有 TXT 小说文件，希望在 Android 手机上阅读和听书”的场景。

核心目标：

- 读书时界面尽量安静，减少工具栏打扰。
- 想听书时不需要复杂配置，点一下就能开始准备朗读。
- 首段 TTS 尽量短，降低首次等待。
- 播放时透明显示当前音频进度和下一段生成状态。
- 杀掉 App 后再次打开，也应该回到上次阅读/朗读推进到的位置。
- API Key 只由用户填写，保存在本机，不写进代码、不内置到 APK。

## 用户操作流程

首次使用：

1. 打开 App。
2. 点击 `导入 TXT`。
3. 选择本地 `.txt` 小说文件。
4. 进入阅读页后，可以直接滑动阅读。
5. 点击屏幕静止区域，可显示/隐藏顶部进度和底部工具栏。
6. 点击底部 `Aa` 可调整主题、字号、行距、音色、语速和 MiMo API Key。
7. 首次听书前，在朗读设置里填写 MiMo API Key。
8. 可点击 `测试 API 连通性`，用一小句测试文本确认 Key、网络、余额和服务状态。
9. 点击底部 `我想听书`，App 开始生成快速起播段并播放。

分享导入：

1. 在系统文件管理器或其他 App 中选中 TXT。
2. 点击系统 `分享`。
3. 选择 `小龟听书`。
4. App 会读取分享过来的 TXT，并导入到书架。

继续阅读：

1. App 会记录最近一本书和每本书的阅读进度。
2. 再次打开 App 时，如果上次读过某本书，会直接进入这本书。
3. 阅读页会跳到保存的段落位置。
4. 右下角会显示当前阅读百分比。

## 阅读界面逻辑

阅读页主体是按段落渲染的 TXT 内容。TXT 会先做基础清理：

- 统一换行符。
- 去掉文件开头 BOM。
- 多个空行压缩成段落分隔。
- 很长的自然段会按标点或长度拆成更短段落，避免单段过大。

阅读交互：

- 页面静止时，点击阅读区域会显示/隐藏顶部信息栏和底部工具栏。
- 用户快速滑动后，如果手指只是为了停住滚动，不会弹出工具栏，避免遮挡阅读。
- 顶部栏显示书名和已读百分比。
- 右下角常驻显示当前阅读百分比。
- 底部工具栏包含书架、书签、阅读设置、听书、更多。

进度保存：

- 普通滑动阅读时，App 会根据当前可见段落保存进度。
- 滚动结束时会更快写入进度，减少强杀 App 后丢进度的概率。
- TTS 开始朗读某一段时，也会把进度推进到这一段开头并保存。
- 启动恢复时会避免初始渲染的第 0 段覆盖真实保存进度。

当前限制：

- 保存的是段落级进度，不是精确到某个字。
- 听书恢复保存的是当前 TTS 段开头，不是音频播放到第几秒。
- 杀掉 App 再进入会回到文字进度，但不会自动恢复音频播放。

## 听书/TTS 逻辑

MiMo TTS 当前采用非流式请求：App 先把一段文字发给 MiMo，等完整音频返回后再播放。

为了改善体验，当前采用“快速起播 + 后台预生成”的策略：

- 第一段是快速起播段，目标约 `260` 字，最少约 `160` 字，软上限约 `360` 字，硬上限约 `520` 字。
- 后续段是正常听书段，目标约 `700` 字，最少约 `420` 字，软上限约 `900` 字，硬上限约 `1100` 字。
- 分段尽量按自然段合并，不强行在普通段落中间切断。
- 第一段播放开始后，App 会立刻在后台生成下一段。
- 如果下一段已生成，当前段播完后会直接切过去。
- 如果下一段还没生成好，底部播放器会显示 `正在准备下一段...`。

听书状态机：

- `idle`：未朗读，按钮显示 `我想听书`。
- `needsApiKey`：缺少 MiMo API Key。
- `preparing`：正在生成快速起播段。
- `playing`：正在朗读。
- `paused`：已暂停。
- `bufferingNext`：当前段播完，但下一段还在准备。
- `completed`：朗读完成。
- `error`：朗读失败，显示具体错误。

底部听书播放器会显示：

- 当前状态，例如 `正在生成快速起播段...`、`正在朗读`。
- 当前朗读文字预览。
- 播放/暂停按钮。
- 停止按钮。
- 当前音频播放进度条和进度小点。
- 已播放时间和总时长。
- 下一段状态，例如 `下一段生成中...`、`下一段已生成`、`已到最后一段`。

## MiMo API Key 与连通性测试

Key 原则：

- 用户自己在 App 内填写 MiMo API Key。
- Key 只保存在本机安全存储。
- 代码、测试、README 和 APK 都不内置真实 Key。
- 设置页保存后只显示掩码，不显示完整 Key。
- Key 输入框使用普通文本输入，不触发安卓安全键盘。

连通性测试：

- 设置页提供 `测试 API 连通性`。
- 测试时只发送一句 `连通性测试。`。
- 如果成功，会显示收到的测试音频字节数。
- 如果失败，会显示更具体的错误，例如认证失败、余额不足、地区/权限问题、请求过频、服务不可用、网络不可用、超时、安全连接失败或连接中断。

## 文件导入与权限

导入策略：

- 主动导入使用 Android 系统文件选择器 `ACTION_OPEN_DOCUMENT`。
- 分享导入支持系统 `ACTION_SEND` 和 `ACTION_VIEW` 传来的 TXT。
- 读取成功后，TXT 会复制到 App 私有目录，由 App 自己管理。

权限策略：

- 不申请全盘文件管理权限。
- 不申请写外部存储权限。
- 为兼容旧 Android 和部分文件管理器，Manifest 声明了 Android 12 及以下的 `READ_EXTERNAL_STORAGE`。
- 现代 Android 上主要依赖系统选择器/分享授权读取文件。

编码与大文件：

- 支持常见 TXT 导入。
- 对 GB18030 文本做了兼容处理。
- 大于约 `30MB` 的 TXT 会提示首次整理可能较慢。

## 视觉和交互方向

当前界面按 `$huashu-design` 的方向做过一轮阅读器视觉打磨：

- 书架页偏柔和、安静，强调“导入一本书就能开始读”。
- 阅读页减少视觉噪音，正文优先。
- 工具栏以浮层卡片呈现，不常驻压迫正文。
- 听书状态从单行提示升级为底部小播放器。
- 阅读设置里加强了文字对比度，避免浅色看不清。

后续可以继续打磨：

- 听书时高亮当前正在朗读的句子。
- 做章节目录识别。
- 增加系统通知栏播放控制。
- 增加锁屏/后台连续播放。
- 增加“继续上次听书到第几秒”。
- 增加 TTS 失败自动降级为更短分段。

## 运行环境

这台机器已有现成 Flutter Android 工具链，不要重复安装 Android Studio、Flutter、JDK 或 Android SDK。

开发前先执行：

```bash
source /Users/lidazuo/Documents/Codex/2026-05-31/app-android-sdk/outputs/flutter-android-env.sh
```

常用检查：

```bash
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

如果 `flutter analyze` 在中文路径下崩溃，可以复制项目到英文临时目录后再跑。这是本机 Flutter 3.44.0 分析器对路径的已知问题，不代表项目代码错误。

## 打包说明

Android 默认只打包 `arm64-v8a`，不再默认附带 `armeabi-v7a` 和 `x86_64`。

常用 debug 包路径：

```text
outputs/novel_tts_reader-debug.apk
```

构建产物示例：

```bash
flutter build apk --debug --no-pub --target-platform android-arm64
cp build/app/outputs/flutter-apk/app-debug.apk outputs/novel_tts_reader-debug.apk
```

## 目录结构

```text
lib/
  app.dart                         App 启动、书架/阅读页路由、分享导入入口
  core/
    constants.dart                 App 常量、MiMo endpoint、TTS 分段参数、音色/语速
    app_theme.dart                 主题和阅读配色
  models/
    book.dart                      书籍模型
    reader_paragraph.dart          TXT 段落解析和长段拆分
    reading_progress.dart          阅读进度模型
    tts_chunk.dart                 TTS 分段模型
    tts_settings.dart              TTS 设置模型
  services/
    book_repository.dart           TXT 导入、书籍持久化、正文读取
    native_file_service.dart       Flutter 与 Android 原生文件选择/分享桥接
    settings_repository.dart       阅读设置、TTS 设置、进度、书签持久化
    secure_key_store.dart          MiMo API Key 安全存储
    mimo_tts_api_client.dart       MiMo TTS 请求与错误映射
    tts_cache_store.dart           临时音频缓存
  features/
    library/                       书架页
    reader/                        阅读页、设置面板、书签面板、底部工具栏
    tts/                           TTS 播放控制器、分段器、播放器 UI
  widgets/                         通用 UI 组件
test/
  settings_repository_test.dart
  tts_chunker_test.dart
  mimo_tts_api_client_test.dart
  widget_test.dart
android/
  app/src/main/AndroidManifest.xml Android 权限、分享/打开 TXT intent
  app/src/main/kotlin/...          原生文件选择和分享读取逻辑
```

## 当前已验证

最近一次代码验证：

- `flutter analyze`：通过。
- `flutter test test/mimo_tts_api_client_test.dart test/tts_chunker_test.dart`：通过。
- `flutter build apk --debug --no-pub --target-platform android-arm64`：通过。

最近一次 APK 输出：

```text
/Users/lidazuo/Documents/dev/安卓app开发/novel_tts_reader/outputs/novel_tts_reader-debug.apk
```

## 开发注意事项

- 不要把真实 MiMo API Key 写进代码、测试、README、提交记录或 APK 资源。
- 继续打包时默认只打 `arm64`。
- 优先在纯英文临时路径做 `flutter analyze`，避免中文路径触发 Flutter 分析器崩溃。
- 进度恢复、TXT 分享导入、TTS 首段等待、下一段预生成是当前体验最关键的回归测试点。
- 如果要进一步优化听书体验，优先做“后台播放通知栏”“精确恢复音频秒数”“当前朗读句子高亮”。
