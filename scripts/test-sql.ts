import {PGlite} from '@electric-sql/pglite';
import {readdir,readFile} from 'node:fs/promises';
export async function createTestDatabase(){
 const db=new PGlite();await db.waitReady;
 // Isolated test fixtures only: production auth schema is owned by Supabase.
 await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
 create schema auth; create table auth.users(id uuid primary key,email text,raw_app_meta_data jsonb default '{}');
 create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id));
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 grant usage on schema auth to authenticated,anon,service_role;
 grant execute on function auth.uid(),auth.jwt() to authenticated,anon,service_role;
 create schema storage;create table storage.buckets(id text primary key,name text,public boolean default false,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,owner uuid,metadata jsonb);
 alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,update,delete on storage.objects to authenticated;
 `);
 for(const name of (await readdir('supabase/migrations')).filter(n=>n.endsWith('.sql')).sort()){
  try{await db.exec(await readFile('supabase/migrations/'+name,'utf8'));console.log('Migration applied in isolated PostgreSQL:',name);}catch(error){await db.close();throw new Error('Migration failed: '+name,{cause:error});}
 }
 return db;
}
if(process.argv[1]?.endsWith('test-sql.ts')){const db=await createTestDatabase();console.log('All migrations parsed and executed. This is NOT a hosted Supabase integration test.');await db.close();}
