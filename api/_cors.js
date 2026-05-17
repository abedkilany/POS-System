const DEFAULT_ALLOWED_HEADERS = [
  'Content-Type',
  'Authorization',
  'X-Device-Id',
  'X-Device-Token',
  'X-Store-Id',
  'X-Branch-Id',
  'X-Device-Role',
  'X-Sync-Transport',
];

export function setCorsHeaders(req, res) {
  const allowedOrigin = (process.env.CORS_ALLOW_ORIGIN || '*').trim() || '*';
  const requestHeaders = req.headers['access-control-request-headers'];

  res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Vary', 'Origin, Access-Control-Request-Headers');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    requestHeaders || DEFAULT_ALLOWED_HEADERS.join(', '),
  );
  res.setHeader('Access-Control-Max-Age', '86400');
}

export function handleCorsPreflight(req, res) {
  setCorsHeaders(req, res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  return false;
}

export function withCors(handler) {
  return async function corsWrappedHandler(req, res) {
    if (handleCorsPreflight(req, res)) return;
    return handler(req, res);
  };
}
