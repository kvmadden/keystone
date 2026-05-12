#!/usr/bin/env node
// PixelLab batch — generates all Keystone sprites at small pixel-art sizes.
// Usage:
//   PIXELLAB_API_KEY=... node tools/generate_sprites.mjs [--only beaver,frog]
//
// Writes PNGs to assets/sprites/<name>.png. Cached: if the file already exists,
// the sprite is skipped unless --force is passed.

import fs from "node:fs/promises";
import path from "node:path";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "assets", "sprites");

const API_KEY = process.env.PIXELLAB_API_KEY;
if (!API_KEY) {
  console.error("✗ PIXELLAB_API_KEY env var not set.");
  process.exit(1);
}

const argv = process.argv.slice(2);
const FORCE = argv.includes("--force");
const ONLY = (() => {
  const i = argv.indexOf("--only");
  if (i < 0) return null;
  return new Set(argv[i + 1].split(","));
})();
const CONCURRENCY = 4;
const STYLE = "limited palette pixel art, clean outlines, gentle warm earthy tones, side or front view on transparent background";
const TILE_STYLE = "top-down view, seamlessly tileable, pixel art texture, no border, no shadow, no objects, even coverage edge-to-edge, low contrast";

// ── Sprite manifest ────────────────────────────────────────────────────
const SPRITES = [
  // Beaver — multiple shots
  { name: "beaver",          w: 32, h: 32, prompt: "friendly beaver standing facing camera, brown fur, paddle tail visible behind, large front teeth, round eyes" },
  { name: "beaver_carrying", w: 32, h: 32, prompt: "beaver standing facing camera holding a brown log horizontally in front of its body, brown fur, large teeth" },
  // Trees and logs
  { name: "tree",            w: 32, h: 32, prompt: "single small leafy tree, dark green canopy, brown trunk, front view, simple silhouette" },
  { name: "tree_stump",      w: 32, h: 32, prompt: "low cut tree stump with brown rings on top, surrounded by short grass" },
  { name: "log",             w: 32, h: 32, prompt: "single short horizontal wooden log centered, brown wood with darker rings on the ends, transparent background" },
  // Dam
  { name: "dam_new",         w: 32, h: 32, prompt: "fresh beaver dam segment made of stacked sticks and logs, bright brown wood, lashed together" },
  { name: "dam_worn",        w: 32, h: 32, prompt: "beaver dam segment with some weathered logs, slightly mossy, holding back water" },
  { name: "dam_broken",      w: 32, h: 32, prompt: "broken splintered beaver dam segment, dark brown rotted wood, gap visible" },
  // Lodge
  { name: "lodge",           w: 32, h: 32, prompt: "beaver lodge dome made of sticks and mud, dark entrance hole at the front, sitting at a water edge" },
  // Species
  { name: "willow",          w: 32, h: 32, prompt: "young willow tree, slim drooping branches, soft green canopy, on muddy wetland ground" },
  { name: "frog",            w: 32, h: 32, prompt: "tiny green frog centered, side view, sitting, large dark eyes, transparent background" },
  { name: "fish",            w: 32, h: 32, prompt: "small golden brown fish centered, side view, swimming, simple shape, transparent background" },
  { name: "duck",            w: 32, h: 32, prompt: "small white duck floating on water, side view, orange beak, calm" },
  { name: "heron",           w: 32, h: 32, prompt: "tall grey heron wading, side view, long neck, long legs, slim orange beak" },
  { name: "otter",           w: 32, h: 32, prompt: "playful river otter side view, brown fur, sleek body, swimming on its back" },
  { name: "coyote",          w: 32, h: 32, prompt: "small tan coyote, lean, side view, alert ears, walking pose" },
  // Tile textures — seamlessly tileable
  { name: "tile_grass",      w: 32, h: 32, style: TILE_STYLE, prompt: "soft natural grass texture, varied green blades, dewy, top-down" },
  { name: "tile_grass_2",    w: 32, h: 32, style: TILE_STYLE, prompt: "natural grass texture with a tiny yellow wildflower and a small white flower, mostly green blades, top-down" },
  { name: "tile_grass_3",    w: 32, h: 32, style: TILE_STYLE, prompt: "natural grass texture with a few short clover sprouts and tiny pebbles, mostly green blades, top-down" },
  { name: "tile_dry",        w: 32, h: 32, style: TILE_STYLE, prompt: "dry parched ground with sparse pale brown grass tufts and small cracks, top-down" },
  { name: "tile_dirt",       w: 32, h: 32, style: TILE_STYLE, prompt: "rich brown dirt soil with small pebbles and twigs, top-down" },
  { name: "tile_shallow",    w: 32, h: 32, style: TILE_STYLE, prompt: "rippling shallow pond water, light blue with small white ripple highlights, calm, no sand, no beach, just water, top-down" },
  { name: "tile_deep",       w: 32, h: 32, style: TILE_STYLE, prompt: "deep dark blue water with subtle wave highlights, calm, top-down" },
  { name: "tile_wetland",    w: 32, h: 32, style: TILE_STYLE, prompt: "lush bright wetland marsh with vibrant green grasses, damp moss, faint puddles, top-down" },
  // Tree variants
  { name: "tree_2",          w: 32, h: 32, prompt: "small leafy bush, round vibrant green canopy, short brown stem visible, front view, simple silhouette, transparent background" },
  { name: "tree_3",          w: 32, h: 32, prompt: "tall narrow pine tree, dark green needles, brown trunk, front view, simple silhouette, transparent background" },
  // Species HUD icons — small distilled silhouettes
  { name: "icon_willow",     w: 32, h: 32, prompt: "small green willow silhouette icon, mostly green canopy with brown trunk dot, simple, transparent background" },
  { name: "icon_frog",       w: 32, h: 32, prompt: "small green frog silhouette icon, front view, simple, transparent background" },
  { name: "icon_fish",       w: 32, h: 32, prompt: "small golden fish silhouette icon, side view, simple, transparent background" },
  { name: "icon_duck",       w: 32, h: 32, prompt: "small white duck silhouette icon, side view with orange beak, simple, transparent background" },
  { name: "icon_heron",      w: 32, h: 32, prompt: "small grey heron silhouette icon, side view, slim neck and beak, simple, transparent background" },
  { name: "icon_otter",      w: 32, h: 32, prompt: "small brown otter silhouette icon, side view, simple, transparent background" },
  // Title-screen background
  { name: "title_bg",        w: 256, h: 192, prompt: "wide pixel art landscape, beaver pond at dusk, calm dark green forest in the background with silhouetted pine trees, dark blue pond water in the foreground with a small beaver dam of stacked logs across the middle, soft warm sky fading from orange at horizon to deep blue at top, a small lit beaver lodge dome on the bank, painterly mood, no text, no UI" },
];

async function generate(s) {
  const out = path.join(OUT, `${s.name}.png`);
  if (!FORCE && existsSync(out)) {
    console.log(`  • cached  ${s.name}`);
    return { name: s.name, status: "cached" };
  }
  const isTile = !!s.style;
  const body = {
    description: `${s.prompt}, ${s.style || STYLE}`,
    image_size: { width: s.w, height: s.h },
    no_background: !isTile,    // tiles need a full background
    text_guidance_scale: 8,
  };
  const t0 = Date.now();
  try {
    const res = await fetch("https://api.pixellab.ai/v1/generate-image-pixflux", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const t = await res.text();
      console.error(`  ✗ ${s.name}: HTTP ${res.status} ${t.slice(0, 200)}`);
      return { name: s.name, status: "error", error: `HTTP ${res.status}` };
    }
    const j = await res.json();
    const b64 = j?.image?.base64;
    if (!b64) {
      console.error(`  ✗ ${s.name}: no image in response`);
      return { name: s.name, status: "error", error: "no image" };
    }
    await fs.writeFile(out, Buffer.from(b64, "base64"));
    const secs = ((Date.now() - t0) / 1000).toFixed(1);
    console.log(`  ✓ ${s.name.padEnd(20)} ${s.w}x${s.h}  (${secs}s)`);
    return { name: s.name, status: "ok" };
  } catch (e) {
    console.error(`  ✗ ${s.name}: ${e.message}`);
    return { name: s.name, status: "error", error: e.message };
  }
}

async function runPool(items, fn, concurrency) {
  const results = [];
  const queue = [...items];
  const active = new Set();
  async function startOne() {
    const item = queue.shift();
    if (!item) return;
    const p = fn(item).then(r => {
      results.push(r);
      active.delete(p);
      return startOne();
    });
    active.add(p);
    return p;
  }
  const starters = [];
  for (let i = 0; i < Math.min(concurrency, items.length); i++) starters.push(startOne());
  await Promise.all(starters);
  while (active.size > 0) await Promise.race(active);
  return results;
}

async function main() {
  await fs.mkdir(OUT, { recursive: true });
  const list = ONLY ? SPRITES.filter(s => ONLY.has(s.name)) : SPRITES;
  console.log(`\n🎨 PixelLab — ${list.length} sprites, ${CONCURRENCY} in parallel${FORCE ? " (force)" : ""}\n`);
  const t0 = Date.now();
  const results = await runPool(list, generate, CONCURRENCY);
  const ok = results.filter(r => r.status === "ok").length;
  const cached = results.filter(r => r.status === "cached").length;
  const err = results.filter(r => r.status === "error").length;
  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
  console.log(`\nDone in ${elapsed}s — ${ok} new · ${cached} cached · ${err} failed\n`);
  if (err > 0) {
    console.log("Failed sprites (placeholders will remain in-game):");
    for (const r of results.filter(r => r.status === "error")) {
      console.log(`  - ${r.name}: ${r.error}`);
    }
  }
}

main().catch(e => { console.error(e); process.exit(1); });
