# 2026-10-03 · OVH CP Build 14

白底图标、全大写名称保留；产品预览替换为本次 Android UI 回归截图，图像引用添加 parity-14 版本参数。APK 1.3.0（14）为 75252044 字节，SHA-256 007b24266a4e3ca45ceee6f33060af7c7df1c851a9b18eb2a25789012e9e2e90。iOS 当前等待 Apple 审核，通过后自动发布。

通过 1Panel OpenResty 原子更新、校验和回滚备份发布。公网页面静态资源与源文件相同；HTML 的差异仅为原 Cloudflare 添加的交付脚本。Chrome 实际下载与最终 APK 校验一致。APK 附件 MIME、名称、长度、Range 206 检查通过，原控制台 API 健康正常。390px 手机预览确认白底标识和新版实例控制截图，截图切换可用，临时视口已恢复。

---

# 安卓下载网站验证

## Gemini 科技产品官网重设计 · 2026-10-03 16:51

根据用户新的视觉要求，实际查看 Gemini 官方产品站，并在用户 Chrome 的 Gemini Pro Canvas 中重新生成和精修。采用纯黑主题、居中大标题、蓝紫 3D 粒子主视觉与真实 App 截图舞台，替换之前的网格与功能卡片设计。

- 保留生成的视觉与粒子投影算法，补齐被截断的动画循环；页面不可见或离开首屏时取消动画，减少动态效果时保留静态主视觉。
- 样式与脚本外置，剩余内联样式改为 CSS 类；无外部运行时、字体或新增网络请求。
- 1141px 桌面、390px / 360px 手机无横向溢出；截图保持原比例。移动菜单、Escape、导航自动关闭、截图鼠标和方向键切换、FAQ 展开通过。
- 复制 SHA-256 后，在本地临时验证页实际粘贴得到正确的 64 位校验值；验证页已删除。
- 禁用 JavaScript 后没有隐藏正文，两个主 APK 链接保持可用；减少动画时文字与静态粒子图正常显示。
- 公网 CSS、JS、版本元数据、校验文件、图标、下载二维码与本地字节一致，浏览器未捕获错误或警告。
- 从新版官网实际下载完整正式 APK：75,507,618 字节，SHA-256 与原发布包一致；Range 请求仍返回 206。
- 源站 HTTPS 页面与本地 HTML SHA-256 完全一致：`006179b1bd86f5dcf0cd1f66a7743c6ea52ad457523afb4304a85cbb24ab9c94`。后端健康检查仍为 `status: ok`。
- 沿用 1Panel OpenResty 静态路径，回滚保存在服务器 `20261003T085137Z-gemini-v2/site` 快照；正式 APK 与签名材料未变更。

![新版官网桌面首屏](verification/gemini-premium-desktop.png)

![新版官网手机首屏](verification/gemini-premium-mobile.png)

以下为此前设计与下载服务的历史验证。

## Gemini 官网更新 · 2026-10-03 16:24

通过用户已登录的 Chrome Gemini Pro Canvas 生成完整官网初稿，再接入现有 `/download/`。保留 Gemini 的网格、光晕、蓝色渐变、产品截图和不同尺寸功能卡片，校正过度宣传文案，完善部署与交互。

- 将样式与脚本外置，兼容现有 CSP；静态文件校验通过，没有修改后端与 OpenResty 路由。
- 1141px 桌面、390px / 360px 手机无横向溢出；深色、浅色、减少动画偏好检查通过。
- 移动菜单展开、导航后关闭、Escape 关闭、截图鼠标/键盘切换、FAQ 展开及校验值复制通过。
- 禁用 JavaScript 后，全部正文仍可见，主要 APK 链接可用。
- 公网 CSS、JavaScript、版本信息和二维码与本地内容一致；浏览器未捕获页面错误。
- 再次从新官网实际下载正式 APK，75,507,618 字节及 SHA-256 与原发布包一致；范围请求仍返回 206。
- 页面源文件 SHA-256：`a9639abbbd5d4866a8d5cd12b975420f15d778e6c1e9e0fa91a44aab6df49d5d`。源站 HTTPS 响应与该文件完全一致，面板健康检查正常。
- 回滚保留在服务器本次发布快照中，正式 APK 与签名资料未变更。

![Gemini 官网桌面首屏](verification/gemini-desktop.png)

![Gemini 官网功能介绍](verification/gemini-features.png)

![Gemini 官网手机首屏](verification/gemini-mobile.png)

以下为初版网站验证与历史截图。

2026-10-03 部署至 <https://ovh.hejingcheng.com/download/>，沿用现有 1Panel OpenResty、域名与 HTTPS。

## 正式安装包

- `ovh-cp-1.3.0-11.apk`，版本 1.3.0，versionCode 11，包名 `com.hejingcheng.ovh_flutter`。
- 75,507,618 字节，最低 SDK 24（Android 7.0），目标 SDK 36；arm64-v8a、armeabi-v7a、x86_64。
- SHA-256：`c2bfe133850f390ecfd0e272fa7248ccf84d8effb45349bf606ba60032339010`。
- Chrome 从页面下载按钮对应链接获取完整 APK；文件大小与哈希和原始正式签名包一致。本次验证下载，没有重新在实体手机安装。

## 网络与页面

- OpenResty 配置检查通过、配置已持久化并重新加载；面板健康接口返回 200 / `status: ok`，原控制台仍返回 200。
- 公网页面、CSS、JavaScript、版本元数据、图标、二维码、三张截图及校验文件正常加载。静态资源与本地源文件一致；HTML 经 Cloudflare 加入其现有检测脚本。
- APK HEAD 返回 200，MIME 为 `application/vnd.android.package-archive`，`Content-Disposition` 指定附件下载和正确文件名，长度 75,507,618。
- `Range: bytes=0-1023` 返回 206、1,024 字节及正确 `Content-Range`，支持范围下载。
- `/download` 重定向至 `/download/`；不存在的 APK 和隐藏文件路径返回 404。
- 桌面 1141px、手机 390px / 360px 无横向溢出。截图切换、方向键切换、FAQ 展开、校验值复制通过；公网浏览器检查未捕获页面错误。
- 下载二维码打开本下载页；用户连接 App 的配对二维码由自己的网页控制台生成。

## 上线截图

![桌面下载页](verification/download-desktop.png)

![手机下载页](verification/download-mobile.png)
