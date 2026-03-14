export async function onRequest(context) {
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
