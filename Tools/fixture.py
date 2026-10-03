"""Local HTTPS QA service. All inventory and effects are synthetic."""
import importlib.util, pathlib, json, re, ssl, time, uuid
from http.server import ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs, unquote

ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('review',pathlib.Path(__file__).with_name('fixture_base.py'))
review=importlib.util.module_from_spec(spec); spec.loader.exec_module(review)
CAT=json.loads((ROOT/'OVHPocket/NativeCatalog.json').read_text())
PLANS=[dict(planCode='24ks-le-b',name='KS-LE-B',description='Intel Xeon · 双 NVMe',cpu='E3-1230v6 · 4 核 / 8 线程',memory='32 GB DDR4',storage='2 × 1.92 TB NVMe',bandwidth='1 Gbps',vrackBandwidth='100 Mbps',defaultOptions=[dict(label='32 GB',value='ram-32g-ddr4',family='memory'),dict(label='2 × 1.92 TB NVMe',value='softraid-2x1920nvme',family='storage')],availableOptions=[dict(label='32 GB DDR4',value='ram-32g-ddr4',family='memory'),dict(label='64 GB DDR4',value='ram-64g-ddr4',family='memory'),dict(label='2 × 1.92 TB NVMe',value='softraid-2x1920nvme',family='storage')],datacenters=[dict(datacenter='gra',availability='1H',countryCode='FR'),dict(datacenter='bhs',availability='unavailable',countryCode='CA')]),dict(planCode='25sys-1',name='SYS-1',cpu='AMD EPYC · 8 核',memory='64 GB',storage='2 × 960 GB SSD',bandwidth='1 Gbps',defaultOptions=[],availableOptions=[],datacenters=[dict(datacenter='gra',availability='comingSoon',countryCode='FR')])]
QUEUE=[]
SUBS=[dict(planCode='24ks-le-b',serverName='KS-LE-B',datacenters=['gra'],notifyAvailable=True,notifyUnavailable=False,autoOrder=False,autoPay=False,quantity=1,autoOrderAccountId='demo-eu',options=['ram-32g-ddr4','softraid-2x1920nvme'],lastStatus={'gra':'1H','bhs':'unavailable'},createdAt='2026-10-02T08:00:00Z')]
VPS_SUBS=[]
CONFIG=dict(appKey='qa-app-key',appSecret='qa-app-secret',consumerKey='qa-consumer',endpoint='ovh-eu',zone='FR',iam='go-ovh-fr',tgToken='qa-telegram',tgChatId='qa-chat',notifyWebhookUrl='https://example.invalid/notify',defaultRetryInterval=60,quickOrderRetryInterval=2)
METRICS_MODE='ok'
METRICS_REQUESTS=0
INVENTORY = dict(mode='ok', delay=0, requests=0, completed=0, forced=0)
REFRESH = dict(mode='ok', delay=0, marker=0, started={}, completed={})
READ_PATHS = {'/accounts', '/stats', '/queue', '/server-control/list', '/vps-control/list', '/system/metrics', '/instance-metrics', '/monitor/subscriptions', '/monitor/status', '/logs', '/purchase-history', '/ovh/account/info', '/app/devices'}

def inventory_request(query):
    # Snapshot controls so switching modes cannot alter an already pending response.
    state = dict(INVENTORY)
    INVENTORY['requests'] += 1
    if query.get('forceRefresh') == ['true']: INVENTORY['forced'] += 1
    time.sleep(state['delay'])
    INVENTORY['completed'] += 1
    return state

class Handler(review.Handler):
    def handle_request(self):
        global METRICS_MODE, METRICS_REQUESTS
        u=urlsplit(self.path); path=unquote(u.path.removeprefix('/api')); query=parse_qs(u.query)
        if u.path=='/qa/availability':
            state = inventory_request(query)
            if state['mode']=='error': return self.send_json(dict(error='QA stock temporarily unavailable'),503)
            return self.send_json([dict(planCode=p['planCode'],fqn=p['planCode']+'.ram-32g-ddr4.softraid-2x1920nvme',datacenters=p['datacenters']) for p in PLANS])
        token=self.headers.get('Authorization','').removeprefix('Bearer ')
        if path=='/app/pair' or (self.headers.get('X-API-Key') != review.KEY and token not in review.DEVICES):
            return super().handle_request()
        refresh_state = dict(REFRESH)
        if self.command == 'GET' and (path in READ_PATHS or path.endswith(('/serviceinfo','/hardware','/current-os','/ips'))):
            label = path + '|' + query.get('account', ['global'])[0]
            REFRESH['started'][label] = REFRESH['started'].get(label, 0) + 1
            time.sleep(refresh_state['delay'])
            REFRESH['completed'][label] = REFRESH['completed'].get(label, 0) + 1
            if refresh_state['mode'] == 'error': return self.send_json(dict(error='QA refresh temporarily unavailable'), 503)
            if path in ['/server-control/list','/vps-control/list']:
                account = query.get('account', [review.ACCOUNTS[0]['id']])[0]
                key = 'servers' if path == '/server-control/list' else 'vps'
                source = review.SERVERS if key == 'servers' else review.VPS
                rows = [dict(row, **{('name' if key == 'servers' else 'displayName'):row.get('name', row.get('displayName', row['serviceName'])) + (('-refresh-' + str(refresh_state['marker'])) if refresh_state['marker'] else '')}) for row in source[account]]
                return self.send_json(dict(success=True, **{key:rows}))
            if path.endswith('/hardware') and refresh_state['marker']:
                return self.send_json(dict(success=True,hardware=dict(processorName='QA CPU refresh '+str(refresh_state['marker']),memorySize=dict(value=32768,unit='MB'))))
        if path in ['/accounts','/server-control/list','/vps-control/list','/app/devices'] or path.startswith('/app/devices/') or path.endswith(('/serviceinfo','/hardware','/current-os','/ips')):
            return super().handle_request()
        body={}
        if self.command!='GET':
            size=int(self.headers.get('Content-Length',0)); body=json.loads(self.rfile.read(size) or b'{}')
        if path=='/qa/refresh':
            if self.command=='POST': REFRESH.update(mode=body.get('mode','ok'), delay=min(10,max(0,body.get('delay',0))), marker=body.get('marker',0), started={}, completed={})
            return self.send_json(REFRESH)
        if path=='/qa/metrics':
            if self.command=='POST': METRICS_MODE=body.get('mode','ok')
            return self.send_json(dict(mode=METRICS_MODE,requests=METRICS_REQUESTS))
        if path=='/qa/inventory':
            if self.command=='POST':
                INVENTORY.update(mode=body.get('mode','ok'), delay=min(10, max(0, body.get('delay',0))), requests=0, completed=0, forced=0)
            return self.send_json(INVENTORY)
        if path=='/system/metrics':
            METRICS_REQUESTS+=1
            if METRICS_MODE=='error': return self.send_json(dict(error='QA metrics temporarily unavailable'),503)
            if METRICS_MODE=='malformed': return self.send_json(dict(success=True))
            return self.send_json(dict(cpu=dict(percent=37.5,cores=8),memory=dict(totalBytes=32*1024**3,usedBytes=16*1024**3,percent=50),disk=dict(totalBytes=2*1024**4,usedBytes=1.4*1024**4,percent=70,path='/'),host=dict(hostname='qa-panel',platform='debian',uptimeSec=86400)))
        if path=='/instance-metrics':
            account=query.get('account',[''])[0]; service=query.get('service',[''])[0]; kind=query.get('kind',[''])[0]
            rows=(review.VPS if kind=='vps' else review.SERVERS).get(account,[])
            if not any(row['serviceName']==service for row in rows): return self.send_json(dict(error='Instance not owned by account'),404)
            envelope=dict(scope='instance',account=account,service=service,kind=kind)
            METRICS_REQUESTS+=1
            if METRICS_MODE=='error': return self.send_json(dict(error='QA metrics temporarily unavailable'),503)
            if METRICS_MODE=='malformed': return self.send_json(dict(cpu={},memory={},disk={}))
            if METRICS_MODE=='unavailable': return self.send_json(dict(envelope,status='unavailable',reason='INSTANCE_MONITORING_NOT_CONFIGURED'))
            pct={'demo-eu':37.5,'demo-ca':12,'demo-us':8}.get(account,0)+(3 if kind=='vps' else 0)
            return self.send_json(dict(envelope,status='available',metrics=dict(cpu=dict(percent=pct,cores=2 if kind=='vps' else 8),memory=dict(totalBytes=4*1024**3,usedBytes=2*1024**3,percent=50),disk=dict(totalBytes=40*1024**3,usedBytes=20*1024**3,percent=50,path='/'))))
        if path.startswith('/accounts/') and path.count('/')==2:
            account=next((a for a in review.ACCOUNTS if a['id']==path.split('/')[-1]),None)
            if not account: return self.send_json({'error':'Unknown account'},404)
            if self.command=='PUT': account.update({k:v for k,v in body.items() if k not in ['appKey','appSecret','consumerKey']})
            return self.send_json(dict(account,appKey='••••••••',appSecret='••••••••',consumerKey='••••••••',proxyUrl=account.get('proxyUrl','')))
        if path=='/stats': return self.send_json(dict(activeQueues=len(QUEUE),totalServers=refresh_state['marker'] or len(PLANS),availableServers=1,purchaseSuccess=1,purchaseFailed=0,queueProcessorRunning=True,monitorRunning=True))
        if path=='/servers':
            state=inventory_request(query)
            if state['mode']=='error': return self.send_json(dict(error='QA catalog temporarily unavailable'),503)
            expired=state['mode']=='expired' and query.get('forceRefresh') != ['true']
            result={'servers':PLANS,'cacheInfo':dict(timestamp=time.time()-(225*60 if expired else 0),cacheAgeMinutes=225 if expired else 0,usingExpiredCache=expired)}
            if not expired: return self.send_json(result)
            raw=json.dumps(result).encode()
            self.send_response(200); self.send_header('Content-Type','application/json')
            self.send_header('X-Cache-Warning','Using expired cache (225 minutes old)')
            self.send_header('Content-Length',str(len(raw))); self.end_headers(); self.wfile.write(raw)
            return
        if path=='/catalog':
            state=inventory_request(query)
            if state['mode']=='error': return self.send_json(dict(error='QA prices temporarily unavailable'),503)
            def pricing(amount,tax=0,install=False): return dict(intervalUnit='month',interval=1,mode='default',price=int(amount*1e8),tax=int(tax*1e8),capacities=['installation' if install else 'renew'])
            currency={'CA':'CAD','US':'USD'}.get(query.get('subsidiary',['FR'])[0],'EUR')
            return self.send_json(dict(locale=dict(currencyCode=currency),plans=[dict(planCode=p['planCode'],pricings=[pricing(10,2,True),pricing(20.83,4.16)]) for p in PLANS],addons=[dict(planCode='ram-32g-ddr4',pricings=[pricing(0)]),dict(planCode='ram-64g-ddr4',pricings=[pricing(5,1)]),dict(planCode='softraid-2x1920nvme',pricings=[pricing(0)])]))
        if path.startswith('/availability/'): return self.send_json({'gra':'1H','bhs':'unavailable'})
        if path.endswith('/price'): return self.send_json(dict(success=True,price=dict(withTax=24.99,withoutTax=20.83,tax=4.16,currencyCode='EUR')))
        if path=='/queue':
            if self.command=='GET': return self.send_json(QUEUE)
            if body.get('account_id') not in [a['id'] for a in review.ACCOUNTS] or not body.get('planCode') or not body.get('datacenter'): return self.send_json({'error':'Missing valid order target'},400)
            item=dict(id=str(uuid.uuid4()),accountId=body['account_id'],planCode=body['planCode'],datacenter=body['datacenter'],options=body.get('options',[]),status='running',retryInterval=body.get('retryInterval',60),retryCount=0,autoPay=body.get('autoPay',False),createdAt='2026-10-02T08:00:00Z',updatedAt='2026-10-02T08:00:00Z')
            QUEUE.append(item); return self.send_json(dict(status='success',id=item['id']))
        if path.startswith('/queue/'):
            parts=path.split('/'); item=next((i for i in QUEUE if i['id']==parts[2]),None)
            if item and self.command=='PUT': item.update(body)
            if item and self.command=='DELETE': QUEUE.remove(item)
            return self.send_json({'success':True})
        if path=='/settings':
            if self.command=='POST':
                if any(k not in body for k in CONFIG): return self.send_json({'error':'Config replacement must preserve all fields'},400)
                CONFIG.update(body)
            return self.send_json(CONFIG)
        if path.endswith('/models'): return self.send_json(dict(subsidiary='FR',models=[dict(planCode='vps-2026-1',name='VPS-1',generation=2026,datacenters=['GRA','BHS'],osChoices=['debian13','ubuntu2404'])]))
        if path.endswith('/subscriptions'):
            rows=VPS_SUBS if path.startswith('/vps') else SUBS
            if self.command=='POST': rows.append(dict(body,id=str(uuid.uuid4()),lastStatus={},createdAt='2026-10-02T08:00:00Z'))
            return self.send_json(rows)
        if path in ['/monitor/status','/vps-monitor/status']: return self.send_json(dict(running=True,subscriptions_count=len(SUBS),check_interval=60,known_servers_count=2))
        if '/subscriptions/' in path and self.command=='PUT':
            rows=VPS_SUBS if path.startswith('/vps') else SUBS
            target=next((i for i in rows if i.get('id')==path.split('/')[-1] or i['planCode']==path.split('/')[-1]),None)
            if target: target.update(body)
            return self.send_json(dict(status='success',message='订阅已更新'))
        if path.endswith('/history'): return self.send_json([dict(timestamp='2026-10-02T08:00:00Z',datacenter='gra',status='1H',changeType='available',oldStatus='unavailable')])
        if path=='/purchase-history': return self.send_json([dict(id='qa-order',accountId='demo-eu',planCode='24ks-le-b',datacenter='gra',status='success',orderId=123456,orderStatus='notPaid',orderUrl='https://example.invalid/order',purchaseTime='2026-10-02T08:00:00Z',attemptCount=3,price=dict(withTax=24.99,withoutTax=20.83,tax=4.16,currencyCode='EUR'),timing=[dict(name='cart',ms=150),dict(name='checkout',ms=200)],totalMs=350)])
        if path=='/logs': return self.send_json([dict(id='qa-log',timestamp='2026-10-02T08:00:00Z',level='INFO',message=('QA log refresh '+str(refresh_state['marker'])) if refresh_state['marker'] else '监控已启动；GRA 库存变为 1H。',source='monitor')])
        if path=='/ovh/account/info': return self.send_json(dict(customerCode='qa001',nichandle='qa001-ovh',email='qa@example.invalid',name='演示账户',country='FR',currency=dict(code='EUR',symbol='€'),ovhSubsidiary='FR'))
        if path.endswith('/templates'): return self.send_json(dict(success=True,templates=[dict(id='debian-13-image' if path.startswith('/vps') else 13,templateName='debian13_64',distribution='Debian 13',bitFormat=64),dict(id='ubuntu-24-image' if path.startswith('/vps') else 24,templateName='ubuntu2404_64',distribution='Ubuntu 24.04',bitFormat=64)]))
        if path.endswith('/mrtg'):
            data=[dict(timestamp=time.time()-i*3600,value=dict(value=(i%5+1)*1000000,unit='bps')) for i in range(24)]
            return self.send_json(dict(success=True,interfaces=[dict(mac='aa:bb:cc:dd:ee:ff',data=data)]))
        if path.endswith('/boot-mode') or path.endswith('/boot'): return self.send_json(dict(success=True,bootModes=[dict(bootId=1,bootType='harddisk',description='从硬盘启动'),dict(bootId=2,bootType='rescue',description='救援模式')]))
        if path.endswith('/snapshot'): return self.send_json(dict(success=True,snapshot=dict(description='安装前备份',creationDate='2026-10-01T00:00:00Z',status='available')))
        if path.endswith('/tasks'): return self.send_json(dict(success=True,tasks=[dict(taskId=1,function='reinstallServer',status='done',startDate='2026-10-01T00:00:00Z')]))
        if path.endswith('/ipmi-types'): return self.send_json(dict(success=True,supportedTypes=['kvmipHtml5URL'],defaultType='kvmipHtml5URL'))
        if path=='/app/pairing-codes':
            code=''.join(review.secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(8)); review.CODES[code]=time.time()+120
            return self.send_json(dict(success=True,code=code,expiresAt=int(review.CODES[code]),qrContent='https://localhost:16443/api/app/pair#'+code))
        for op in CAT['operations']:
            pattern='^'+re.sub(r'[:*]\w+',r'[^/]+',op['path'])+'$'
            if op['method']==self.command and re.match(pattern,path):
                if self.command!='GET': return self.send_json(dict(success=True,message='演示操作已完成',taskId=1))
                return self.send_json(dict(success=True,items=[],message='当前没有记录'))
        return self.send_json({'error':'No QA route'},404)

if __name__=='__main__':
    server=ThreadingHTTPServer(('127.0.0.1',16443),Handler)
    ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(str(pathlib.Path(__file__).with_name('localhost.crt')),str(pathlib.Path(__file__).with_name('localhost.key')))
    server.socket=ctx.wrap_socket(server.socket,server_side=True)
    print('Local native QA HTTPS ready',flush=True); server.serve_forever()
