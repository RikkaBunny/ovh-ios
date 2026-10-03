# 实例资源接口扩展

Flutter 1.3.0 (15) 使用 `GET /api/instance-metrics?account=ID&kind=dedicated|vps&service=NAME`。
读数必须同时包含 `scope: instance`、账户 ID、服务名称、类型、状态和 `metrics`，客户端拒绝错账户、错实例或旧宿主机响应。不存在接口的后端显示未支持，不回退到 `/system/metrics`。

扩展沿用原面板认证，每次读取在原后端验证设备令牌，按账户验证实例归属。仅在部署者明确设置 `PANEL_HOST_SERVICE` 为运行面板的独服服务名称后，为该实例采样 Linux 内核 `/proc/stat`、`/proc/meminfo` 及 `/app` 只读绑定目录所在的主机文件系统；其他实例返回 `unavailable`，不会复制这台主机的数据。CPU 核心数来自内核，不使用原 Go 容器的 CPU 配额。磁盘只代表该目录所在的文件系统，不汇总其他挂载磁盘；不能当作另一台机器或全账户的汇总。

不读取 SSH 或 OVH API 密钥，不向外部监控服务传输授权；不修改上游的数据库或二进制。账户所属实例列表按设备凭据和账户隔离缓存 30 秒；每个请求仍验证授权，撤销设备即刻失效。

部署在 1Panel 的本地 Compose 目录，复制 `server.py` 到 `app/server.py`，将运行面板的独服名称写入此目录 `.env` 的 `PANEL_HOST_SERVICE`（不是客户端配置）。Compose 只监听主机回环 `127.0.0.1:19997`。现有 OpenResty 为 `/api/instance-metrics` 添加专用代理到该端口；其他路径继续使用原面板。不要直接公开容器端口。未设置绑定时所有实例资源保持未知。

返回可用例子：

```json
{"scope":"instance","account":"demo-ca","service":"panel.example","kind":"dedicated","status":"available","source":"panel-host","metrics":{"cpu":{},"memory":{},"disk":{}}}
```

其他实例需要在后端接入独立的监控采集来源。当前扩展不假设 OVH 硬件配置等同于实际使用量，也不自动安装远程 agent。

验证：`cd metrics-bridge && python3 -m unittest -v`。源码沿用根目录 AGPL-3.0 许可。
