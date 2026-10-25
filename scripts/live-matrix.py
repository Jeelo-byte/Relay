"""Local live-test controls. Credentials stay in ignored private files; never printed."""
import argparse, hashlib, hmac, json, os, pathlib, secrets
import requests, yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
PRIVATE = ROOT / 'infra/matrix/private'
BASE = 'http://127.0.0.1:8008'

def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2))
    path.chmod(0o600)

def account():
    return json.loads((PRIVATE / 'relay-account.json').read_text())

def request(method, path, data=None):
    response = requests.request(method, BASE + '/_matrix/client/v3/' + path,
        headers={'Authorization': 'Bearer ' + account()['access_token']}, json=data, timeout=35)
    if not response.ok:
        raise RuntimeError('Matrix request failed: HTTP ' + str(response.status_code))
    return response.json() if response.content else {}

def configure():
    password = (PRIVATE / 'runtime.env').read_text().strip().split('=', 1)[1]
    home = PRIVATE / 'synapse/homeserver.yaml'
    config = yaml.safe_load(home.read_text())
    config['enable_registration'] = False
    config['report_stats'] = False
    config['registration_shared_secret'] = config.get('registration_shared_secret') or secrets.token_urlsafe(48)
    config['database'] = {'name':'psycopg2', 'args':{'user':'relay','password':password,'database':'synapse','host':'postgres','cp_min':5,'cp_max':10}}
    config['listeners'] = [{'port':8008,'tls':False,'type':'http','x_forwarded':False,'bind_addresses':['0.0.0.0'], 'resources':[{'names':['client'],'compress':False}]}]
    config['trusted_key_servers'] = []
    double_path = PRIVATE / 'synapse/doublepuppet.yaml'
    if double_path.exists():
        dp = yaml.safe_load(double_path.read_text())
    else:
        dp = {'id':'relay-doublepuppet','url':None,'as_token':secrets.token_urlsafe(48),
              'hs_token':secrets.token_urlsafe(48),'sender_localpart':'relay_doublepuppet',
              'rate_limited':False,'namespaces':{'users':[{'regex':r'@relay:relay\.local','exclusive':False}]}}
        double_path.write_text(yaml.safe_dump(dp,sort_keys=False)); double_path.chmod(0o600)
    config['app_service_config_files'] = ['/data/whatsapp-registration.yaml','/data/doublepuppet.yaml']
    home.write_text(yaml.safe_dump(config, sort_keys=False)); home.chmod(0o600)
    bridge = PRIVATE / 'whatsapp/config.yaml'
    c = yaml.safe_load(bridge.read_text())
    c['homeserver'].update(address='http://synapse:8008', domain='relay.local')
    c['appservice'].update(address='http://whatsapp:29318',hostname='0.0.0.0',port=29318)
    for key in ['as_token','hs_token']:
        if c['appservice'].get(key) in [None,'','generate','This value is generated when generating the registration']: c['appservice'][key] = secrets.token_urlsafe(48)
    c['database'].update(type='postgres',uri=f'postgres://relay:{password}@postgres/whatsapp?sslmode=disable')
    c['bridge']['permissions'] = {'@relay:relay.local':'admin'}
    c['bridge']['portal_create_filter'].update(mode='allow',list=[])
    c['network']['history_sync']['max_initial_conversations'] = 0
    c['network']['history_sync']['request_full_sync'] = False
    c['backfill'].update(enabled=False,max_initial_messages=0,max_catchup_messages=0)
    c['backfill']['queue'].update(enabled=False,manual=False)
    c['encryption'].update(allow=False,default=False,require=False)
    c['double_puppet']['servers'] = {}
    c['double_puppet']['secrets'] = {'relay.local':'as_token:' + dp['as_token']}
    c['logging'] = {'min_level':'warn','writers':[{'type':'stdout','format':'json'}]}
    bridge.write_text(yaml.safe_dump(c, sort_keys=False)); bridge.chmod(0o600)
    print('Configured PostgreSQL, local-only Synapse, and WhatsApp. No chats allowed; history backfill off.')

def register():
    path = PRIVATE / 'relay-account.json'
    if path.exists():
        request('GET','account/whoami'); print('Existing local account verified.'); return
    c = yaml.safe_load((PRIVATE/'synapse/homeserver.yaml').read_text())
    endpoint = BASE + '/_synapse/admin/v1/register'
    nonce = requests.get(endpoint,timeout=10).json()['nonce']
    password = secrets.token_urlsafe(32)
    mac = hmac.new(c['registration_shared_secret'].encode(), '\0'.join([nonce,'relay',password,'admin']).encode(), hashlib.sha1).hexdigest()
    r = requests.post(endpoint,json={'nonce':nonce,'username':'relay','password':password,'admin':True,'mac':mac},timeout=20)
    if not r.ok: raise RuntimeError('Account registration failed: HTTP ' + str(r.status_code))
    save(path, {'server':BASE,'password':password,**r.json()})
    print('Local Relay account created. Credentials saved privately.')

def login_room():
    state = PRIVATE / 'live-test.json'
    s = json.loads(state.read_text()) if state.exists() else {}
    if not s.get('management_room'):
        room = request('POST','createRoom', {'preset':'private_chat','invite':['@whatsappbot:relay.local'],'is_direct':True,'name':'Relay · WhatsApp setup'})
        s['management_room'] = room['room_id'];save(state,s)
    request('PUT', 'rooms/' + requests.utils.quote(s['management_room'],safe='') + '/send/m.room.message/' + secrets.token_hex(12), {'msgtype':'m.text','body':'login qr'})
    print('Requested WhatsApp login QR from the local bridge bot.')

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('command',choices=['configure','register','login-qr']);args=p.parse_args()
    {'configure':configure,'register':register,'login-qr':login_room}[args.command]()
