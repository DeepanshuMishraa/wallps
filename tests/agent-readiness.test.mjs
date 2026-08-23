import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const docs = path.join(root, "docs");
const read = (file) => fs.readFileSync(path.join(docs, file), "utf8");

const homepage = read("index.html");
const homepageText = homepage
  .replace(/<style[\s\S]*?<\/style>/gi, "")
  .replace(/<script[\s\S]*?<\/script>/gi, "")
  .replace(/<[^>]+>/g, " ")
  .replace(/&amp;/g, "&")
  .replace(/\s+/g, " ")
  .trim();

assert.match(homepage, /<h1\b[^>]*>/i, "homepage has an H1");
assert.ok(homepageText.length >= 500, `homepage text is only ${homepageText.length} characters`);
assert.match(homepage, /rel="canonical"/i);
assert.match(homepage, /type="text\/markdown"/i);
assert.match(homepage, /"@type": "SoftwareApplication"/);
const jsonLd = homepage.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/i)?.[1];
assert.ok(jsonLd, "homepage has JSON-LD");
assert.equal(JSON.parse(jsonLd).name, "Wallps");

const robots = read("robots.txt");
for (const agent of ["ChatGPT-User", "GPTBot", "ClaudeBot", "Google-Extended", "DeepSeekBot", "PerplexityBot", "ora-agent"]) {
  assert.match(robots, new RegExp(`User-agent: ${agent}[\\s\\S]*?Allow: \/`), `${agent} is allowed`);
}
assert.match(robots, /Sitemap: https:\/\/deepanshumishraa\.github\.io\/wallps\/sitemap\.xml/);

const llms = read("llms.txt");
assert.match(llms, /^# Wallps/m);
assert.match(llms, /^## When to use Wallps/m);
assert.match(llms, /^## How an agent should use this site/m);
assert.match(llms, /macOS 13/);

const sitemap = read("sitemap.xml");
assert.match(sitemap, /<urlset[^>]+xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9"/);
for (const url of ["/wallps/", "/wallps/about/", "/wallps/contact/", "/wallps/privacy/"]) {
  assert.match(sitemap, new RegExp(`<loc>https:\/\/deepanshumishraa\.github\.io${url.replaceAll("/", "\\/")}<\\/loc>`));
}
assert.equal((sitemap.match(/<lastmod>/g) ?? []).length, 4);

const notFound = read("404.html");
assert.match(notFound, /# Page not found/);
assert.match(notFound, /sitemap\.xml/);
assert.match(notFound, /llms\.txt/);

for (const page of ["about/index.html", "contact/index.html", "privacy/index.html"]) {
  const html = read(page);
  const text = html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  assert.match(html, /<h1\b[^>]*>/i, `${page} has an H1`);
  assert.ok(text.length >= 500, `${page} text is only ${text.length} characters`);
  assert.match(html, /rel="canonical"/i, `${page} has a canonical URL`);
}

for (const [endpoint, file] of Object.entries({
  "/": "index.html",
  "/about/": "about/index.html",
  "/contact/": "contact/index.html",
  "/privacy/": "privacy/index.html",
  "/robots.txt": "robots.txt",
  "/sitemap.xml": "sitemap.xml",
  "/llms.txt": "llms.txt",
  "/index.md": "index.md",
})) {
  assert.ok(fs.existsSync(path.join(docs, file)), `${endpoint} is published as ${file}`);
}
assert.ok(fs.existsSync(path.join(docs, "404.html")), "unknown paths have a custom 404 page");

console.log("Agent readiness static checks passed.");
