"""Isolated App Review backend. Synthetic data only; never connects to OVH."""
import json
import mimetypes
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

ROOT = Path(__file__).parent
KEY = "OVH-AppReview-2026"
ACCOUNTS = [
    dict(id="demo-eu", name="欧洲演示账户", endpoint="ovh-eu", zone="FR", isDefault=True),
    dict(id="demo-ca", name="加拿大演示账户", endpoint="ovh-ca", zone="CA", isDefault=False),
    dict(id="demo-us", name="美国演示账户", endpoint="ovh-us", zone="US", isDefault=False),
]
SERVERS = {
    "demo-eu": [dict(serviceName="ns-demo-eu.example", name="欧洲独立服务器", commercialRange="KS-LE-B", datacenter="GRA", state="ok", ip="192.0.2.10", os="debian13_64", renewalType=True)],
    "demo-ca": [dict(serviceName="ns-demo-ca.example", name="加拿大独立服务器", commercialRange="KS-LE-B", datacenter="BHS", state="ok", ip="198.51.100.10", os="ubuntu2404_64", renewalType=True)],
    "demo-us": [],
}
VPS = {
    "demo-eu": [dict(serviceName="vps-demo-eu.example", displayName="EU 开发环境", state="running", zone="Region OpenStack: os-eu-west-gra", vcore=2, memoryMB=4096, diskGB=40, renewalType=True, model="VPS-1")],
    "demo-ca": [],
    "demo-us": [dict(serviceName="vps-demo-us.example", displayName="US 云主机", state="running", zone="Region OpenStack: os-us-west-or-2", vcore=1, memoryMB=2048, diskGB=20, renewalType=True, model="VPS-1")],
}
LOCK = threading.Lock()
DEVICES = {}
CODES = {}
QUEUE = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # No request/IP/credential logs.

    def send_json(self, value, status=200):
        raw = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()

    def do_PUT(self):
        self.handle_request()

    def do_DELETE(self):
        self.handle_request()

    def handle_request(self):
        parts = urlsplit(self.path)
        path = parts.path
        if not path.startswith("/api/"):
            file = ROOT / "public" / path.lstrip("/")
            if not file.resolve().is_relative_to((ROOT / "public").resolve()):
                self.send_json({"error": "Not found"}, 404)
                return
            if path == "/privacy":
                file = ROOT / "privacy.html"
            elif path in ("/support", "/"):
                file = ROOT / "support.html" if path == "/support" else ROOT / "public/index.html"
            elif path == "/source.zip":
                file = ROOT / "source.zip"
            elif path == "/review":
                file = ROOT / "review.html"
            elif not file.is_file():
                file = ROOT / "public/index.html"
            base = ROOT.resolve()
            if not file.resolve().is_relative_to(base) or not file.is_file():
                self.send_json({"error": "Not found"}, 404)
                return
            raw = file.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mimetypes.guess_type(file)[0] or "application/octet-stream")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        body = {}
        if self.command != "GET":
            size = int(self.headers.get("Content-Length", 0))
            if size > 65536:
                self.send_json({"error": "Too large"}, 413)
                return
            try:
                body = json.loads(self.rfile.read(size) or b"{}")
            except ValueError:
                self.send_json({"error": "Invalid JSON"}, 400)
                return
            if not isinstance(body, dict):
                self.send_json({"error": "Expected JSON object"}, 400)
                return
        if path == "/api/health":
            self.send_json({"status": "ok", "version": "0.1.37", "demo": True})
            return
        if path == "/api/app/pair" and self.command == "POST":
            with LOCK:
                valid = CODES.pop(str(body.get("code", "")).upper(), 0) > time.time()
                if valid:
                    token = secrets.token_urlsafe(32)
                    device_id = secrets.randbelow(1000000000)
                    DEVICES[token] = dict(id=device_id, name=str(body.get("deviceName", "Review device"))[:100], createdAt="2026-10-02T00:00:00Z")
            self.send_json(dict(success=True, token=token, deviceId=device_id, serverVersion="0.1.37") if valid else {"error": "配对码已过期，请在 /review 页面生成新码"}, 200 if valid else 400)
            return
        key = self.headers.get("X-API-Key", "")
        token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        if key != KEY and token not in DEVICES:
            self.send_json({"error": "Unauthorized"}, 401)
            return
        account = parse_qs(parts.query).get("account", ["demo-eu"])[0]
        if account not in SERVERS:
            self.send_json({"error": "Unknown demonstration account"}, 400)
            return
        if path == "/api/app/pair-code":
            code = "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(8))
            CODES[code] = time.time() + 120
            self.send_json(dict(code=code, expiresAt=int(CODES[code]), qrContent="https://ovh-review.hejingcheng.com/api/app/pair#" + code))
            return
        if path == "/api/app/devices":
            self.send_json({"devices": list(DEVICES.values())})
            return
        if path.startswith("/api/app/devices/") and self.command == "DELETE":
            device_id = path.rsplit("/", 1)[-1]
            for existing, device in list(DEVICES.items()):
                if str(device["id"]) == device_id:
                    DEVICES.pop(existing, None)
            self.send_json({"success": True})
            return
        if self.command != "GET":
            if path.endswith(("/stop", "/start", "/reboot")):
                name = path.split("/")[-2]
                for row in VPS[account]:
                    if row["serviceName"] == name:
                        row["state"] = "stopped" if path.endswith("/stop") else "running"
            self.send_json({"success": True, "demo": True, "message": "演示操作已完成；未调用真实 OVH 服务。", "taskId": 1})
            return
        if path == "/api/accounts":
            result = {"accounts": ACCOUNTS}
        elif path == "/api/stats":
            result = dict(activeQueues=0, totalServers=3, availableServers=2, purchaseSuccess=0, purchaseFailed=0, queueProcessorRunning=False, monitorRunning=False)
        elif path == "/api/queue":
            result = QUEUE
        elif path == "/api/server-control/list":
            result = dict(success=True, servers=SERVERS[account], total=len(SERVERS[account]))
        elif path == "/api/vps-control/list":
            result = dict(success=True, vps=VPS[account], total=len(VPS[account]))
        elif path.endswith("/serviceinfo"):
            result = dict(success=True, serviceInfo=dict(status="ok", expiration="2026-12-01T00:00:00Z", creation="2026-09-01T00:00:00Z", renewalType=True, renewalPeriod=1, renewalDeleteAtExpiration=False, terminationScheduled=False, renewalForced=False, renewalManualPayment=False, possibleRenewPeriod=[1,3,6,12]))
        elif path.endswith("/hardware"):
            result = dict(success=True, hardware=dict(processorName="Intel Xeon E3-1230 v6", processorArchitecture="x86_64", coresPerProcessor=4, threadsPerProcessor=8, memorySize=dict(value=32768, unit="MB"), diskGroups=[]))
        elif path.endswith("/current-os"):
            result = dict(success=True, currentOS=dict(name="Debian 13", distribution="debian", bitFormat=64))
        elif path.endswith("/ips"):
            result = dict(success=True, ips=[dict(ipAddress="192.0.2.10", type="dedicated", version="v4")])
        elif path.endswith("/info") and "/vps-control/" in path:
            result = dict(success=True, info=next((v for v in VPS[account] if v["serviceName"] in path), {}))
        elif path.endswith("/network-interfaces"):
            result = dict(success=True, interfaces=[])
        elif path.endswith("/monitoring"):
            result = dict(success=True, monitoring=False)
        elif path.endswith("/tasks"):
            result = dict(success=True, tasks=[])
        elif path.endswith("/snapshots"):
            result = dict(success=True, snapshots=[])
        elif path.endswith("/templates"):
            result = dict(success=True, kind="templateId", templates=[])
        elif path in ("/api/history", "/api/logs", "/api/monitor", "/api/vps-monitor", "/api/notify/channels"):
            result = []
        elif path == "/api/servers":
            result = dict(servers=[])
        elif path == "/api/settings":
            result = dict(endpoint="ovh-eu", zone="FR", defaultRetryInterval=60, quickOrderRetryInterval=2)
        elif path == "/api/system/metrics":
            result = dict(cpu=dict(percent=5, cores=4), memory=dict(totalBytes=4294967296, usedBytes=1073741824, percent=25), disk=dict(totalBytes=42949672960, usedBytes=8589934592, percent=20, path="/demo"), host=dict(hostname="review-demo", platform="linux", uptimeSec=3600))
        elif path in ("/api/monitor/subscriptions", "/api/vps-monitor/subscriptions", "/api/ovh/account/refunds", "/api/ovh/account/email-history"):
            result = []
        elif path in ("/api/monitor/status", "/api/vps-monitor/status"):
            result = dict(running=False, interval=60, subscriptions=0, lastCheck=None)
        elif path == "/api/vps-monitor/models":
            result = dict(subsidiary="US", models=[])
        elif path == "/api/queue/timings":
            result = dict(timings={})
        elif path == "/api/version/check-update":
            result = dict(current="0.1.37", latest="0.1.37", tag="v0.1.37", name="Demo", hasUpdate=False, url="https://github.com/gokele/ovh", publishedAt="2026-10-02T00:00:00Z", body="", checkedAt="2026-10-02T00:00:00Z", prerelease=False, inContainer=True)
        elif path.endswith("/datacenter"):
            result = dict(success=True, datacenter=dict(name="OR", longName="Oregon", country="US"))
        elif path.endswith("/snapshot"):
            result = dict(success=True, snapshot=None)
        elif path.endswith("/engagement"):
            result = dict(success=True, engagement=None)
        elif path.endswith("/engagement/available"):
            result = dict(success=True, pricings=[])
        elif path.endswith("/engagement/request"):
            result = dict(success=True, request=None)
        elif path.endswith("/options"):
            result = dict(success=True, options=[])
        elif path.endswith("/mitigation"):
            result = dict(success=True, ips=[])
        elif path.endswith("/automated-backup"):
            result = dict(success=True, automatedBackup=None)
        elif path.endswith("/secondary-dns"):
            result = dict(success=True, domains=[])
        elif path.endswith("/interventions"):
            result = dict(success=True, interventions=[])
        elif path.endswith("/boot-mode"):
            result = dict(success=True, bootModes=[])
        elif path == "/api/server-control/aliases":
            result = {"aliases": {}}
        elif path in ("/api/version", "/api/update/check"):
            result = dict(version="0.1.37", currentVersion="0.1.37", latestVersion="0.1.37", hasUpdate=False, inContainer=True)
        elif path == "/api/queue/status":
            result = dict(running=False, processing=False)
        else:
            self.send_json({"error": "演示环境未配置此功能。真实面板的接口由你自己的部署提供。", "demo": True}, 404)
            return
        self.send_json(result)
