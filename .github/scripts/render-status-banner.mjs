// .github/assets/status-banner.html をコマ撮りしてアニメーション WebP にする。
// 必要: playwright (chromium) と ffmpeg (libwebp)。
// usage: node .github/scripts/render-status-banner.mjs [query] [out]  例: "?down=5" /tmp/degraded.webp
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const { chromium } = createRequire(import.meta.url)("playwright"); // グローバル導入の playwright も解決できるよう require で読む

const assets = join(dirname(fileURLToPath(import.meta.url)), "../assets");
const LOOP_MS = 3000; // HTML 側のアニメ周期 (3s / 1.5s / 0.75s) の最小公倍数
const FPS = 20;
const frames = (LOOP_MS / 1000) * FPS;

const [query = "", out = join(assets, "status-banner.webp")] = process.argv.slice(2);
const dir = mkdtempSync(join(tmpdir(), "banner-"));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 900, height: 280 }, deviceScaleFactor: 2 });
await page.goto("file://" + join(assets, "status-banner.html") + query);
await page.evaluate(() => document.fonts.ready);
for (let i = 0; i < frames; i++) {
  await page.evaluate((t) => document.getAnimations().forEach((a) => { a.pause(); a.currentTime = t; }), (i * 1000) / FPS);
  await page.screenshot({ path: join(dir, `f${String(i).padStart(3, "0")}.png`) });
}
await browser.close();

execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-framerate", String(FPS), "-i", join(dir, "f%03d.png"),
  "-c:v", "libwebp_anim", "-lossless", "0", "-quality", "70", "-compression_level", "6", "-loop", "0", out]);
rmSync(dir, { recursive: true });
console.log("wrote", out);
