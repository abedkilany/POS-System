import http from 'http';
import apiHandler from './api/[...path].js';
import { attachRealtimeServer } from './server_api/sync/realtime.js';

const port = Number(process.env.PORT || 3000);
const maxBodyBytes = 25 * 1024 * 1024;

function parseQuery(reqUrl) {
  const url = new URL(reqUrl || '/', 'http://localhost');
  const query = {};
  for (const [key, value] of url.searchParams.entries()) {
    if (query[key] == null) {
      query[key] = value;
    } else if (Array.isArray(query[key])) {
      query[key].push(value);
    } else {
      query[key] = [query[key], value];
    }
  }
  return query;
}

function attachResponseHelpers(res) {
  res.status = (statusCode) => {
    res.statusCode = statusCode;
    return res;
  };
  res.json = (value) => {
    if (!res.headersSent) {
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
    }
    res.end(JSON.stringify(value));
  };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > maxBodyBytes) {
        reject(Object.assign(new Error('Request body is too large.'), { statusCode: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      const raw = Buffer.concat(chunks).toString('utf8');
      if (!raw.trim()) return resolve({});
      const type = String(req.headers['content-type'] || '').toLowerCase();
      if (type.includes('application/json')) {
        try {
          return resolve(JSON.parse(raw));
        } catch (_) {
          return reject(Object.assign(new Error('Invalid JSON body.'), { statusCode: 400 }));
        }
      }
      return resolve(raw);
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  attachResponseHelpers(res);
  const url = new URL(req.url || '/', 'http://localhost');
  if (!url.pathname.startsWith('/api/')) {
    res.status(404).json({ ok: false, error: 'Not found.' });
    return;
  }
  try {
    req.query = parseQuery(req.url);
    req.body = await readBody(req);
    await apiHandler(req, res);
  } catch (error) {
    const status = error.statusCode || 500;
    if (!res.headersSent) {
      res.status(status).json({
        ok: false,
        error: error.message || String(error),
      });
    }
  }
});
attachRealtimeServer(server);

server.listen(port, '127.0.0.1', () => {
  console.log(`Ventio API listening on 127.0.0.1:${port}`);
});
