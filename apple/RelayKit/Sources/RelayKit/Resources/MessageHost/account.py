"""Executed inside Synapse. stdout is consumed privately by Relay, never logged."""
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import time
import urllib.request
import yaml

BASE = 'http://127.0.0.1:8008'
path = Path('/data/relay-account.json')
def request(route, body=None):
    data = None if body is None else json.dumps(body).encode()
    with urllib.request.urlopen(urllib.request.Request(BASE + route, data=data,
            headers={'Content-Type': 'application/json'}), timeout=15) as response:
        return json.load(response)

for attempt in range(60):
    try:
        request('/_matrix/client/versions')
        break
    except Exception:
        if attempt == 59:
            raise RuntimeError('Message server did not become ready. Check Docker and retry.') from None
        time.sleep(2)
if path.exists():
    account = json.loads(path.read_text())
    # Obtain a fresh device session without changing an existing password.
    login = request('/_matrix/client/v3/login', {'type': 'm.login.password',
        'identifier': {'type': 'm.id.user', 'user': 'relay'}, 'password': account['password'],
        'initial_device_display_name': 'Relay'})
else:
    config = yaml.safe_load(Path('/data/homeserver.yaml').read_text())
    nonce = request('/_synapse/admin/v1/register')['nonce']
    password = secrets.token_urlsafe(32)
    mac = hmac.new(config['registration_shared_secret'].encode(),
        '\0'.join([nonce, 'relay', password, 'notadmin']).encode(), hashlib.sha1).hexdigest()
    login = request('/_synapse/admin/v1/register', {'nonce': nonce, 'username': 'relay',
        'password': password, 'admin': False, 'mac': mac})
    account = {'password': password}
account.update(login)
path.write_text(json.dumps(account)); path.chmod(0o600)
print(json.dumps({'server': 'http://127.0.0.1:' + os.environ.get('RELAY_MATRIX_PORT', '8008'), 'user_id': login['user_id'], 'access_token': login['access_token']}))
