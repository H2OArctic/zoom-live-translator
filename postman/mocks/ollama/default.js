const http = require('http');
let scenario = 'success';

const server = http.createServer(async (req, res) => {
  const path = new URL(req.url, 'http://127.0.0.1').pathname.replace(/^\/api/, '');
  const send = (status, body) => {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
  };
  if (req.method === 'POST' && path === '/__scenario') {
    scenario = req.body?.scenario || 'success';
    return send(200, { scenario });
  }
  if (scenario === 'timeout') await new Promise(resolve => setTimeout(resolve, 1000));
  if (req.method === 'GET' && path === '/tags') {
    return send(200, { models: scenario === 'missing' ? [] : [{ name: 'translategemma:4b' }] });
  }
  if (req.method === 'POST' && path === '/generate') {
    const body = req.body;
    if (body?.model !== 'translategemma:4b' || typeof body.prompt !== 'string' || body.stream !== false) {
      return send(400, { error: 'Invalid model, prompt or stream fields' });
    }
    if (scenario === 'error') return send(500, { error: 'model failed to load' });
    if (scenario === 'html') {
      res.writeHead(500, { 'Content-Type': 'text/html' });
      return res.end('<h1>Unavailable</h1>');
    }
    if (scenario === 'truncated') return send(200, { response: 'Incomplete', done: true, done_reason: 'length' });
    if (scenario === 'empty') return send(200, { response: ' ', done: true, done_reason: 'stop' });
    if (scenario === 'redirect') {
      res.writeHead(302, { Location: 'http://127.0.0.1:1/should-not-be-requested' });
      return res.end();
    }
    return send(200, { response: 'Synthetic translated sentence.', done: true, done_reason: 'stop' });
  }
  send(501, { error: 'Endpoint not modeled' });
});

server.listen(process.env.PORT || 4917);
