export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const key = decodeURIComponent(url.pathname.slice(1));

    if (!key || key.includes("..") || key.includes("/")) {
      return new Response("Not found", { status: 404 });
    }

    const object = await env.WALLPS.get(key);
    if (object === null) {
      return new Response("Not found", { status: 404 });
    }

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("etag", object.httpEtag);
    headers.set("content-disposition", `attachment; filename="${key}"`);
    headers.set("cache-control", "public, max-age=31536000, immutable");

    return new Response(object.body, { headers, status: 200 });
  },
};