// Isolated spike: identity is always derived from a verified bearer token.
export function makeHandler({ verify, getNote, putNote }) {
  return {
    async fetch(request) {
      const authorization = request.headers.get('authorization') ?? '';
      const match = /^Bearer\s+(\S+)$/i.exec(authorization);
      if (!match) return new Response('Unauthorized', { status: 401 });

      let subject;
      try {
        subject = (await verify(match[1])).sub;
        if (typeof subject !== 'string' || subject.length === 0) throw new Error('missing subject');
      } catch {
        return new Response('Unauthorized', { status: 401 });
      }

      if (request.method === 'GET') {
        return Response.json({ note: await getNote(subject) });
      }
      if (request.method === 'PUT') {
        let body;
        try { body = await request.json(); } catch { return new Response('Invalid JSON', { status: 400 }); }
        if (typeof body?.note !== 'string' || body.note.length > 200) {
          return new Response('Invalid note', { status: 400 });
        }
        await putNote(subject, body.note);
        return Response.json({ note: body.note });
      }
      return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, PUT' } });
    }
  };
}
