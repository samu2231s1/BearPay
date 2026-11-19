import { createServer } from 'node:http';
import { readFile } from 'node:fs';
import { extname, join } from 'node:path';
createServer((req,res)=>{
  let pathname=new URL(req.url,'http://localhost').pathname;
  if(['/app','/login','/cadastro'].includes(pathname))pathname='/dashboard.html';
  if(pathname==='/api/config'){res.setHeader('content-type','application/json');return res.end(JSON.stringify({configured:false}));}
  const file=join(process.cwd(),pathname==='/'?'index.html':pathname);
  readFile(file,(error,data)=>{if(error){res.statusCode=404;return res.end('not found');}const ext=extname(file);res.setHeader('content-type',ext==='.css'?'text/css':ext==='.js'?'text/javascript':ext==='.html'?'text/html':'application/octet-stream');res.end(data);});
}).listen(4173,'127.0.0.1',()=>console.log('http://127.0.0.1:4173'));

