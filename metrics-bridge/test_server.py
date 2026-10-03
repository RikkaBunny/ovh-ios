import unittest
import io
from types import SimpleNamespace
from unittest.mock import patch
from server import Telemetry, UpstreamFailure, LocalCollector


class CollectorTests(unittest.TestCase):
    def test_proc_cpu_uses_all_cores_and_excludes_guest_double_counting(self):
        with patch('builtins.open', return_value=io.StringIO('cpu 100 0 20 800 20 0 0 10 500 500\ncpu0 0\ncpu1 0\n')):
            self.assertEqual(LocalCollector.cpu_sample(), (950, 820, 2))

    def test_kernel_sampling_and_bind_filesystem_values(self):
        collector = LocalCollector('/app')
        disk = SimpleNamespace(f_blocks=10000, f_bfree=4000, f_frsize=4096)
        with patch.object(collector, 'cpu_sample', side_effect=[(950, 820, 8), (1050, 840, 8)]), \
             patch('builtins.open', return_value=io.StringIO('MemTotal: 1000 kB\nMemAvailable: 400 kB\n')), \
             patch('server.os.statvfs', return_value=disk), patch('server.time.sleep'):
            value = collector()
            self.assertAlmostEqual(value['cpu']['percent'], 80)
            self.assertEqual(value['cpu']['cores'], 8)
            self.assertEqual(value['memory']['usedBytes'], 600 * 1024)
            self.assertEqual(value['disk']['percent'], 60)
            self.assertIs(collector(), value)


class TelemetryTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.revoked = False
        self.metrics = {k: {'percent': 10} for k in ('cpu', 'memory', 'disk')}
        def forward(path, headers):
            self.calls.append((path, headers))
            if self.revoked:
                raise UpstreamFailure(401)
            if path == '/accounts':
                return {'accounts': []}
            if path == '/system/metrics':
                return self.metrics
            if path == '/server-control/list?account=CA':
                return {'servers': [{'serviceName': 'panel.example'}]}
            if path == '/vps-control/list?account=US':
                return {'vps': [{'serviceName': 'vps.example'}]}
            return {'servers': []}
        self.telemetry = Telemetry('http://127.0.0.1:19998', 'panel.example', forward, lambda: self.metrics)
        self.auth = {'Authorization': 'Bearer synthetic-token'}

    def test_bound_host_requires_membership(self):
        status, value = self.telemetry.read('CA', 'panel.example', 'dedicated', self.auth)
        self.assertEqual(status, 200)
        self.assertEqual((value['account'], value['service'], value['kind']), ('CA', 'panel.example', 'dedicated'))
        self.assertEqual(value['metrics'], self.metrics)

    def test_other_account_cannot_read_host(self):
        status, _ = self.telemetry.read('EU', 'panel.example', 'dedicated', self.auth)
        self.assertEqual(status, 404)
        self.assertFalse(any(path == '/system/metrics' for path, _ in self.calls))

    def test_unmonitored_vps_never_uses_host_metrics(self):
        status, value = self.telemetry.read('US', 'vps.example', 'vps', self.auth)
        self.assertEqual(status, 200)
        self.assertEqual(value['status'], 'unavailable')
        self.assertNotIn('metrics', value)
        self.assertFalse(any(path == '/system/metrics' for path, _ in self.calls))

    def test_cached_ownership_does_not_bypass_revocation(self):
        self.telemetry.read('CA', 'panel.example', 'dedicated', self.auth)
        self.revoked = True
        self.assertEqual(self.telemetry.read('CA', 'panel.example', 'dedicated', self.auth)[0], 401)

    def test_cache_is_per_credential_and_account(self):
        self.telemetry.read('CA', 'panel.example', 'dedicated', self.auth)
        self.telemetry.read('CA', 'panel.example', 'dedicated', {'X-API-Key': 'another-synthetic-key'})
        self.assertEqual(sum(path.startswith('/server-control/list') for path, _ in self.calls), 2)

    def test_authentication_is_required_and_mutually_exclusive(self):
        for auth in ({}, {'Authorization': 'Basic abc'}, dict(self.auth, **{'X-API-Key': 'key'})):
            self.assertEqual(self.telemetry.read('CA', 'panel.example', 'dedicated', auth)[0], 401)

    def test_malformed_metrics_fail_instead_of_showing_zero(self):
        self.metrics = {'cpu': {}}
        self.assertEqual(self.telemetry.read('CA', 'panel.example', 'dedicated', self.auth)[0], 503)

    def test_upstream_cannot_be_user_controlled(self):
        with self.assertRaises(ValueError):
            Telemetry('https://external.example', 'panel.example')


if __name__ == '__main__':
    unittest.main()
