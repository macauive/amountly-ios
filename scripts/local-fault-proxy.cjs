// Loopback-only proxy used to lose a response AFTER the real local API commits.
// It never accepts a configurable upstream, credentials, or remote destination.
const http=require('node:http')
let fault=null
const server=http.createServer((req,res)=>{
 if(req.url==='/__test/fault'&&req.method==='POST'){
  let body='';req.on('data',chunk=>{body+=chunk;if(body.length>1024)req.destroy()})
  req.on('end',()=>{try{const value=JSON.parse(body);if(!/^\/rest\/v1\/(rpc\/[a-z_]+|[a-z_]+)$/.test(value.path)||!['GET','POST','PATCH'].includes(value.method)||!['drop','delay','clear'].includes(value.mode))throw Error();fault=value.mode==='clear'?null:value;res.writeHead(204);res.end()}catch{res.writeHead(400);res.end()}});return
 }
 const upstream=http.request({hostname:'127.0.0.1',port:54321,path:req.url,method:req.method,headers:{...req.headers,host:'127.0.0.1:54321'}},response=>{
  if(fault && req.url.split('?')[0]===fault.path && req.method===fault.method && response.statusCode>=200 && response.statusCode<300){
   const mode=fault.mode;fault=null
   if(mode==='drop'){response.resume();response.on('end',()=>res.destroy());return}
   if(mode==='delay'){setTimeout(()=>{res.writeHead(response.statusCode,response.headers);response.pipe(res)},500);return}
  }
  res.writeHead(response.statusCode,response.headers);response.pipe(res)
 });upstream.on('error',()=>{res.writeHead(502);res.end()});req.pipe(upstream)
})
server.listen(54331,'127.0.0.1',()=>console.log('Local response-fault proxy listening on loopback.'))
