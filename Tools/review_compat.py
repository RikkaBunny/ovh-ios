"""Synthetic v0.4.3 review routes. Never connects to OVH or real instances."""
import re
from datetime import datetime, timedelta, timezone
from review_release18 import handle_release18


def handle_review_compat(handler, path, query, body, subscriptions, queue=None):
    if queue is not None and handle_release18(handler, path, query, body, queue):
        return True
    if path == '/ovh/account/orders' and handler.command == 'GET':
        account = query.get('account', ['demo-eu'])[0]
        currency = {'demo-eu': 'EUR', 'demo-ca': 'CAD', 'demo-us': 'USD'}.get(account)
        if currency is None:
            handler.send_json({'error': 'Unknown demonstration account'}, 404)
        else:
            now = datetime.now(timezone.utc)
            handler.send_json([dict(orderId=123456, date=now.isoformat(),
                                    expirationDate=(now + timedelta(days=7)).isoformat(),
                                    url='https://example.invalid/demo-order',
                                    priceWithTax=dict(value=24.99, text=f'24.99 {currency}',
                                                      currencyCode=currency))])
        return True
    match = re.fullmatch(r'/monitor/subscriptions/([^/]+)/pause', path)
    if match and handler.command == 'POST':
        key = body.get('optionsKey', '')
        target = next((row for row in subscriptions
                       if row['planCode'] == match[1]
                       and (not key or ','.join(sorted(row.get('options', []))) == key)), None)
        if target is None:
            handler.send_json({'error': 'Demonstration subscription not found'}, 404)
        elif not isinstance(body.get('paused'), bool):
            handler.send_json({'error': 'paused must be boolean'}, 400)
        else:
            target['paused'] = body['paused']
            handler.send_json(dict(status='success', paused=target['paused']))
        return True
    return False
