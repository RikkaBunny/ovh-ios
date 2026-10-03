import argparse, json, pathlib, re, subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--upstream', required=True, type=pathlib.Path)
parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1]/'OVHPocket/NativeCatalog.json')
parser.add_argument('--audit', type=pathlib.Path, default=pathlib.Path(__file__).with_name('route-audit.json'))
args = parser.parse_args()
root = args.upstream.resolve()
commit = subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()
functions = {}
for path in (root / 'server/internal/handlers').glob('*.go'):
    if path.name.endswith('_test.go'): continue
    source = path.read_text()
    starts = list(re.finditer(r'^func (\w+)\(', source, re.M))
    for i, m in enumerate(starts):
        functions[m[1]] = (path.name, source[m.start():starts[i+1].start() if i+1<len(starts) else len(source)])

routes = []
for group, method, path, handler in re.findall(r'(api|sc|vc)\.(GET|POST|PUT|DELETE)\("([^\"]+)", handlers\.(\w+)\(', (root/'server/main.go').read_text()):
    path = {'api':'','sc':'/server-control','vc':'/vps-control'}[group] + path
    file, source = functions.get(handler, ('', ''))
    fields = []
    bind = re.search(r'ShouldBindJSON\(&(\w+)\)', source)
    if bind:
        var = bind[1]
        decl = re.search(r'var '+var+r' struct \{', source)
        if decl:
            body = source[decl.end():source.find('\n\t\t}', decl.end())]
            for name, typ, key, required in re.findall(r'(\w+)\s+([^\n`]+)\s+`json:"([^",]+)[^"\n]*"([^`]*)`', body):
                fields.append({'key':key,'type':typ.strip(),'required':'required' in required})
        elif re.search(r'var '+var+r' map\[string\]interface', source):
            for key in dict.fromkeys(re.findall(var+r'\["(\w+)"\]', source)):
                match = re.search(var+r'\["'+key+r'"\]\.\(([^)]+)\)', source)
                fields.append({'key':key,'type':match[1] if match else 'interface{}','required':False})
        else:
            decl = re.search(r'var '+var+r' (\w+\.\w+)',source)
            if decl: fields.append({'key':'$type','type':decl[1],'required':False})
    queries = list(dict.fromkeys(re.findall(r'c\.(?:Query|DefaultQuery)\("([^\"]+)"', source)))
    routes.append({'method':method,'path':path,'handler':handler,'file':file,'fields':fields,'query':queries})

args.audit.write_text(json.dumps(routes,ensure_ascii=False,indent=2))
print(len(routes), 'registered routes')
for r in routes:
    if r['method']!='GET': print(r['method'],r['path'],[(f['key'],f['type']) for f in r['fields']])

titles = {
 'list':'实例列表','aliases':'服务器别名','alias':'服务器别名','order-mapping':'订单对应关系','retraction':'撤回订单',
 'reboot':'重启','templates':'操作系统模板','install':'重装系统','install/status':'安装进度','tasks':'任务列表',
 'available-timeslots':'可预约时间','schedule':'预约任务时间','rescue':'救援模式','rescue/exit':'退出救援模式',
 'boot':'启动配置','monitoring':'硬件监控','boot-mode':'启动模式','hardware':'硬件信息','network-specs':'网络规格',
 'ips':'IP 地址','reverse':'反向 DNS','serviceinfo':'续费信息','serviceinfo/renewal':'续费策略',
 'engagement':'合同期','engagement/available':'可选合同期','engagement/request':'合同期变更','engagement/end-rule':'合同到期策略',
 'mitigation':'DDoS 防护','change-contact':'修改联系人','interventions':'维护记录','planned-interventions':'计划维护',
 'hardware/replace':'硬件更换','hardware-raid-profiles':'RAID 配置','hardware-disk-info':'磁盘信息','partition-schemes':'分区方案',
 'network-interfaces':'网卡接口','mrtg':'流量监控','ola/aggregation':'聚合网络接口','ola/reset':'重置网络聚合',
 'ola/group':'分组网络接口','ola/ungroup':'取消网络分组','console':'远程控制台','ipmi-types':'IPMI 访问方式',
 'statistics':'统计信息','network-stats':'网络统计','burst':'突发带宽','firewall':'硬件防火墙','backup-ftp':'FTP 备份',
 'backup-ftp/access':'FTP 访问权限','backup-ftp/password':'重置 FTP 密码','backup-ftp/authorizable-blocks':'可授权 IP 段',
 'backup-cloud':'云备份','backup-cloud/offer-details':'云备份套餐','backup-cloud/password':'重置云备份密码',
 'secondary-dns':'辅助 DNS','virtual-mac':'虚拟 MAC','virtual-network-interface':'虚拟网卡','vrack':'vRack',
 'orderable/bandwidth':'可选带宽','orderable/traffic':'可选流量','orderable/ip':'可选 IP','options':'附加服务',
 'ip-specs':'IP 规格','ip/can-be-moved-to':'IP 可迁移目标','ip/country-available':'IP 可用国家','ip/move':'迁移 IP',
 'ongoing':'进行中的操作','license/windows/compliant':'Windows 授权兼容性','license/windows-sql/compliant':'SQL Server 授权兼容性',
 'termination-policy':'服务终止策略','terminate':'立即终止服务','confirm-termination':'确认终止服务','spla':'SPLA 授权',
 'bios-settings':'BIOS 设置','bios-settings/sgx':'SGX 配置','info':'实例信息','status':'运行状态','datacenter':'数据中心',
 'start':'开机','stop':'关机','password':'重置密码','current-os':'当前操作系统','reinstall':'重装系统',
 'snapshot':'快照','snapshot/revert':'恢复快照','automated-backup':'自动备份',
 '/health':'连接状态','/settings':'API 设置','/verify-auth':'验证 API 凭据','/endpoint-config':'区域配置',
 '/logs':'详细日志','/logs/flush':'同步日志','/stats':'系统状态','/queue':'抢购队列','/queue/timings':'抢购耗时',
 '/queue/clear':'清空抢购队列','/purchase-history':'抢购历史','/purchase-history/refresh-status':'刷新订单付款状态',
 '/monitor/subscriptions':'服务器监控订阅','/monitor/subscriptions/batch-add-all':'监控全部机型','/monitor/subscriptions/clear':'清空服务器订阅',
 '/monitor/start':'启动服务器监控','/monitor/stop':'停止服务器监控','/monitor/status':'服务器监控状态','/monitor/interval':'服务器检查间隔',
 '/monitor/test-notification':'测试通知','/notify/channels':'通知通道','/telegram/verify':'验证 Telegram','/telegram/poller':'Telegram 状态',
 '/accounts/proxy-status':'代理状态','/servers':'服务器列表','/cache/info':'缓存状态','/cache/clear':'清理缓存',
 '/catalog':'产品目录','/system/metrics':'系统资源','/version':'后端版本','/app/pairing-codes':'生成配对码',
 '/app/devices':'配对设备','/version/check-update':'检查后端更新','/version/update':'更新后端','/version/update/status':'后端更新进度',
 '/accounts':'OVH 账户','/queue/quick-order':'快速抢购','/vps-monitor/models':'VPS 机型',
 '/vps-monitor/subscriptions':'VPS 补货订阅','/vps-monitor/subscriptions/clear':'清空 VPS 订阅',
 '/vps-monitor/start':'启动 VPS 监控','/vps-monitor/stop':'停止 VPS 监控','/vps-monitor/status':'VPS 监控状态',
 '/vps-monitor/interval':'VPS 检查间隔','/ovh/account/info':'账户资料','/ovh/refunds':'退款记录',
 '/ovh/credit-balance':'账户余额','/ovh/email-history':'邮件记录','/ovh/contact-change-requests':'联系人变更',
 '/ovh/account/sub-accounts':'子账户','/ovh/bills':'账单'
}
labels = dict(zip(
 'account_id accountId name endpoint zone appKey appSecret consumerKey iam setDefault proxyUrl fingerprint planCode datacenter datacenters options retryInterval autoPay status interval check_interval notifyAvailable notifyUnavailable autoOrder quantity autoOrderAccountId monitorLinux monitorWindows os ovhSubsidiary alias reason comment confirm templateName customHostname useProxmox9Zfs partitionSchemeName storageConfig zfsRaidLevel zfsVzSize wantedBeginingDate startDate hasPerformedBackup email sshKey bootId enabled monitoring ip reverse mode period pricingMode strategy contactAdmin contactTech contactBilling componentType disks inverse details slots virtualNetworkInterfaces virtualNetworkInterface ipBlock ftp nfs cifs cloudProjectId projectDescription domain ipAddress type virtualMachineName policy token futureUse commentary serialNumber templateId doNotSendPassword description option vrack task_id boot_id service_name subscription_id plan_code notifyWebhookUrl tgToken tgChatId defaultRetryInterval quickOrderRetryInterval'.split(),
 '下单账户|账户|名称|API 区域|账户站点|Application Key|Application Secret|Consumer Key|IAM|设为默认账户|代理地址|浏览器指纹|机型编码|数据中心|数据中心|配置选项|重试间隔（秒）|自动付款|状态|检查间隔（秒）|检查间隔（秒）|补货时通知|缺货时通知|自动抢购|每个机房数量|自动抢购账户|监控 Linux|监控 Windows|操作系统|账户站点|别名|原因|备注|确认执行|操作系统模板|主机名|Proxmox 9 ZFS 分区|分区方案|存储配置|ZFS RAID 级别|ZFS 数据分区大小（MB）|预约开始时间|开始时间|已完成备份|救援邮件地址|SSH 公钥|启动选项|启用|硬件监控|IP 地址|反向 DNS 域名|续费模式|续费周期（月）|合同套餐|合同到期策略|管理联系人|技术联系人|账单联系人|故障组件|磁盘|更换未列出的磁盘|故障详情|内存槽位|虚拟网卡列表|虚拟网卡|IP 段|FTP|NFS|CIFS|云项目 ID|云项目描述|域名|IP 地址|类型|虚拟机名称|终止策略|确认令牌|未来用途|备注|序列号|系统模板 ID|不发送密码邮件|描述|附加服务|vRack 名称|任务 ID|启动选项 ID|服务名称|订阅 ID|机型编码|Webhook 地址|Telegram Bot Token|Telegram Chat ID|默认重试间隔（秒）|快速抢购间隔（秒）'.split('|')))
labels.update({'timestamp':'时间','createdAt':'创建时间','updatedAt':'更新时间','expiration':'到期时间','serviceName':'服务名称','state':'状态','hardware':'硬件信息','serviceInfo':'服务信息','currentOS':'当前系统','ips':'IP 地址','currencyCode':'货币','withTax':'含税金额','withoutTax':'税前金额','priceWithTax':'含税金额','running':'运行中','lastStatus':'上次库存','level':'级别','message':'内容','source':'来源','orderId':'订单号','orderUrl':'订单链接','taskId':'任务 ID','retryCount':'尝试次数','failureCount':'失败次数','purchaseTime':'下单时间','orderStatus':'订单付款状态','price':'价格','cpu':'处理器','memory':'内存','storage':'硬盘','bandwidth':'带宽','processorName':'处理器','memorySize':'内存','distribution':'发行版','renew':'续费','automatic':'自动续费','forced':'合同锁定','deleteAtExpiration':'到期删除','manualPayment':'手动付款','name':'名称','snapshot':'快照','backup':'备份','email':'邮箱','firstname':'名','customerCode':'客户号','nichandle':'账户 ID','country':'国家','ovhSubsidiary':'账户站点','refundId':'退款 ID','date':'日期','subject':'主题','body':'正文','pdfUrl':'PDF 文件','value':'数值','unit':'单位','totalMs':'总耗时（毫秒）','timing':'各阶段耗时','error':'错误','success':'成功','tasks':'任务','templateName':'系统模板','templateId':'系统模板 ID'})
labels.update(dict(zip('block forceRefresh fromMonitor id intervention_id ip_block periodEnd periodStart showApiServers skipDuplicateCheck subsidiary verify disk_serial slot_id diskGroupId hardwareRaid partitioning layout mountPoint fileSystem raidLevel arrays spares disks'.split(),'IP 段|强制刷新|来自监控|编号|维护 ID|IP 段|结束日期|开始日期|包含 API 机型|跳过重复检查|账户站点|验证凭据|硬盘序列号|硬盘槽位|磁盘组 ID|硬件 RAID|分区配置|分区布局|挂载点|文件系统|RAID 级别|阵列数|备用磁盘数|磁盘数量'.split('|'))))
for suffix in ['refunds','credit-balance','email-history','bills']: titles['/ovh/account/'+suffix]=titles.get('/ovh/'+suffix,suffix)
titles.update({'/server-control/list':'服务器列表','/server-control/aliases':'服务器别名','/server-control/order-mapping':'订单对应关系','/vps-control/list':'VPS 列表'})

choices = {'endpoint':['ovh-eu','ovh-ca','ovh-us'],'mode':['auto','manual'],'policy':['empty','terminateAtExpirationDate','terminateAtEngagementDate'],'strategy':['REACTIVATE_ENGAGEMENT','STOP_ENGAGEMENT_FALLBACK_DEFAULT_PRICE','STOP_ENGAGEMENT_KEEP_PRICE','CANCEL_SERVICE'],'componentType':['hardDiskDrive','memory','cooling'],'zfsRaidLevel':['0','1'],'status':['active','inactive','inactiveLocked'],'cacheType':['memory','disk','all']}
def field(key, typ='string', location='body', required=False):
    typ=typ.replace('*','').strip().split()[-1]
    kind='list' if '[]' in typ else 'toggle' if 'bool' in typ else 'number' if typ.startswith(('int','float')) else 'text'
    if key in ['appSecret','consumerKey','tgToken','token']: kind='secret'
    if key in ['wantedBeginingDate','startDate','periodStart','periodEnd']: kind='date'
    if key in ['slots','virtualNetworkInterfaces','datacenters','options']: kind='list'
    if key in ['bootId','zfsVzSize','quantity','retryInterval','interval','check_interval']: kind='number'
    f={'key':key,'label':labels.get(key,key),'kind':kind,'location':location,'required':required}
    if key in choices: f['choices']=choices[key]
    return f

accountFields=[field(k,t) for k,t in [('name','string'),('endpoint','string'),('zone','string'),('appKey','string'),('appSecret','string'),('consumerKey','string'),('iam','string'),('setDefault','bool'),('proxyUrl','string'),('fingerprint','string')]]
configFields=[field(k,t) for k,t in [('appKey','string'),('appSecret','string'),('consumerKey','string'),('endpoint','string'),('zone','string'),('iam','string'),('tgToken','string'),('tgChatId','string'),('notifyWebhookUrl','string'),('defaultRetryInterval','int'),('quickOrderRetryInterval','int')]]
operations=[]
for r in routes:
    p,m=r['path'],r['method']
    if p.startswith('/internal/') or p == '/app/pair': continue
    asset=p.startswith(('/server-control/','/vps-control/')) and ':service_name' in p
    scope='dedicated' if asset and p.startswith('/server-control') else 'vps' if asset else 'panel'
    tail=p.split('/:service_name/')[-1] if asset else p
    base=re.sub(r'/(?:[:*]\w+)', '', tail)
    if asset:
        if 'available-timeslots' in tail: title='可预约时间'
        elif 'schedule' in tail: title='预约任务时间'
        elif base.startswith('interventions/'): title='维护详情'
        elif base.startswith('planned-interventions/'): title='计划维护详情'
        else: title=titles.get(base,titles.get(base.split('/')[0],base))
        group='电源' if base.split('/')[0] in ['reboot','start','stop','rescue','boot','boot-mode','monitoring','console','ipmi-types','install','reinstall','templates','current-os'] else '维护' if base.split('/')[0] in ['tasks','hardware','hardware-raid-profiles','hardware-disk-info','partition-schemes','interventions','planned-interventions','retraction'] else '概览' if base in ['info','status','hardware','network-specs','ips','serviceinfo','network-interfaces','mrtg','statistics','network-stats','datacenter'] else '高级'
    else:
        if p.startswith('/accounts/:id'):
            suffix=p.split('/:id')[-1]
            title={'':'OVH 账户','/verify':'验证凭据','/set-default':'设为默认账户','/proxy-test':'测试代理连通','/proxy-check':'检测代理出口'}.get(suffix,'账户操作')
        elif p.startswith('/queue/:id'): title={'/queue/:id':'抢购任务','/queue/:id/status':'任务状态','/queue/:id/interval':'任务重试间隔'}[p]
        elif p.startswith('/servers/') and p.endswith('/price'): title='配置价格'
        elif p.startswith('/availability/'): title='实时库存'
        elif p.startswith('/app/devices/'): title='配对设备'
        elif p.startswith('/vps-monitor/check/'): title='检查 VPS 库存'
        elif p.startswith('/ovh/contact-change-requests/'): title='联系人变更'+{'accept':'接受','refuse':'拒绝','resend-email':'重发邮件'}.get(p.split('/')[-1],'详情')
        elif '/subscriptions/' in p and ':' in p: title=('VPS ' if p.startswith('/vps') else '服务器')+('库存变化历史' if p.endswith('/history') else '监控订阅')
        else: title=titles.get(p,p)
        group='账户管理' if p.startswith('/ovh/') else 'OVH 账户' if p.startswith('/accounts') else 'App 配对' if p.startswith('/app') else '缓存管理' if p.startswith(('/cache','/catalog')) else '通知通道' if p.startswith(('/telegram','/notify','/monitor/test')) else '后端系统' if p.startswith(('/version','/system','/health')) else '抢购' if p.startswith(('/queue','/servers','/availability','/purchase')) else '监控' if p.startswith(('/monitor','/vps-monitor')) else '日志' if p.startswith('/logs') else 'API 设置'
    fs=[field(f['key'],f['type'],required=f['required']) for f in r['fields'] if f['key']!='$type']
    if r['handler'] in ['CreateAccount','UpdateAccount']: fs=accountFields
    if p=='/settings' and m=='POST': fs=configFields
    if p.endswith('/termination-policy') and m=='PUT': fs=[field('policy')]
    if p.endswith('/spla') and m=='POST':
        for f in fs:
            if f['key']=='type': f['choices']=['os','sqlstd','sqlweb']
    if p.endswith('/virtual-mac') and m=='POST':
        for f in fs:
            if f['key']=='type': f['choices']=['ovh','vmware']
    if p.endswith('/reinstall'):
        for f in fs:
            if f['key']=='templateId': f.update(kind='text',required=True)
    if p.endswith('/install'):
        for f in fs:
            if f['key']=='templateName': f['required']=True
    if p.endswith('/rescue'):
        for f in fs:
            if f['key']=='sshKey': f.update(kind='text',label='SSH 公钥')
    if p.endswith('/mrtg') or p.endswith('/statistics'):
        fs=[dict(field('period',location='query'),choices=['hourly','daily','weekly','monthly','yearly']),dict(field('type',location='query'),choices=['traffic:download','traffic:upload','packets:download','packets:upload','errors:download','errors:upload'])]
    if p.endswith('/console'):
        for f in fs:
            if f['key']=='type': f.pop('choices',None)
    if p.startswith('/availability/') and m=='POST': fs=[field('options','[]string')]
    if p.endswith('/hardware/replace'):
        for f in fs:
            if f['key']=='disks': f.update(kind='objects',children=[field('disk_serial',required=True),field('slot_id','int')])
    if p.endswith('/install'):
        for f in fs:
            if f['key']=='storageConfig': f.update(kind='objects',children=[field('diskGroupId','int'),dict(field('hardwareRaid'),kind='objects',children=[field('raidLevel','int'),field('disks','int'),field('arrays','int'),field('spares','int')]),dict(field('partitioning'),kind='object',children=[dict(field('layout'),kind='objects',children=[field('mountPoint',required=True),field('fileSystem',required=True),field('size','int'),field('raidLevel','int')])])])
            if f['key']=='zfsRaidLevel': f.update(kind='number',choices=['0','1','5','6','7','10'])
    # Both interval names are aliases; submit the documented current name only.
    if p=='/monitor/interval': fs=[field('interval','int',required=True)]
    if p.endswith('/monitoring') and m=='PUT': fs=[field('monitoring','bool',required=True)]
    if p.endswith('/tasks/:task_id/schedule'): fs=[f for f in fs if f['key']!='startDate']
    fs += [field(k,location='path',required=True) for k in re.findall(r'[:*](\w+)',p) if k!='service_name']
    fs += [field(k,location='query') for k in r['query'] if k not in ['account','ipBlock'] and not any(f['key']==k for f in fs) or k=='ipBlock' and 'ip_block' not in p and not any(f['key']==k for f in fs)]
    if not asset and p=='/cache/clear': fs[0]['choices']=['memory','sqlite','all']
    if p=='/queue/:id/status': fs[0]['choices']=['running','paused']
    danger= m=='DELETE' or any(x in base for x in ['terminate','retraction','install','snapshot/revert','hardware/replace','ola/reset','ola/ungroup'])
    prefix= '' if m=='GET' else '删除' if m=='DELETE' else '修改' if m=='PUT' else '创建' if base.endswith(('subscriptions','snapshot','accounts','secondary-dns','virtual-mac')) else ''
    operations.append(dict(id=m+' '+p,title=prefix+title,group=group,scope=scope,method=m,path=p,fields=fs,danger=danger,source=r['file'],handler=r['handler']))

target=args.output
subsidiaries=[dict(code=c,endpoint=e,label=l,currency=currency) for c,e,l,currency in re.findall(r'\{ code: "(\w+)", endpoint: "([\w-]+)", label: "([^\"]+)", currency: "(\w+)"', (root/'web/src/lib/ovh-subsidiaries.ts').read_text())]
target.write_text(json.dumps({'commit':commit,'operations':operations,'labels':labels,'subsidiaries':subsidiaries},ensure_ascii=False,indent=2))
print('Native catalog:',len(operations),'operations')
