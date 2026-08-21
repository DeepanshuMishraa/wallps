const PINNED = {
  "Wallps-1.0.1-macos.dmg": "bb7c5eca369a214e9a3ec0d140df4a5d3c7d5040094146ea8aab14bc6def4d41",
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