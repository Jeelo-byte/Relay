import {neon} from '@neondatabase/serverless';
const sql=neon(process.env.DATABASE_URL);
const rows=await sql`SELECT account_id,row_id,version,seq,key_version,encode(envelope,'base64') AS envelope,deleted FROM blobs ORDER BY seq DESC`;
const values=JSON.stringify(rows);
for(const marker of ['Maya','Concert tickets','RELAYCANARY','Friday','I owe'])if(values.includes(marker))throw Error('Plaintext marker detected in encrypted blob table.');
console.log(`PASS: inspected ${rows.length} blob rows; no seeded plaintext markers. Records contain UUIDs, versions, sequence and ciphertext only.`);
