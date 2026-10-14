import {readdir,readFile,mkdir,writeFile} from 'node:fs/promises';
const files=(await readdir('supabase/migrations')).filter(f=>/^\d+_.+\.sql$/.test(f)).sort();
let sql=`-- Gujjar Brother Transport: NEW EMPTY SUPABASE PROJECT ONLY.
-- Run this complete file once in the Supabase SQL Editor as postgres.
-- Do not use this file to update an existing app. Use db:migrate instead.
-- Everything is transactional; a failed statement rolls back this installation.
begin;
do $$begin
 if to_regclass('public.app_users') is not null then
  raise exception 'This database already contains the app. Use npm run db:migrate for updates.';
 end if;
end $$;
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations(version text primary key,statements text[],name text);
`;
for(const file of files){
 const [,version,name]=/^(\d+)_(.+)\.sql$/.exec(file);
 sql+=`\n-- Migration: ${file}\n`+await readFile('supabase/migrations/'+file,'utf8');
 sql+=`\ninsert into supabase_migrations.schema_migrations(version,name,statements) values('${version}','${name.replaceAll("'","''")}',array[]::text[]);\n`;
}
sql+="\nnotify pgrst, 'reload schema';\ncommit;\n";
await mkdir('supabase/setup',{recursive:true});await writeFile('supabase/setup/NEW_DATABASE_SETUP.sql',sql);
console.log(`Generated new-database setup from ${files.length} ordered migrations.`);
