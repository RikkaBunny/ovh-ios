"""Checks synthetic review state transitions and account isolation."""
import unittest
from review_release18 import STATE, handle_release18
from test_review_compat import Reply


class Review18Test(unittest.TestCase):
    def setUp(self):
        STATE.clear()
        self.queue = [dict(id='task', accountId='demo-eu', status='running', options=['original'])]

    def request(self, method, path, body=None, account='demo-eu'):
        reply = Reply(method)
        self.assertTrue(handle_release18(reply, path, {'account':[account]}, body or {}, self.queue))
        return reply

    def test_queue_requires_pause_preserves_identity_and_configuration(self):
        self.assertEqual(self.request('PUT', '/queue/task', dict(coupon='DEMO')).status, 409)
        self.request('PUT', '/queue/task/status', dict(status='paused'))
        self.request('PUT', '/queue/task', dict(coupon='DEMO', accountId='demo-us', id='other'))
        self.assertEqual(self.queue[0], dict(id='task', accountId='demo-eu', status='paused', options=['original'], coupon='DEMO'))
        self.assertEqual(self.request('PUT', '/queue/missing', dict(coupon='DEMO')).status, 404)

    def test_ticket_lifecycle_and_account_isolation(self):
        created = self.request('POST', '/ovh/support/tickets', dict(subject='Demo', body='Synthetic example', category='assistance', product='dedicated'))
        ident = created.body['result']['ticketId']
        path = '/ovh/support/tickets/' + ident
        self.assertEqual(self.request('GET', path, account='demo-us').status, 404)
        self.assertEqual(self.request('GET', '/ovh/support/tickets').body['total'], 1)
        self.request('POST', path, dict(action='reply', body='Demo reply'))
        self.assertEqual(len(self.request('GET', path).body['messages']), 2)
        self.request('POST', path, dict(action='close'))
        self.assertEqual(self.request('POST', path, dict(action='reply', body='Invalid')).status, 409)
        self.request('POST', path, dict(action='reopen'))
        self.assertEqual(self.request('GET', path).body['ticket']['state'], 'open')
        self.assertEqual(self.request('POST', '/ovh/support/tickets', dict(subject='x')).status, 400)

    def test_payment_is_regional_once_only_and_checks_confirmation(self):
        path = '/ovh/account/orders/123456/'
        for account, currency in [('demo-eu','EUR'),('demo-ca','CAD'),('demo-us','USD')]:
            info = self.request('GET', path+'payment', account=account).body
            self.assertEqual(info['currency'], currency)
            self.assertFalse(info['attempted'])
            body = dict(confirm=True, amount=24.99, currency=currency, paymentMethodId='demo-payment')
            self.assertEqual(self.request('POST', path+'pay', dict(body, confirm=False), account).status, 409)
            self.assertEqual(self.request('POST', path+'pay', body, account).status, 200)
            self.assertEqual(self.request('POST', path+'pay', body, account).status, 409)

    def test_rescue_ownership_stale_state_confirmation_and_exit(self):
        path = '/server-control/ns-demo-eu.example/rescue'
        self.assertEqual(self.request('GET', path, account='demo-us').status, 404)
        self.assertEqual(self.request('POST', path, dict(confirm=True, expectedBoot=2, useDefaultEmail=True)).status, 409)
        self.assertEqual(self.request('POST', path, dict(confirm=True, expectedBoot=1, email='')).status, 400)
        self.assertEqual(self.request('POST', path, dict(confirm=True, expectedBoot=1, email='qa@example.invalid')).status, 200)
        # The demo does not send this address anywhere; state change is synthetic.
        self.assertTrue(self.request('GET', path).body['rescueConfigured'])
        self.request('POST', path+'/exit', dict(confirm=True, expectedBoot=2))
        self.assertFalse(self.request('GET', path).body['rescueConfigured'])

    def test_renewal_and_retraction_have_observable_demo_state(self):
        root = '/server-control/ns-demo-eu.example/'
        self.request('PUT', root+'serviceinfo/renewal', dict(mode='manual', period=3))
        info = self.request('GET', root+'serviceinfo').body['serviceInfo']
        self.assertFalse(info['renewalType'])
        self.assertEqual(info['renewalPeriod'], 3)
        self.assertTrue(self.request('GET', root+'retraction').body['eligible'])
        self.request('POST', root+'retraction', dict(confirm=True, orderId=123456))
        self.assertFalse(self.request('GET', root+'retraction').body['eligible'])

    def test_chat_cannot_return_a_real_identity_and_unknown_routes_fall_through(self):
        reply = self.request('POST', '/ovh/support/chat/session', dict(product='vps'))
        self.assertEqual(reply.status, 501)
        self.assertNotIn('token', reply.body)
        self.assertFalse(handle_release18(Reply('GET'), '/accounts', {}, {}, []))
        for method, path in [('GET', '/queue/timings'), ('GET', '/queue/status'),
                             ('DELETE', '/queue/clear'), ('POST', '/queue/quick-order')]:
            self.assertFalse(handle_release18(Reply(method), path, {}, {}, []))


if __name__ == '__main__':
    unittest.main()
