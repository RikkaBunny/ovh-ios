# OVH CP 产品官网与安卓下载

公开入口：<https://ovh.gamelife.life/>。

使用前置条件：先在用户自己的 VPS 上部署支持「API 设置 → App 配对」的 [gokele/ovh 服务](https://github.com/gokele/ovh)，配置 OVH 账户，并准备手机可访问的 HTTPS 网页面板地址，再安装 App、生成配对码并连接。上游 [部署文档](https://github.com/gokele/ovh#部署方式) 提供 Docker 等方式。首页下载入口、安装与配对区的前置条件说明、FAQ、下载区和页脚均明确该要求，并提供服务项目链接；缺少 App 配对入口时需先更新服务。App 与网页读取同一服务的数据。

功能、部署与配对区使用铺满页面宽度的白色 / 浅灰色背景交替区分：任务功能为白色，多地区账户为浅灰，部署说明为白色，三步配对指南为浅灰。前置条件与步骤保持开放式排版，不使用圆角卡片；服务项目及部署文档使用无阴影的文字链接。五张功能插图已改为真实 Alpha 透明素材，移除原来的 CSS 混合样式，在两种背景下直接显示。

使用用户已登录的 Chrome Gemini Pro Canvas 重新设计官网，视觉参考 Gemini 产品官网 <https://gemini.google/us/about/?hl=en>。采用固定浅色主题、居中轻字重大标题、原生 Canvas 3D 蓝紫粒子云、胶囊按钮、真实截图产品舞台与交错功能介绍。官网的白色与浅灰背景和三张浅色 App 示例统一，操作系统的深色偏好不会切换官网主题。

接入时补齐 Gemini 未生成完整的动画脚本末尾，校正剩余内联样式、缺失布局类与产品文案。粒子数量按桌面/手机分别为 3,500 / 1,000，DPR 上限 1.5、30 FPS；离开首屏或页面不可见时停止动画，减少动态效果时保留静态画面。生产版本为独立 HTML/CSS/JavaScript，无登录、埋点、第三方字体或 CDN 运行时。

保留下载、安装与配对说明、GitHub 备用、版本与校验信息，并补全移动导航和可访问的截图切换。下载二维码指向本网站；连接 App 的配对码由用户自己的网页面板生成。iOS 入口显示“申请 iOS 测试”，跳转到 https://www.hejingcheng.com/contact/；首屏及 FAQ 说明在联系页留下邮箱，申请接收 TestFlight 邀请。

五张功能插图使用图像生成工具制作，统一白色瓷质与磨砂玻璃、蓝紫点缀：任务、全球账户、安装、生成配对码、扫码连接。最新版本由内置图像编辑工具移除白底，网页加载带 Alpha 的 `assets/feature-*.webp`，总大小约 834 KB，采用延迟加载与固定宽高比。格式转换保留生成结果的 Alpha 通道，四角完全透明；完整提示词、最终素材路径及透明验证见 [插图记录](artwork/README.md)。插图里的配对图案是装饰，真实下载二维码与 App 截图继续使用原资源。

接入时校正文案中的绝对安全承诺与凭据处理说明，补全键盘操作、减少动画偏好和脚本失效时的内容展示；样式与脚本外置以兼容现有 CSP。测试覆盖桌面、390px/360px 手机、菜单、截图、FAQ、校验复制、减少动态效果及禁用 JavaScript 场景。当前上线截图与验证见 [验证记录](verification.md)。

`release.json`、页面版本信息及 `SHA256SUMS.txt` 与最终 APK 保持一致。APK 不提交 Git，由已发布的正式签名安装包单独部署。图标位于 `assets/icon.png`，截图来自 `flutter/publishing/screenshots/android/`，均为演示数据。

页面通过现有 1Panel OpenResty 的独立域名 `ovh.gamelife.life` 根目录服务。旧 `ovh.hejingcheng.com/download/` 路径永久跳转到新官网，并保留路径与查询参数。APK 使用独立 MIME、附件下载头、版本文件名及字节范围请求；原控制台和 API 继续走现有代理。发布前验证 OpenResty 配置、页面与资源、完整文件校验、范围下载及移动布局。

本地预览：`python3 -m http.server 18347 --directory website --bind 127.0.0.1`。预览不包含 APK。

生产静态目录为 `/opt/1panel/apps/openresty/openresty/www/sites/ovh-cp-download/`，挂载到 OpenResty 容器的 `/www/sites/ovh-cp-download/`。只发布页面、样式、脚本、版本元数据、校验文件、`assets/` 和正式 APK；文档与验证截图留在 GitHub。不要把仓库、签名材料或后端配置复制到公开目录。

后续发布更新时，同步页面、`release.json`、校验文件和版本化 APK 文件名，更新对应附件路由，保留旧版 APK 下载。先备份站点与 vhost，上传并校验，再执行 OpenResty 配置检查与 reload。官网配置文件为 `ovh-cp-site.conf`，使用独立 Let’s Encrypt 证书与续期部署钩子。旧面板配置只将 `/download` 与 `/download/` 重定向到新域名，控制台 `/` 与 `/api/` 代理继续保持原样。Build 15 的产品截图已同步新版 Flutter 界面。iOS 测试可通过联系页申请加入 TestFlight；Android 从官网直接下载，尚未上架 Google Play。仪表盘按账户与选定实例展示资源，未接入采集的实例显示未知。当前上线证据见 [验证记录](verification.md)。

官网换域名时，同时更新 HTML 的 canonical、Open Graph URL、下载二维码，以及仓库中的当前下载入口；历史验证记录保留原地址。新域名仅提供公开静态页面与安装包。

生产配置的公开资源名单还需包含 `feature-tasks.webp`、`feature-regions.webp`、`feature-install.webp`、`feature-pairing.webp`、`feature-scan.webp`，并以 `image/webp` 返回。只增加这五张图的具体路径，`artwork/`、验证文档和仓库文件保持不公开。
