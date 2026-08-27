const PINNED = {
  "Wallps-1.0.3-macos.dmg": "ffd1aac27f817a9421d991a0113ae438041a9461fb7faff161b20b92e5a64428",
  "Wallps-1.0.4-macos.dmg": "c99de3052c5d4591713a3cad144ca35baa6e3bcec3379f27add3f2ffc974d3ca",
  "Wallps-1.0.5-macos.dmg": "adb8ce8d1a9c4f643c9f9325f3056bc88ddb3af4b05827abdac4946d92b8b41e",
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