const PINNED = {
  "Wallps-1.0.1-macos.dmg": "179d7e68c47f0d79dea06d7d9a7934ad04135ee36c42acc3b5c0446080d83f71",
};

const ALLOWED_NAME = /^Wallps-\d+\.\d+\.\d+-macos\.dmg(\.sha256)?$/;

async function sha256Hex(data) {
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const key = decodeURIComponent(url.pathname.slice(1));

    if (!key || !ALLOWED_NAME.test(key) || key.includes("..") || key.includes("/")) {
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
    headers.set("x-content-type-options", "nosniff");

    const pinned = PINNED[key];
    if (key.endsWith(".dmg")) {
      if (!pinned) {
        return new Response("Unpinned release", { status: 410 });
      }
      const data = await new Response(object.body).arrayBuffer();
      if ((await sha256Hex(data)) !== pinned) {
        return new Response("Integrity check failed", { status: 410 });
      }
      return new Response(data, { headers, status: 200 });
    }

    return new Response(object.body, { headers, status: 200 });
  },
};