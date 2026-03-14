export async function onRequest(context) {
  const url = new URL(context.request.url);

  // Allow data.json to be fetched without HTTP Basic Auth.
  // The HTML has its own SHA-256 password gate, so this file
  // is not exposed to unauthenticated users in practice.
  if (url.pathname === '/data/data.json') {
    return context.next();
  }

  const auth = context.request.headers.get('Authorization');
  if (!auth || !auth.startsWith('Basic ')) {
    return new Response('Unauthorized', {
      status: 401,
      headers: { 'WWW-Authenticate': 'Basic realm="Mission Control"' }
    });
  }
  const decoded = atob(auth.split(' ')[1]);
  const colonIdx = decoded.indexOf(':');
  const pass = colonIdx >= 0 ? decoded.slice(colonIdx + 1) : decoded;
  if (pass !== context.env.MC_PASSWORD) {
    return new Response('Unauthorized', {
      status: 401,
      headers: { 'WWW-Authenticate': 'Basic realm="Mission Control"' }
    });
  }
  return context.next();
}
