# 安卓下载网站验证

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
