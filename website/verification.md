# 安卓下载网站验证

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
