const fs=require('node:fs'),path=require('node:path'),{spawn}=require('node:child_process')
const [webRoot,fixturesPath,mode='dev']=process.argv.slice(2)
if(!['build','start','dev'].includes(mode))throw Error('Invalid mode')
const f=JSON.parse(fs.readFileSync(fixturesPath,'utf8'))
if(f.url!=='http://127.0.0.1:54321')throw Error('Refusing non-local configuration')
const env={...process.env,NEXT_PUBLIC_SUPABASE_URL:f.url,NEXT_PUBLIC_SUPABASE_ANON_KEY:f.anonKey,OPENAI_API_KEY:'',SUPABASE_SERVICE_ROLE_KEY:''}
const args=[path.join(webRoot,'node_modules/next/dist/bin/next'),mode]
if(mode!=='build')args.push('--hostname','127.0.0.1','--port','4174')
const child=spawn(process.execPath,args,{cwd:webRoot,env,stdio:'inherit'})
for(const sig of ['SIGINT','SIGTERM'])process.on(sig,()=>child.kill(sig))
child.on('exit',code=>process.exit(code||0))
