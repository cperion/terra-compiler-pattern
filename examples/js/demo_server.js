// demo_server.js — a Node.js-style HTTP server running on jsrun
//
// This is real JavaScript compiled to LuaJIT closure trees.
// The HTTP server is libuv (same as Node.js).
// Total runtime: ~5MB. Startup: ~27ms.

const http = require('http');
const fs = require('fs');
const path = require('path');

let requestCount = 0;

function fib(x) {
    if (x <= 1) { return x; }
    return fib(x - 1) + fib(x - 2);
}

const server = http.createServer(function(req, res) {
    requestCount++;
    let url = req.url;

    if (url === '/') {
        res.setHeader('Content-Type', 'text/html');
        res.end(`<!DOCTYPE html>
<html>
<head><title>jsrun</title></head>
<body>
  <h1>Hello from jsrun!</h1>
  <p>A tiny Node.js-compatible runtime.</p>
  <p>LuaJIT + libuv + js.lua compiler</p>
  <ul>
    <li><a href="/api/info">/api/info</a> — runtime info</li>
    <li><a href="/api/fib?n=10">/api/fib?n=10</a> — fibonacci</li>
    <li><a href="/api/echo?msg=hello">/api/echo?msg=hello</a> — echo</li>
  </ul>
</body>
</html>`);

    } else if (url === '/api/info') {
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({
            runtime: 'jsrun',
            engine: 'LuaJIT + libuv',
            requests: requestCount,
            pid: process.pid,
            platform: process.platform,
            cwd: process.cwd(),
        }));

    } else if (url.indexOf('/api/fib') === 0) {
        // Parse ?n=... from URL — extract after '='
        let n = 10;
        let eqIdx = url.indexOf('=');
        if (eqIdx !== -1) {
            n = parseInt(url.slice(eqIdx + 1));
        }

        let result = fib(n);
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ n: n, result: result }));

    } else if (url.indexOf('/api/echo') === 0) {
        let msg = 'no message';
        let eqIdx = url.indexOf('=');
        if (eqIdx !== -1) {
            msg = url.slice(eqIdx + 1);
        }
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ echo: msg }));

    } else {
        res.statusCode = 404;
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ error: 'not found', url: url }));
    }
});

server.listen(3000, function() {
    console.log('jsrun server running on http://localhost:3000');
    console.log('Try:');
    console.log('  curl http://localhost:3000/');
    console.log('  curl http://localhost:3000/api/info');
    console.log('  curl http://localhost:3000/api/fib?n=20');
});
