import { neon } from "@neondatabase/serverless";
import { readFileSync, readdirSync } from "node:fs";
const connection = new URL(process.env.DATABASE_URL_UNPOOLED || process.env.DATABASE_URL);
connection.hostname = connection.hostname.replace(/-pooler(?=\.)/, "");
const sql = neon(connection.toString());
const directory = new URL("../backend/migrations/", import.meta.url);
for (const file of readdirSync(directory).filter(f => /^\d+.*\.sql$/.test(f)).sort()) {
  const statements = readFileSync(new URL(file, directory), "utf8")
    .split(";").map(x => x.trim()).filter(Boolean);
  await sql.transaction(statements.map(s => sql.query(s, [])));
  console.log(`Migration ${file} applied.`);
}
