// Synthetic fixtures only. Never reads the application's .env or hosted credentials.
const fs = require('node:fs')
const path = require('node:path')
const {createRequire} = require('node:module')
const {execFileSync} = require('node:child_process')
const {randomUUID,randomBytes} = require('node:crypto')
const [webRoot, stackRoot, output] = process.argv.slice(2)
if (!webRoot || !stackRoot || !output) throw Error('Provide web checkout, local stack directory, and private output path')
const {createClient} = createRequire(path.join(path.resolve(webRoot),'package.json'))('@supabase/supabase-js')
const status = JSON.parse(execFileSync('supabase',['status','--workdir',stackRoot,'-o','json'],{encoding:'utf8',stdio:['ignore','pipe','ignore']}))
if (status.API_URL !== 'http://127.0.0.1:54321') throw Error('Refusing a non-local stack')
const admin = createClient(status.API_URL,status.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}})
const ok = async (promise,label) => {const result=await promise;if(result.error)throw Error(label+': '+result.error.code);return result.data}
const actors = {}
async function actor(label,type,organization,role='MEMBER') {
 const email=`ios-${label}-${randomUUID()}@example.invalid`, password=randomBytes(24).toString('base64url')
 const {user}=await ok(admin.auth.admin.createUser({email,password,email_confirm:true}),'auth fixture')
 let org=organization
 if(type==='business' && !org) org=(await ok(admin.from('organizations').insert({name:`iOS ${label} workspace`,owner_id:user.id}).select().single(),'workspace fixture')).id
 await ok(admin.from('users').insert({id:user.id,email,name:`Test ${label}`,account_type:type,role:type==='business'&&!organization?'OWNER':role,organization_id:org||null,is_active:true}),'profile fixture')
 const entry={id:user.id,email,password,organization:org||null}
 if(type!=='personal'){
 const client=await ok(admin.from('clients').insert({name:'Studio North',organization_id:org||null,user_id:org?null:user.id,email:'billing@example.invalid',address:'Synthetic address'}).select().single(),'client fixture')
 const project=await ok(admin.from('projects').insert({name:'Website redesign',client_id:client.id,organization_id:org||null,user_id:org?null:user.id,billing_model:'HOURLY',rate:125}).select().single(),'project fixture')
 entry.client=client.id;entry.project=project.id
 }
 actors[label]=entry;return entry
}
async function main(){
 const owner=await actor('owner','business')
 await actor('admin','business',owner.organization,'ADMIN')
 await actor('member','business',owner.organization)
 await actor('outsider','business')
 await actor('freelancer','freelancer')
 await actor('personal','personal')
 await actor('disabled','business')
 await ok(admin.from('users').update({is_active:false}).eq('id',actors.disabled.id),'disabled fixture')
 const bulk=await actor('bulk','freelancer')
 const invoices=Array.from({length:1005},(_,n)=>({id:randomUUID(),user_id:bulk.id,client_id:bulk.client,invoice_number:`PAGE-${n}`,issue_date:'2026-01-01',due_date:'2026-02-01',subtotal:1,total:1,currency:n%2?'EUR':'USD',status:'SENT'}))
 await ok(admin.from('invoices').insert(invoices),'pagination fixture')
 await ok(admin.from('invoice_payments').insert(invoices.map(i=>({id:randomUUID(),invoice_id:i.id,amount:0.5,paid_on:'2026-01-15',method:'other',recorded_by:bulk.id}))),'partial receipt fixture')
 // Real rows for reservation and independent approval tests.
 for(const name of ['member','freelancer']){
 const a=actors[name],project=name==='member'?owner.project:a.project
 const rows=await ok(admin.from('time_entries').insert([{user_id:a.id,project_id:project,start_at:'2026-01-05T09:00:00Z',end_at:'2026-01-05T10:00:00Z',duration_minutes:60,billable_rate:125,status:name==='member'?'APPROVED':'DRAFT',source:'WEB',notes:'Synthetic billable work'}]).select(),'time fixture')
 a.timeEntry=rows[0].id
 }
 fs.writeFileSync(output,JSON.stringify({url:status.API_URL,anonKey:status.ANON_KEY,actors}),{mode:0o600})
 console.log('Prepared eight isolated actors, 1,005 invoices, payment and time fixtures. Credentials saved privately outside the repository.')
}
main().catch(e=>{console.error(e.message);process.exitCode=1})
