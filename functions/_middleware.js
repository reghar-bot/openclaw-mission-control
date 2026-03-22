export async function onRequest(context) {
  // No server-side auth required — the HTML has a client-side SHA-256 password gate.
  // /data/data.json is intentionally public (no secrets in it, HTML gate protects the UI).
  return context.next();
}
