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

// The repair installer targets an existing app and is safe to rerun. It never
// resets the database or performs a record deletion on the administrator's behalf.
const lifecycleFile='20261014120000_record_lifecycle.sql';
const repairFile='20261014143000_lifecycle_delete_repair.sql';
const whereGuardFile='20261014170000_lifecycle_delete_where_guard.sql';
const lifecycleSql=await readFile('supabase/migrations/'+lifecycleFile,'utf8');
const repairSql=await readFile('supabase/migrations/'+repairFile,'utf8');
const whereGuardSql=await readFile('supabase/migrations/'+whereGuardFile,'utf8');
let repair=`-- Gujjar Brother Transport: EXISTING DATABASE archive/delete repair.
-- Run this complete file in the Supabase SQL Editor for the app's project.
-- No business records are deleted by this script. Safe to rerun.
begin;
set local lock_timeout = '5s';
do $preflight$
begin
 if to_regprocedure('public.save_form(text,uuid,integer,jsonb,integer,uuid)') is null
    or to_regclass('public.driver_duty_sessions') is null then
  raise exception 'The base app migrations are missing. Apply all pending migrations with npm run db:migrate before this repair. Do not run the new-database installer on an existing app.';
 end if;
end $preflight$;
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations(version text primary key,statements text[],name text);
do $install$
begin
 if to_regclass('private.lifecycle_resources') is null then
  -- Installation of the original feature is atomic; existing deployments skip it.
  execute $lifecycle$${lifecycleSql}$lifecycle$;
 end if;
end $install$;
${repairSql}
${whereGuardSql}
`;
for(const file of [lifecycleFile,repairFile,whereGuardFile]){
 const [,version,name]=/^(\d+)_(.+)\.sql$/.exec(file);
 repair+=`insert into supabase_migrations.schema_migrations(version,name,statements) values('${version}','${name}',array[]::text[]) on conflict(version) do nothing;\n`;
}
repair+=`notify pgrst, 'reload schema';
commit;
select 'Archive/delete database repair applied. Redeploy the updated app, refresh the page, and reload the deletion preview.' as result;
`;
await writeFile('supabase/setup/REPAIR_RECORD_DELETE.sql',repair);
console.log('Generated existing-database repair: supabase/setup/REPAIR_RECORD_DELETE.sql');
