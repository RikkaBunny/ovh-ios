"""Authenticated instance telemetry extension for an existing gokele/ovh panel.

The panel-host collector is exposed ONLY for an explicitly configured service
that the selected OVH account owns. Other machines remain unknown. No SSH keys,
OVH credentials, or monitoring tokens are stored in this service.
"""
import hashlib
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


class UpstreamFailure(Exception):
    def __init__(self, status):
        self.status = status


class LocalCollector:
    """Kernel CPU/RAM and the filesystem backing the read-only app bind mount.

    This intentionally counts /proc CPUs rather than the Go container's CPU
    quota, and statvfs(/app) rather than the container's overlay filesystem.
    """
    def __init__(self, disk_path='/app'):
        self.disk_path = disk_path
        self.lock = threading.Lock()
        self.previous = None
        self.cached = None
        self.sampled = 0

    @staticmethod
    def cpu_sample():
        with open('/proc/stat') as f:
            lines = f.readlines()
        values = [int(v) for v in lines[0].split()[1:9]]
        return sum(values), values[3] + values[4], sum(line.startswith('cpu') and line[3:4].isdigit() for line in lines)

    def __call__(self):
        with self.lock:
            now = time.monotonic()
            if self.cached is not None and now - self.sampled < 1:
                return self.cached
            current = self.cpu_sample()
            if self.previous is None:
                self.previous = current
                time.sleep(.15)
                current = self.cpu_sample()
            delta = current[0] - self.previous[0]
            if delta <= 0:
                raise UpstreamFailure(503)
            cpu = max(0, min(100, 100 * (1 - (current[1] - self.previous[1]) / delta)))
            self.previous = current
            with open('/proc/meminfo') as f:
                memory = {line.split(':')[0]: int(line.split()[1]) * 1024 for line in f if ':' in line}
            total = memory['MemTotal']
            used = total - memory['MemAvailable']
            disk = os.statvfs(self.disk_path)
            disk_total = disk.f_blocks * disk.f_frsize
            disk_used = (disk.f_blocks - disk.f_bfree) * disk.f_frsize
            if total <= 0 or disk_total <= 0:
                raise UpstreamFailure(503)
            value = {
                'cpu': {'percent': cpu, 'cores': current[2]},
                'memory': {'percent': used / total * 100, 'usedBytes': used, 'totalBytes': total},
                'disk': {'percent': disk_used / disk_total * 100, 'usedBytes': disk_used, 'totalBytes': disk_total, 'path': self.disk_path},
            }
            self.cached, self.sampled = value, now
            return value


class Telemetry:
    def __init__(self, origin, panel_service, forward=None, collector=None):
        self.origin = origin.rstrip('/')
        parsed = urlsplit(self.origin)
        if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost') or parsed.path or parsed.query:
            raise ValueError('The panel upstream must be a fixed local HTTP origin')
        self.panel_service = panel_service
        self.forward = forward or self._forward
        self.collector = collector or LocalCollector()
        self.cache = {}
        self.lock = threading.Lock()

    def _forward(self, path, headers):
        # Fixed local destination; neither URLs nor credentials are logged.
        req = Request(self.origin + '/api' + path, headers=headers)
        try:
            with build_opener(NoRedirect).open(req, timeout=20) as response:
                raw = response.read(2 * 1024 * 1024 + 1)
                if len(raw) > 2 * 1024 * 1024:
                    raise UpstreamFailure(502)
                return json.loads(raw)
        except HTTPError as error:
            raise UpstreamFailure(error.code) from None
        except (URLError, TimeoutError, ValueError, OSError):
            raise UpstreamFailure(502) from None

    def read(self, account, service, kind, headers):
        if not account or not service or kind not in ('dedicated', 'vps') or len(account) > 128 or len(service) > 200:
            return 400, {'error': '请选择账户和有效实例'}
        if any(ord(c) < 32 for c in account + service):
            return 400, {'error': '实例参数无效'}
        authorization = headers.get('Authorization', '')
        api_key = headers.get('X-API-Key', '')
        if bool(authorization) == bool(api_key) or len(authorization + api_key) > 4096:
            return 401, {'error': '请先连接面板'}
        if authorization and (not authorization.startswith('Bearer ') or not authorization[7:].strip()):
            return 401, {'error': '设备授权无效'}
        auth = {'Accept': 'application/json'}
        auth['Authorization' if authorization else 'X-API-Key'] = authorization or api_key
        try:
            # Validate even cached requests, so revoked device tokens immediately
            # stop reading telemetry. Only the upstream handles authentication.
            self.forward('/accounts', auth)
            fingerprint = hashlib.sha256((authorization or api_key).encode()).hexdigest()
            key = (fingerprint, account, kind)
            now = time.monotonic()
            with self.lock:
                cached = self.cache.get(key)
                if cached and now - cached[0] < 30:
                    names = cached[1]
                else:
                    root = '/vps-control/list' if kind == 'vps' else '/server-control/list'
                    value = self.forward(root + '?' + urlencode({'account': account}), auth)
                    rows = value.get('vps' if kind == 'vps' else 'servers')
                    if not isinstance(rows, list):
                        raise UpstreamFailure(502)
                    names = {r.get('serviceName') for r in rows if isinstance(r, dict)}
                    self.cache = {k: v for k, v in self.cache.items() if now - v[0] < 30}
                    if len(self.cache) >= 256:
                        self.cache.clear()
                    self.cache[key] = (now, names)
            if service not in names:
                return 404, {'error': '该实例不属于当前账户'}
            envelope = {'scope': 'instance', 'account': account, 'service': service, 'kind': kind}
            if kind != 'dedicated' or not self.panel_service or service != self.panel_service:
                return 200, dict(envelope, status='unavailable', reason='INSTANCE_MONITORING_NOT_CONFIGURED')
            value = self.collector()
            if not isinstance(value, dict) or any(not isinstance(value.get(k), dict) for k in ('cpu', 'memory', 'disk')):
                raise UpstreamFailure(502)
            # The explicit deployment binding identifies the panel machine. Do
            # not infer ownership from an IP substring, alias, or account zone.
            return 200, dict(envelope, status='available', source='panel-host', metrics=value, sampledAt=int(time.time()))
        except UpstreamFailure as error:
            if error.status == 401:
                return 401, {'error': '设备授权已失效，请重新连接'}
            if error.status == 403:
                return 403, {'error': '当前授权没有读取实例资源的权限'}
            return 503, {'error': '实例资源读取失败，请稍后重试'}
        except (OSError, ValueError, KeyError, IndexError):
            return 503, {'error': '主机资源采样失败，请稍后重试'}


class Handler(BaseHTTPRequestHandler):
    telemetry = None

    def log_message(self, *_):
        pass

    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == '/health':
            status, data = 200, {'status': 'ok', 'version': 15}
        elif url.path == '/api/instance-metrics':
            query = parse_qs(url.query, keep_blank_values=True)
            if any(len(v) != 1 for v in query.values()):
                status, data = 400, {'error': '不支持重复的实例参数'}
            else:
                status, data = self.telemetry.read(
                    query.get('account', [''])[0], query.get('service', [''])[0],
                    query.get('kind', [''])[0], self.headers,
                )
        else:
            status, data = 404, {'error': '接口不存在'}
        raw = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(raw)


if __name__ == '__main__':
    Handler.telemetry = Telemetry(os.getenv('PANEL_ORIGIN', 'http://127.0.0.1:19998'), os.getenv('PANEL_HOST_SERVICE', ''))
    ThreadingHTTPServer(('127.0.0.1', int(os.getenv('PORT', '19997'))), Handler).serve_forever()
