import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline/promises';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

// Use the project-pinned JS entry through Node on Windows, macOS and Linux.
export async function cliCommand() {
 const require=createRequire(import.meta.url),packagePath=require.resolve('supabase/package.json');
 const pkg=JSON.parse(await readFile(packagePath,'utf8'));
 return {command:process.execPath,prefix:[resolve(dirname(packagePath),typeof pkg.bin==='string'?pkg.bin:pkg.bin.supabase)]};
}
export async function main(argv=process.argv.slice(2)) {
 const action=argv[0],local=argv.includes('--local'),dryRun=argv.includes('--dry-run');
 if(!['migrate','types','test','status','login','link'].includes(action))throw new Error('Use migrate, types, test, status, login, or link.');
 if(action==='test'&&!local)throw new Error('Database tests require --local and a disposable local stack.');
 let args;
 if(action==='login')args=['login'];
 else if(action==='link') {
  const ref=argv[argv.indexOf('--project-ref')+1];
  if(!argv.includes('--project-ref')||!ref||!/^[a-z0-9]{20}$/.test(ref))throw new Error('Use npm run db:link -- --project-ref YOUR_NEW_PROJECT_REFERENCE');
  args=['link','--project-ref',ref];
 } else {
  if(!local){
   const ref=(await readFile('supabase/.temp/project-ref','utf8').catch(()=>'' )).trim();
   if(!ref)throw new Error('First run npm run db:login, then npm run db:link -- --project-ref YOUR_NEW_PROJECT_REFERENCE.');
   if(action==='migrate'&&!dryRun){
    if(!process.stdin.isTTY)throw new Error('Use an interactive terminal to confirm the target database.');
    const rl=createInterface({input:process.stdin,output:process.stdout});
    try{if(await rl.question(`Type the linked project reference ${ref} to apply pending migrations: `)!==ref)throw new Error('Target did not match.');}finally{rl.close();}
   }
  }
  args=action==='migrate'?['db','push',local?'--local':'--linked',...(dryRun?['--dry-run']:[])]:action==='test'?['test','db','--local']:action==='status'?['migration','list',local?'--local':'--linked']:['gen','types','typescript',local?'--local':'--linked','--schema','public'];
 }
 const cli=await cliCommand();
 const output=await new Promise((done,reject)=>{
  const child=spawn(cli.command,[...cli.prefix,...args],{stdio:action==='types'?['inherit','pipe','inherit']:'inherit',shell:false});
  let result='';child.stdout?.on('data',b=>result+=b);
  child.on('error',reject);child.on('close',code=>code===0?done(result):reject(new Error(`Supabase command exited with code ${code??1}. Review the database error above.`)));
 });
 if(action==='types'){await mkdir('shared/generated',{recursive:true});await writeFile('shared/generated/database.types.ts',output);console.info('Types generated from the selected database.');}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{console.error(error.message);process.exitCode=1;});
