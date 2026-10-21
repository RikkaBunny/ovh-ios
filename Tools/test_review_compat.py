import unittest
from review_compat import handle_review_compat


class Reply:
    def __init__(self, method):
        self.command = method
        self.body = None
        self.status = None

    def send_json(self, body, status=200):
        self.body, self.status = body, status


class ReviewCompatTest(unittest.TestCase):
    def test_exact_configuration_pause_preserves_other_subscription(self):
        rows = [dict(planCode='demo', options=['ram-a'], paused=False),
                dict(planCode='demo', options=['storage-b', 'ram-b'], paused=False)]
        reply = Reply('POST')
        self.assertTrue(handle_review_compat(reply, '/monitor/subscriptions/demo/pause', {},
                                            dict(optionsKey='ram-b,storage-b', paused=True), rows))
        self.assertEqual(reply.status, 200)
        self.assertFalse(rows[0]['paused'])
        self.assertTrue(rows[1]['paused'])
        handle_review_compat(reply, '/monitor/subscriptions/demo/pause', {},
                             dict(optionsKey='ram-b,storage-b', paused=False), rows)
        self.assertFalse(rows[1]['paused'])

    def test_missing_configuration_cannot_report_success(self):
        reply = Reply('POST')
        handle_review_compat(reply, '/monitor/subscriptions/demo/pause', {},
                             dict(optionsKey='missing', paused=True), [])
        self.assertEqual(reply.status, 404)

    def test_orders_have_regional_currency_and_no_credentials(self):
        for account, currency in [('demo-eu', 'EUR'), ('demo-ca', 'CAD'), ('demo-us', 'USD')]:
            reply = Reply('GET')
            handle_review_compat(reply, '/ovh/account/orders', {'account': [account]}, {}, [])
            self.assertEqual(reply.body[0]['priceWithTax']['currencyCode'], currency)
            self.assertNotIn('password', reply.body[0])
        reply = Reply('GET')
        handle_review_compat(reply, '/ovh/account/orders', {'account': ['real']}, {}, [])
        self.assertEqual(reply.status, 404)

    def test_other_routes_are_not_intercepted(self):
        self.assertFalse(handle_review_compat(Reply('GET'), '/accounts', {}, {}, []))


if __name__ == '__main__':
    unittest.main()
