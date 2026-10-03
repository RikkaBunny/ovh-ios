# ovh cp 安卓下载页

公开入口：<https://ovh.hejingcheng.com/download/>。

纯静态 HTML/CSS/JavaScript，无登录、埋点或第三方字体。保留面板的黑白、灰色分隔、圆角卡片和胶囊按钮，展示安卓模拟器实际界面。桌面二维码指向下载页；APK 使用本站 HTTPS 下载，GitHub 提供备用。

`release.json`、页面版本信息及 `SHA256SUMS.txt` 与最终 APK 保持一致。APK 不提交 Git，由已发布的正式签名安装包单独部署。图标位于 `assets/icon.png`，截图来自 `flutter/publishing/screenshots/android/`，均为演示数据。

页面通过现有 1Panel OpenResty 的 `/download/` 静态路径服务。APK 使用独立 MIME、附件下载头、版本文件名及字节范围请求；原控制台和 API 继续走现有代理。发布前验证 OpenResty 配置、页面与资源、完整文件校验、范围下载及移动布局。

本地预览：`python3 -m http.server 18347 --directory website --bind 127.0.0.1`。预览不包含 APK。

生产静态目录为 `/opt/1panel/apps/openresty/openresty/www/sites/ovh-cp-download/`，挂载到 OpenResty 容器的 `/www/sites/ovh-cp-download/`。只发布页面、样式、脚本、版本元数据、校验文件、`assets/` 和正式 APK；文档与验证截图留在 GitHub。不要把仓库、签名材料或后端配置复制到公开目录。

后续发布更新时，同步页面、`release.json`、校验文件和版本化 APK 文件名，更新对应附件路由，保留旧版 APK 下载。先备份站点与 vhost，上传并校验，再执行 OpenResty 配置检查与 reload。变更仅限 `/download/`；不修改控制台 `/` 与 `/api/` 代理。当前上线证据见 [验证记录](verification.md)。
