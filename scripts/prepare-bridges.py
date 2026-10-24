"""Generate and configure every supported bridge; never link accounts or print secrets."""
import pathlib,subprocess,yaml,secrets,shutil,os
root=pathlib.Path(__file__).resolve().parent.parent
compose=root/'infra/matrix/compose.yml'
private=compose.parent/'private'
services={'whatsapp':29318,'telegram':29317,'discord':29334,'signal':29328,'slack':29335,'gmessages':29336,'meta':29319,'instagram':29320}
def run(*args):return subprocess.run(['docker','compose','-f',str(compose),*args],capture_output=True,text=True,timeout=90)
for name,port in services.items():
 folder=private/name;folder.mkdir(parents=True,exist_ok=True)
 if not (folder/'config.yaml').exists():
  result=run('run','--rm','--no-deps',name)
  if not (folder/'config.yaml').exists():raise RuntimeError(f'{name}: configuration generation failed (exit {result.returncode})')
 config=yaml.safe_load((folder/'config.yaml').read_text())
 config['homeserver']['address']='http://synapse:8008';config['homeserver']['domain']='relay.local'
 app=config['appservice'];app.update(address=f'http://{name}:{port}',hostname='0.0.0.0',port=port)
 if app.get('as_token') in [None,'','generate']:app['as_token']=secrets.token_urlsafe(48)
 if app.get('hs_token') in [None,'','generate']:app['hs_token']=secrets.token_urlsafe(48)
 db=config.get('database',app.get('database'));db.update(type='sqlite3-fk-wal',uri='file:/data/bridge.db?_txlock=immediate')
 enc=config.get('encryption',config.get('bridge',{}).get('encryption'));enc.update(allow=False,default=False,require=False)
 config['bridge']['permissions']={'@relay:relay.local':'admin'}
 if 'federate_rooms' in config['bridge']:config['bridge']['federate_rooms']=False
 config['logging']={'min_level':'warn','writers':[{'type':'stdout','format':'json'}]}
 (folder/'config.yaml').write_text(yaml.safe_dump(config,sort_keys=False));os.chmod(folder/'config.yaml',0o600)
 if not (folder/'registration.yaml').exists():
  result=run('run','--rm','--no-deps',name)
  if not (folder/'registration.yaml').exists():raise RuntimeError(f'{name}: registration generation failed (exit {result.returncode})')
 shutil.copyfile(folder/'registration.yaml',private/'synapse'/f'{name}-registration.yaml')
 print(f'{name}: configured; account linking is pending')
synapse=private/'synapse/homeserver.yaml';config=yaml.safe_load(synapse.read_text());config['app_service_config_files']=[f'/data/{name}-registration.yaml' for name in services];synapse.write_text(yaml.safe_dump(config,sort_keys=False))
# Pin every downloaded bridge image to its immutable digest.
config=yaml.safe_load(compose.read_text())
for name in [*services,'synapse','element']:
 image=config['services'][name]['image'];result=subprocess.run(['docker','image','inspect',image,'--format','{{index .RepoDigests 0}}'],capture_output=True,text=True,check=True)
 config['services'][name]['image']=result.stdout.strip()
compose.write_text(yaml.safe_dump(config,sort_keys=False))
print('All bridge configurations generated and images pinned. No third-party accounts have been linked.')
