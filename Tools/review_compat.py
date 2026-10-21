"""Synthetic v0.4.3 review routes. Never connects to OVH or real instances."""
import re


def handle_review_compat(handler, path, query, body, subscriptions):
    if path == '/ovh/account/orders' and handler.command == 'GET':
        account = query.get('account', ['demo-eu'])[0]
        currency = {'demo-eu': 'EUR', 'demo-ca': 'CAD', 'demo-us': 'USD'}.get(account)
        if currency is None:
            handler.send_json({'error': 'Unknown demonstration account'}, 404)
        else:
            handler.send_json([dict(orderId=123456, date='2026-10-21T08:00:00Z',
                                    expirationDate='2026-10-22T08:00:00Z',
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
