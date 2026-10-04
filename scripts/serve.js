import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
const types = { '.html':'text/html; charset=utf-8', '.css':'text/css; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.svg':'image/svg+xml' };
const server = http.createServer(async (req, res) => {
 try {
  if (!['GET','HEAD'].includes(req.method)) { res.writeHead(405); return res.end(); }
  const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  const target = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
  const relative = path.relative(root, target);
  if (relative.startsWith('..') || path.isAbsolute(relative) || relative.split(path.sep).some(segment => segment.startsWith('.')) || !types[path.extname(target)]) { res.writeHead(404); return res.end('Not found'); }
  const body = await readFile(target);
  res.writeHead(200, { 'Content-Type':types[path.extname(target)], 'X-Content-Type-Options':'nosniff', 'Cache-Control':'no-store' });
  res.end(req.method === 'HEAD' ? undefined : body);
 } catch { res.writeHead(404); res.end('Not found'); }
});
server.listen(Number(process.env.PORT || 3000), '127.0.0.1', () => console.log('TradeUp: http://localhost:' + server.address().port));
