import {neon} from '@neondatabase/serverless';
import {readFileSync} from 'node:fs';
const sql=neon(process.env.DATABASE_URL);
const statements=readFileSync(new URL('../backend/migrations/001_init.sql',import.meta.url),'utf8').split(';').map(x=>x.trim()).filter(Boolean);
await sql.transaction(statements.map(s=>sql.query(s,[])));
console.log('Migration 001 applied.');
