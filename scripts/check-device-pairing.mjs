import { chromium } from '@playwright/test';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { derive, to64, sealBlob } from '../apps/web/lib/crypto.js';
import { makeDemo } from '../apps/web/lib/demo.js';
const origin = process.env.RELAY_PAIRING_TEST_ORIGIN;
if (!origin) throw Error('Set RELAY_PAIRING_TEST_ORIGIN to a running Relay server backed by an isolated test database.');
const handle = 'qr_' + randomBytes(6).toString('hex'), passphrase = 'pairing verification four unrelated words';
const salt = randomBytes(16), account = randomUUID(), dek = randomBytes(32), keys = await derive(passphrase, salt);
async function wrap(type) {
  const key = await crypto.subtle.importKey('raw', keys.kek, 'AES-GCM', false, ['encrypt']), nonce = randomBytes(12);
  const data = await crypto.subtle.encrypt({name:'AES-GCM',iv:nonce,additionalData:new TextEncoder().encode(`relay/v1/wrap|${account}|1|${type}`)},key,dek);
  return Buffer.concat([nonce,Buffer.from(data)]).toString('base64url');
}
async function api(path,body,token,method=body?'POST':'GET') {
  const r=await fetch(origin+'/api/v1/'+path,{method,headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{})});
  const data=r.status===204?{}:await r.json(); assert(r.ok,JSON.stringify(data));return data;
}
const session = await api('accounts',{account_id:account,handle,kdf_salt:to64(salt),kdf_params:{alg:'argon2id13',ops:3,mem:67108864},auth_verifier:createHash('sha256').update(keys.auth).digest('base64url'),recovery_verifier:to64(randomBytes(32)),device:{device_id:randomUUID(),priority:4},wraps:await Promise.all(['passphrase','recovery'].map(async wrap_type=>({wrap_type,key_version:1,wrapped_dek:await wrap(wrap_type)})))});
await mkdir('artifacts', { recursive: true });
let browser;
try {
  browser=await chromium.launch({headless:true});
  const agreement=makeDemo()[0]; agreement.title='Pairing sync verification';
  await api('blobs/'+agreement.id,{base_version:0,key_version:1,envelope:await sealBlob(agreement,dek,account,1)},session.token,'PUT');
  const first=await browser.newPage({viewport:{width:1280,height:900}});
  await first.goto(origin+'/workspace');
  await first.getByRole('button',{name:'Scan Pairing Code',exact:true}).waitFor();
  await first.getByRole('button',{name:'Use My Passphrase',exact:true}).click();
  await first.getByLabel('Handle',{exact:true}).fill(handle);await first.getByLabel('Passphrase',{exact:true}).fill(passphrase);
  await first.getByRole('button',{name:'Unlock Agreements',exact:true}).click();
  await first.getByRole('button',{name:'Settings',exact:true}).click();
  await first.getByRole('button',{name:/Devices Your current browser session/}).click();
  await first.getByRole('button',{name:'Show Pairing Code',exact:true}).click();
  await first.locator('.pairing-qr').waitFor();
  await first.getByText('Can’t scan?',{exact:true}).click();
  const link=await first.getByLabel('Private pairing link',{exact:true}).inputValue();
  await first.screenshot({path:'artifacts/pairing-host.png',fullPage:true});
  const second=await browser.newPage({viewport:{width:390,height:844}});
  await second.goto(link);
  await second.getByRole('button',{name:'Connect with Link',exact:true}).click();
  await second.getByText('Waiting for approval on your other device.',{exact:true}).waitFor();
  await first.getByRole('button',{name:'Approve Web browser',exact:true}).waitFor();
  const code=await first.locator('.pairing-check').textContent();assert.equal(await second.locator('.pairing-check').textContent(),code);
  await second.screenshot({path:'artifacts/pairing-waiting.png',fullPage:true});
  await first.getByRole('button',{name:'Approve Web browser',exact:true}).click();
  await second.getByRole('button',{name:'Settings',exact:true}).waitFor();
  await second.getByText('Pairing sync verification',{exact:true}).waitFor();
  assert.equal(new URL(second.url()).hash,'');
  await second.screenshot({path:'artifacts/pairing-complete.png',fullPage:true});
  await second.getByRole('button',{name:'Settings',exact:true}).click();
  await second.getByRole('button',{name:/Devices Your current browser session/}).click();
  await second.getByRole('button',{name:'Lock This Browser',exact:true}).click();
  await second.getByRole('button',{name:'Scan Pairing Code',exact:true}).waitFor();
  console.log('PASS: default pairing, QR display, matching check codes, explicit approval, cross-session encrypted record decryption, fragment removal, and lock.');
} finally {
  await browser?.close();await api('account',{handle,auth_key:to64(keys.auth)},session.token,'DELETE');keys.kek.fill(0);keys.auth.fill(0);dek.fill(0);
}
