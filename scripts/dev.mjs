import {spawn} from 'node:child_process';
const children=[['--import','tsx','--watch','server/index.ts'],['node_modules/vite/bin/vite.js','--host','127.0.0.1']].map(args=>spawn(process.execPath,args,{stdio:'inherit'}));
let stopping=false;function stop(code=0){if(stopping)return;stopping=true;children.forEach(c=>c.kill());process.exitCode=code;}
children.forEach(c=>{c.on('error',()=>stop(1));c.on('exit',code=>stop(code??1));});for(const s of ['SIGINT','SIGTERM'])process.on(s,()=>stop());
