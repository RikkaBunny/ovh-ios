# OVH CP 发布

Flutter 客户端版本为 **1.3.0 (13)**。iOS 使用原 OVH 商店记录的 Bundle ID `com.hejingcheng.ovhpocket`，Android 使用 `com.hejingcheng.ovh_flutter`。应用显示名称统一为 `OVH CP`。

旧 SwiftUI 源码保留作参考；发布以本目录为准。iOS 更新会将原版 Keychain 中的面板令牌、账户选择和外观迁移到 Flutter 存储。成功保存后清除旧令牌，断开时清理两个存储，避免重新导入已断开的授权。迁移不读取其他应用的钥匙串，不上传凭据。

## 构建

```sh
flutter pub get
flutter analyze
flutter test
flutter build ipa --release --export-options-plist=publishing/ExportOptions.plist
flutter build appbundle --release
flutter build apk --release --split-per-abi
```

构建前配置 Android SDK 路径，例如本机 `ANDROID_HOME=/opt/homebrew/share/android-commandlinetools`。保留发布命令的默认依赖准备流程，避免继承 UI 测试生成的插件注册文件；本机 Flutter SDK 下不要在跨平台发布时追加 `--no-pub`。

Release 不使用 `OVH_QA`，不自动连接测试后端，也不接受测试证书。

Android 必须提供未跟踪的 `android/key.properties`：

```properties
storeFile=/absolute/private/path/ovh-cp-upload.p12
storePassword=YOUR_PRIVATE_STORE_PASSWORD
keyAlias=ovh-cp-upload
keyPassword=YOUR_PRIVATE_KEY_PASSWORD
```

Release 缺少签名配置时拒绝构建，不回退到调试签名。实际上传密钥和凭据保存在本机 `~/.ovh-cp/android-signing/`，权限分别为目录 700、文件 600。请在私人备份中保留这整个目录；不要上传 GitHub。换电脑时使用同一上传密钥，或依照 Google Play 的官方上传密钥重置流程处理。

iOS 的 ExportOptions 使用现有开发者团队 `4MGNRHR56T`。本地归档/导出、商店上传、提交审核、审核通过和公开发行分别记录，任何构建成功都不等于上架完成。

## 商店资料

名称：`OVH CP`

简短说明：管理自建 OVH 面板的服务器、VPS、监控与抢购任务。

功能介绍：

连接你部署的 gokele/ovh 控制台，在手机和平板上管理同一份后端数据。通过网页配对二维码、二维码图片、8 位配对码或面板访问密钥连接；支持多个地区账户、独立服务器及 VPS 实例、硬件信息、IP、流量、电源、维护、库存、任务队列、监控、历史、日志与 API 设置。仪表盘展示面板主机的 CPU、内存和存储资源。

本应用需要兼容的自建 HTTPS 面板及相应账户权限。它不会建立额外的 OVH 账户数据库。访问凭据存放在本机安全存储；可在网页撤销单台设备。危险操作再次确认，重装、终止等操作要求输入服务名称。

本应用没有广告或付费订阅。Android 扫码 SDK 的诊断数据处理详见隐私政策和 [数据安全核对](DATA-SAFETY.md)。由 jingcheng he 提供，支持 OVHcloud 服务；并非 OVHcloud 官方开发的应用。源码基于 AGPL-3.0 发布：https://github.com/RikkaBunny/ovh-ios 。

支持页面：https://ovh-review.hejingcheng.com/support

隐私页面：https://ovh-review.hejingcheng.com/privacy

审核演示页面：https://ovh-review.hejingcheng.com/review

演示环境仅包含合成 EU/CA/US 账户、实例与操作，不控制真实服务器。审核可用演示页面公开的测试访问密钥，不需要真实 OVH 登录。提交前应核对这些页面的可访问性、当前名称和隐私说明。

更新说明：全新的 Flutter 跨平台客户端；应用更名为 OVH CP；白底蓝标 cp 图标；iOS 原版连接迁移；保留仪表盘资源、实例主入口、配对和刷新修复。
