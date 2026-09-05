const upstream = 'https://raw.githubusercontent.com/jonathanbertholet/OXP26-App/codex/agenda-feed/catalog.json';
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== '/agenda/catalog.json') return env.ASSETS.fetch(request);
    if (!['GET', 'HEAD'].includes(request.method)) return new Response(null, {status: 405, headers: {Allow: 'GET, HEAD'}});
    try {
      const headers = new Headers();
      const etag = request.headers.get('If-None-Match');
      if (etag) headers.set('If-None-Match', etag);
      const response = await fetch(upstream, {headers, cf: {cacheTtlByStatus: {'200-299': 60, '400-599': 0}}});
      if (response.status !== 200 && response.status !== 304) throw new Error(`Upstream ${response.status}`);
      const outgoing = new Headers({'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'public, max-age=60, must-revalidate', 'X-Content-Type-Options': 'nosniff'});
      if (response.headers.has('etag')) outgoing.set('ETag', response.headers.get('etag'));
      return new Response(request.method === 'HEAD' ? null : response.body, {status: response.status, headers: outgoing});
    } catch (error) {
      console.error('Agenda upstream unavailable', String(error));
      return new Response('Agenda temporarily unavailable', {status: 503, headers: {'Cache-Control': 'no-store'}});
    }
  }
};
