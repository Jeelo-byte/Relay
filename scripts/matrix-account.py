"""Create the local Relay Matrix account; secrets go only to ignored private files."""
import os,secrets,yaml,requests,hmac,hashlib,json
root=os.path.join(os.path.dirname(__file__),'../infra/matrix/private')
config=yaml.safe_load(open(os.path.join(root,'synapse/homeserver.yaml')))
endpoint='http://127.0.0.1:8008/_synapse/admin/v1/register'
nonce=requests.get(endpoint,timeout=10).json()['nonce']
password=secrets.token_urlsafe(24)
message='\0'.join([nonce,'relay',password,'admin']).encode()
mac=hmac.new(config['registration_shared_secret'].encode(),message,hashlib.sha1).hexdigest()
response=requests.post(endpoint,json={'nonce':nonce,'username':'relay','password':password,'admin':True,'mac':mac},timeout=15)
response.raise_for_status()
path=os.path.join(root,'relay-account.json')
fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as f:json.dump({'server':'http://127.0.0.1:8008','user_id':'@relay:relay.local','password':password,**response.json()},f)
print('Local Relay Matrix account created. Credentials saved in the ignored private directory.')
