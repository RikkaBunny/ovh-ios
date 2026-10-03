# 原生客户端维护与隔离测试

## 更新接口

```sh
python3 Tools/generate_catalog.py --upstream /你的/gokele-ovh-checkout
```

生成 `OVHPocket/NativeCatalog.json` 与 `Tools/route-audit.json`。检查差异再构建；新增嵌套类型、枚举或业务规则需要人工核对。文件中 commit 从 Git 实际读取。

## 本机测试环境

`fixture.py` 只监听 `127.0.0.1:16443`。账户、服务器、令牌、购买和电源效果都是演示数据，不连接 OVH。访问密钥 `OVH-AppReview-2026` 是公开测试值。测试证书私钥在本地生成，不加入源码包。

从项目根目录生成临时本机证书：

```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
  -keyout Tools/localhost.key -out Tools/localhost.crt \
  -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
  -addext 'basicConstraints=critical,CA:TRUE'
python3 Tools/fixture.py
```

另一个终端把证书加入**专门用于本项目测试的现有模拟器**，并执行检查：

```sh
xcrun simctl keychain QA模拟器UDID add-root-cert "$PWD/Tools/localhost.crt"
xcodebuild -project OVHPocket.xcodeproj -scheme OVHPocket \
  -destination id=QA模拟器UDID -derivedDataPath build \
  -resultBundlePath Native-QA.xcresult -parallel-testing-enabled NO test
```

UI 测试会清除 QA 模拟器中 OVH 的连接，以本机演示账户重新登录，因此不要选择保存真实配对凭据的日常模拟器。UI 测试只在 Debug 模拟器、地址为 `https://localhost:16443` 时启用自动登录与重置。生成与运行均不需要真实服务器凭据。

测试客户端原生代码、路由与交互，不能证明真实 OVH 硬件能力、付款、重装、KVM 或实体相机已通过测试。
