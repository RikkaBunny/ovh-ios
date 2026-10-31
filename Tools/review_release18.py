"""In-memory App Review examples, never OVH API calls, messages or charges."""
from datetime import datetime, timedelta, timezone
import re
import threading

LOCK = threading.RLock()
STATE = {}
ACCOUNTS = {'demo-eu': 'EUR', 'demo-ca': 'CAD', 'demo-us': 'USD'}
SERVICES = {
    'demo-eu': ['ns-demo-eu.example', 'vps-demo-eu.example'],
    'demo-ca': ['ns-demo-ca.example'],
    'demo-us': ['vps-demo-us.example'],
}
MESSAGE = '演示操作已完成；未调用 OVH、未发送消息、未付款。'


def handle_release18(handler, path, query, body, queue):
    # Caller authenticates before this hook. Only explicitly listed routes match.
    recognized = (path.startswith('/ovh/support/') or
                  re.fullmatch(r'/ovh/account/orders/123456/(payment|pay)', path) or
                  re.fullmatch(r'/(server|vps)-control/[^/]+/(rescue(?:/exit)?|retraction|serviceinfo(?:/renewal)?)', path) or
                  (handler.command in ['PUT', 'DELETE'] and
                   path not in ['/queue/timings', '/queue/clear', '/queue/quick-order'] and
                   re.fullmatch(r'/queue/[^/]+(?:/status)?', path)))
    if not recognized:
        return False
    with LOCK:
        _handle(handler, path, query, body, queue)
    return True


def _handle(h, path, query, body, queue):
    account = query.get('account', ['demo-eu'])[0]
    if account not in ACCOUNTS:
        return h.send_json({'error': 'Unknown demonstration account'}, 404)
    state = STATE.setdefault(account, dict(tickets={}, paid=False, services={}))
    now = datetime.now(timezone.utc)
    future = (now + timedelta(days=7)).isoformat()
    ok = lambda **kw: h.send_json(dict(success=True, demo=True, message=MESSAGE, **kw))
    bad = lambda message, code=400: h.send_json(dict(error=message, demo=True), code)
    if path == '/ovh/support/chat/session':
        return bad('演示账户没有真实 OVH 聊天身份。请连接自己的后端及 OVH 账户使用官方客服。', 501)
    if path == '/ovh/support/options' and h.command == 'GET':
        return h.send_json(dict(accountId=account, categories=['assistance', 'billing', 'incident'],
                                products=['dedicated', 'vps'], subcategories=['other', 'down', 'perfs']))
    if path == '/ovh/support/services' and h.command == 'GET':
        return h.send_json(dict(accountId=account, services=SERVICES[account]))
    if path == '/ovh/support/tickets':
        if h.command == 'GET':
            items = list(state['tickets'].values())
            status, subject = query.get('status', [''])[0], query.get('subject', [''])[0]
            items = [t for t in items if (not status or t['state'] == status) and subject in t['subject']]
            return h.send_json(dict(accountId=account, items=items, total=len(items)))
        if h.command == 'POST':
            if not all(isinstance(body.get(k), str) and body[k].strip() for k in ['subject', 'body', 'category', 'product']):
                return bad('Missing ticket fields')
            if body.get('serviceName') and body['serviceName'] not in SERVICES[account]:
                return bad('Service not owned by demonstration account', 404)
            ticket_id = str(1000 + len(state['tickets']))
            ticket = dict(ticketId=ticket_id, subject=body['subject'][:200], state='open', canBeClosed=True,
                          category=body['category'], product=body['product'], creationDate=now.isoformat(),
                          messages=[dict(body=body['body'][:4000], from_='demo-customer', creationDate=now.isoformat())])
            state['tickets'][ticket_id] = ticket
            return ok(accountId=account, result=dict(ticketId=ticket_id))
    match = re.fullmatch(r'/ovh/support/tickets/([^/]+)', path)
    if match:
        ticket = state['tickets'].get(match[1])
        if ticket is None:
            return bad('Demonstration ticket not found', 404)
        if h.command == 'GET':
            return h.send_json(dict(accountId=account, ticket={k:v for k,v in ticket.items() if k != 'messages'}, messages=ticket['messages']))
        if h.command == 'POST':
            action = body.get('action')
            if action == 'reply' and ticket['state'] == 'open' and str(body.get('body', '')).strip():
                ticket['messages'].append(dict(body=str(body['body'])[:4000], creationDate=now.isoformat(), from_='demo-customer'))
            elif action == 'close' and ticket['state'] == 'open':
                ticket['state'] = 'closed'
            elif action == 'reopen' and ticket['state'] == 'closed':
                ticket['state'] = 'open'
            else:
                return bad('Invalid ticket state or missing reply body', 409)
            return ok(accountId=account, result=dict(ticketId=match[1]))
    if path.startswith('/ovh/account/orders/123456/'):
        currency = ACCOUNTS[account]
        if path.endswith('/payment') and h.command == 'GET':
            return h.send_json(dict(accountId=account, orderId=123456, status='delivered' if state['paid'] else 'notPaid',
                                    attempted=state['paid'], amount=24.99, currency=currency, priceText=f'24.99 {currency}',
                                    expirationDate=future, methods=[dict(id='demo-payment', type='creditCard', label='Synthetic payment (no charge)')]))
        if path.endswith('/pay') and h.command == 'POST':
            if state['paid'] or body.get('confirm') is not True or body.get('amount') != 24.99 or body.get('currency') != currency or body.get('paymentMethodId') != 'demo-payment':
                return bad('Invalid or already attempted demonstration payment', 409)
            state['paid'] = True
            return ok(accountId=account, orderId=123456)
    match = re.fullmatch(r'/(server|vps)-control/([^/]+)/(rescue(?:/exit)?|retraction|serviceinfo(?:/renewal)?)', path)
    if match:
        kind, service, action = match.groups()
        if service not in SERVICES[account] or (kind == 'vps') != service.startswith('vps-'):
            return bad('Service not owned by demonstration account', 404)
        resource = state['services'].setdefault(service, dict(boot=1, withdrawn=False, auto=True, period=1))
        if action == 'serviceinfo' and h.command == 'GET':
            return h.send_json(dict(success=True, accountId=account, serviceInfo=dict(status='ok', expiration=future, creation=now.isoformat(),
                                    renewalType=resource['auto'], renewalPeriod=resource['period'], renewalModes=['automatic', 'manual'],
                                    possibleRenewPeriod=[1,3,6,12], terminationScheduled=False)))
        if action == 'serviceinfo/renewal' and h.command == 'PUT':
            if body.get('mode') not in ['auto', 'manual'] or body.get('period', 1) not in [1,3,6,12]:
                return bad('Invalid renewal mode or period')
            resource.update(auto=body['mode'] == 'auto', period=body.get('period', resource['period']))
            return ok()
        if action == 'rescue' and h.command == 'GET':
            return h.send_json(dict(accountId=account, currentBoot=resource['boot'], rescueConfigured=resource['boot'] == 2, inRescue=resource['boot'] == 2))
        if action in ['rescue', 'rescue/exit'] and h.command == 'POST':
            if body.get('confirm') is not True or body.get('expectedBoot') != resource['boot']:
                return bad('Boot state changed or confirmation missing', 409)
            if action == 'rescue' and body.get('useDefaultEmail') is not True and not re.fullmatch(r'[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+', str(body.get('email', ''))):
                return bad('Full rescue email required')
            resource['boot'] = 1 if action.endswith('/exit') else 2
            return ok(taskId=1)
        if action == 'retraction' and h.command == 'GET':
            return h.send_json(dict(accountId=account, orderId=123456, orderDate=now.isoformat(), retractionDate=future, eligible=not resource['withdrawn']))
        if action == 'retraction' and h.command == 'POST':
            if resource['withdrawn'] or body.get('confirm') is not True or body.get('orderId') != 123456:
                return bad('Withdrawal not eligible or not confirmed', 409)
            resource['withdrawn'] = True
            return ok()
    match = re.fullmatch(r'/queue/([^/]+)(/status)?', path)
    if match:
        item = next((row for row in queue if str(row['id']) == match[1]), None)
        if item is None:
            return bad('Demonstration queue item not found', 404)
        if h.command == 'DELETE' and not match[2]:
            queue.remove(item)
            return ok()
        if h.command == 'PUT':
            if match[2]:
                if body.get('status') not in ['paused', 'running'] or item.get('status') == 'completed':
                    return bad('Invalid task state', 409)
                item['status'] = body['status']
            else:
                if item.get('status') not in ['paused', 'failed']:
                    return bad('Pause the task before editing', 409)
                item.update({k:v for k,v in body.items() if k in ['datacenter', 'options', 'retryInterval', 'autoPay', 'coupon']})
                item['status'] = 'paused'
            return ok()
    return bad('Demonstration route or method not supported', 404)
