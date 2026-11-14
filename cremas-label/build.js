// Builds the Crémas bottle labels: front + back (3.5" x 4.5"), PNG @300 DPI, PDFs, and a letter print sheet.
// Edit the settings below, then run: node build.js
const fs = require('fs');
const { chromium } = require('playwright');

const BRAND   = 'Island Vibes';                 // small line above the name
const NAME    = 'Crémas';
const TAG     = 'Bringing the island to you';
const VOLUME  = '750 mL';
const ABV     = 'XX% ALC./VOL.';                // <-- put your real alcohol % here

const W = 350, H = 450; // viewBox units (100 units = 1 inch)

// ---------- illustration helpers ----------
const INK = '#2b1424';
const line = (a, b, w) => `<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" stroke="${INK}" stroke-width="${w}" stroke-linecap="round"/>`;
function bottle(x, y, rot) {
  return `<g transform="translate(${x} ${y}) rotate(${rot})">
    <rect x="-1.4" y="-17" width="2.8" height="6" rx="0.8" fill="#f6e7c8"/>
    <rect x="-1.8" y="-18.5" width="3.6" height="2.2" rx="0.6" fill="#c0392b"/>
    <path d="M-1.4 -11 Q-4 -9 -4 -6 L-4 4 Q-4 6 -2 6 L2 6 Q4 6 4 4 L4 -6 Q4 -9 1.4 -11 Z" fill="#fff4dd"/>
    <rect x="-4" y="-3" width="8" height="5" fill="#e07a3f"/>
  </g>`;
}
// seated person facing right at ground point (x,y); opts give arm pose + hair/hat
function person(o) {
  const { x, y, flip = false, hand, elbow, hand2, elbow2, extra = '', bottleRot = 0, bottle2 = null, scale = 1 } = o;
  const hip = [0, -5], sh = [3, -33], knee = [17, -20], foot = [27, -2], head = [5, -46];
  let s = '';
  s += line(hip, knee, 10) + line(knee, foot, 8.5) + `<ellipse cx="${foot[0] + 2}" cy="${foot[1]}" rx="5" ry="2.6" fill="${INK}"/>`;
  s += line(hip, sh, 14);
  if (hand2) s += line(sh, elbow2, 6.5) + line(elbow2, hand2, 6);
  s += `<circle cx="${head[0]}" cy="${head[1]}" r="8.2" fill="${INK}"/>`;
  s += extra;
  s += line(sh, elbow, 6.5) + line(elbow, hand, 6);
  s += bottle(hand[0], hand[1] - 2, bottleRot);
  if (bottle2) s += bottle(hand2[0], hand2[1] - 2, bottle2);
  return `<g transform="translate(${x} ${y}) scale(${flip ? -scale : scale} ${scale})">${s}</g>`;
}
function frond(cx, cy, ang, len, bend, color) {
  // a palm leaf: curved spine with leaflets
  const r = ang * Math.PI / 180;
  const ex = cx + Math.cos(r) * len, ey = cy + Math.sin(r) * len + bend;
  const mx = cx + Math.cos(r) * len * 0.5, my = cy + Math.sin(r) * len * 0.5 - Math.abs(bend) * 0.35 - 6;
  let leaflets = '';
  const n = 14;
  for (let i = 2; i <= n; i++) {
    const t = i / (n + 1);
    const px = (1 - t) * (1 - t) * cx + 2 * (1 - t) * t * mx + t * t * ex;
    const py = (1 - t) * (1 - t) * cy + 2 * (1 - t) * t * my + t * t * ey;
    const dx = 2 * (1 - t) * (mx - cx) + 2 * t * (ex - mx), dy = 2 * (1 - t) * (my - cy) + 2 * t * (ey - my);
    const a = Math.atan2(dy, dx);
    const L = 22 * Math.sin(Math.PI * t) + 4;
    for (const sgn of [1, -1]) {
      const la = a + sgn * 1.0 + 0.35;
      leaflets += `<path d="M${px.toFixed(1)} ${py.toFixed(1)} q${(Math.cos(la) * L * 0.5).toFixed(1)} ${(Math.sin(la) * L * 0.5 - 2).toFixed(1)} ${(Math.cos(la) * L).toFixed(1)} ${(Math.sin(la) * L + 6).toFixed(1)}" stroke="${color}" stroke-width="3.2" stroke-linecap="round" fill="none"/>`;
    }
  }
  return `<path d="M${cx} ${cy} Q${mx.toFixed(1)} ${my.toFixed(1)} ${ex.toFixed(1)} ${ey.toFixed(1)}" stroke="${color}" stroke-width="3.2" fill="none" stroke-linecap="round"/>${leaflets}`;
}
function hibiscus(x, y, r, rot, c1, c2) {
  let p = '';
  for (let i = 0; i < 5; i++) p += `<ellipse cx="0" cy="${-r * 0.55}" rx="${r * 0.42}" ry="${r * 0.6}" fill="${c1}" transform="rotate(${i * 72})"/>`;
  return `<g transform="translate(${x} ${y}) rotate(${rot})">${p}<circle r="${r * 0.18}" fill="${c2}"/><line x1="0" y1="0" x2="${r * 0.5}" y2="${-r * 0.7}" stroke="#ffd166" stroke-width="1.2" stroke-linecap="round"/></g>`;
}

// ---------- FRONT ----------
const crownX = 92, crownY = 188;
let palm = '';
palm += `<path d="M58 452 C 70 380, 66 300, 80 240 S 88 190, ${crownX} ${crownY}" stroke="${INK}" stroke-width="15" fill="none" stroke-linecap="round"/>`;
for (let i = 0; i < 9; i++) palm += `<path d="M${62 + i * 0.6} ${430 - i * 30} q8 -3 14 1" stroke="#4a2a3a" stroke-width="1.6" fill="none"/>`; // trunk rings
palm += frond(crownX, crownY, 200, 95, 30, INK) + frond(crownX, crownY, 240, 50, 10, INK) + frond(crownX, crownY, 160, 85, 40, INK);
palm += frond(crownX, crownY, -12, 115, 38, INK) + frond(crownX, crownY, 15, 100, 55, INK) + frond(crownX, crownY, -40, 60, 14, INK) + frond(crownX, crownY, 60, 70, 45, INK);
palm += `<circle cx="${crownX + 4}" cy="${crownY + 8}" r="6" fill="${INK}"/><circle cx="${crownX - 6}" cy="${crownY + 9}" r="5.5" fill="${INK}"/><circle cx="${crownX}" cy="${crownY + 15}" r="5.5" fill="${INK}"/>`;

const ground = 384;
const people =
  // 1: leaning on the palm, sun hat, bottle raised high
  person({ x: 92, y: ground, elbow: [16, -50], hand: [20, -70], bottleRot: 12, hand2: [-6, -14], elbow2: [-4, -22],
    extra: `<ellipse cx="5" cy="-52" rx="15" ry="3" fill="${INK}"/><path d="M-3 -52 Q5 -66 13 -52 Z" fill="${INK}"/>` }) +
  // 2: afro puff, clinking toward person 3
  person({ x: 150, y: ground, elbow: [18, -26], hand: [33, -38], bottleRot: 40, hand2: [16, -24], elbow2: [8, -16],
    extra: `<circle cx="3" cy="-50" r="11" fill="${INK}"/>` }) +
  // 3: ponytail, facing left, clinking back
  person({ x: 222, y: ground, flip: true, elbow: [18, -26], hand: [34, -40], bottleRot: 35, hand2: [-6, -12], elbow2: [-4, -22],
    extra: `<path d="M0 -50 q-12 2 -14 16 q8 -6 12 -9 z" fill="${INK}"/>` });

const front = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="100%" height="100%">
<defs>
  <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2d1b4e"/><stop offset="0.28" stop-color="#7b2d5e"/>
    <stop offset="0.5" stop-color="#e2574c"/><stop offset="0.66" stop-color="#f7a046"/><stop offset="0.75" stop-color="#ffd27a"/>
  </linearGradient>
  <linearGradient id="sea" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e98a5b"/><stop offset="0.35" stop-color="#3f8ea6"/><stop offset="1" stop-color="#145a73"/></linearGradient>
  <linearGradient id="sand" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4c98a"/><stop offset="1" stop-color="#e3a65f"/></linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#fff2b3" stop-opacity="0.9"/><stop offset="1" stop-color="#ffcf6b" stop-opacity="0"/></radialGradient>
  <filter id="ts" x="-10%" y="-10%" width="120%" height="140%"><feDropShadow dx="0" dy="2" stdDeviation="1.6" flood-color="#2b1424" flood-opacity="0.55"/></filter>
</defs>
<rect width="${W}" height="${H}" fill="url(#sky)"/>
${[[40,60],[300,40],[320,110],[200,30],[15,130],[270,85],[150,18],[335,170]].map(([x,y])=>`<circle cx="${x}" cy="${y}" r="0.9" fill="#fff" opacity="0.7"/>`).join('')}
<circle cx="250" cy="318" r="95" fill="url(#glow)"/>
<circle cx="250" cy="318" r="48" fill="#fff0b8"/>
<g fill="none" stroke="${INK}" stroke-width="1.6" stroke-linecap="round" opacity="0.8">
  <path d="M190 205 q5 -5 10 0 q5 -5 10 0"/><path d="M220 188 q4 -4 8 0 q4 -4 8 0"/><path d="M285 215 q3.5 -3.5 7 0 q3.5 -3.5 7 0"/>
</g>
<rect x="0" y="318" width="${W}" height="60" fill="url(#sea)"/>
<g stroke="#fff3c4" stroke-linecap="round" opacity="0.85">
  <line x1="222" y1="324" x2="278" y2="324" stroke-width="2"/><line x1="232" y1="331" x2="268" y2="331" stroke-width="1.6"/>
  <line x1="240" y1="338" x2="260" y2="338" stroke-width="1.3"/><line x1="246" y1="345" x2="255" y2="345" stroke-width="1"/>
</g>
<g stroke="#bfe6ef" stroke-width="1.1" stroke-linecap="round" opacity="0.6">
  <line x1="20" y1="335" x2="45" y2="335"/><line x1="90" y1="342" x2="120" y2="342"/><line x1="300" y1="340" x2="330" y2="340"/><line x1="150" y1="352" x2="170" y2="352"/>
</g>
<path d="M0 372 Q 90 360 175 368 T ${W} 362 L ${W} ${H} L 0 ${H} Z" fill="#fff6e4" opacity="0.7"/>
<path d="M0 376 Q 90 365 175 372 T ${W} 367 L ${W} ${H} L 0 ${H} Z" fill="url(#sand)"/>
${palm}
<ellipse cx="160" cy="${ground + 1}" rx="105" ry="5" fill="#b9733d" opacity="0.35"/>
${people}
<path d="M300 410 q14 -8 30 2 M306 412 q-4 -14 10 -20" stroke="#2e7d4f" stroke-width="3" fill="none" stroke-linecap="round"/>${hibiscus(330, 396, 13, 20, '#e63946', '#8d1b2a')}${hibiscus(308, 404, 8.5, -30, '#ff6b81', '#a4243b')}
${hibiscus(22, 400, 10, 40, '#ff6b81', '#a4243b')}
<g stroke="#fff3c4" stroke-width="1.4" stroke-linecap="round"><line x1="185" y1="318" x2="185" y2="310"/><line x1="176" y1="321" x2="171" y2="315"/><line x1="194" y1="321" x2="199" y2="315"/></g>
<g fill="#fff3c4" font-family="DejaVu Sans" opacity="0.9"><text x="150" y="300" font-size="11">♪</text><text x="163" y="288" font-size="9">♫</text></g>
<g text-anchor="middle" filter="url(#ts)">
  <text x="175" y="44" font-family="Lato" font-weight="700" font-size="11" letter-spacing="4" fill="#ffe3b0">✦ ${BRAND.toUpperCase()} ✦</text>
  <text x="175" y="104" font-family="Pacifico" font-size="60" fill="#fff6e4">${NAME}</text>
  <text x="175" y="128" font-family="Lato" font-weight="700" font-size="9.5" letter-spacing="3.2" fill="#ffe3b0">COCONUT CREAM LIQUEUR</text>
</g>
<rect x="0" y="412" width="${W}" height="38" fill="#2b1424" opacity="0.9"/>
<text x="175" y="429" text-anchor="middle" font-family="Playfair Display" font-style="italic" font-size="14" fill="#ffd27a">${TAG}</text>
<text x="175" y="443" text-anchor="middle" font-family="Lato" font-weight="700" font-size="7.5" letter-spacing="2" fill="#fff6e4">${VOLUME.toUpperCase()}   ·   HANDCRAFTED   ·   ${ABV}</text>
</svg>`;

// ---------- BACK ----------
const ingredients = ['Real Coconut', 'Rum', 'Sugar', 'Evaporated Milk', 'Condensed Milk', 'Ginger', 'Cinnamon'];
const back = `<div class="back">
  <svg class="wm" viewBox="0 0 350 450" opacity="0.6">${frond(360, 470, 225, 210, 20, '#e9d3a8')}${frond(-10, -20, 40, 170, 30, '#efdcb6')}</svg>
  <div class="in">
    <div class="b-brand">✦ ${BRAND.toUpperCase()} ✦</div>
    <div class="b-name">${NAME}</div>
    <p class="story">Close your eyes and take a sip — warm sand, a sea breeze, the sun on your face. Every bottle is handmade in small batches, <em>bringing the island vibe straight to you.</em></p>
    <div class="hdr"><span>What's Inside</span></div>
    <ul class="ing">${ingredients.map(i => `<li>${i}</li>`).join('')}<li class="love">&amp; lots of Love <span>♥</span></li></ul>
    <div class="serve">Shake well &nbsp;·&nbsp; Serve chilled &nbsp;·&nbsp; Keep refrigerated</div>
    <div class="contains"><b>Contains:</b> Milk &nbsp;|&nbsp; ${VOLUME} &nbsp;|&nbsp; ${ABV}</div>
    <div class="batch"><span>Made by <i></i></span></div>
    <div class="batch"><span>Batch No. <i></i></span><span>Bottled <i></i></span></div>
    <p class="warn"><b>GOVERNMENT WARNING:</b> (1) ACCORDING TO THE SURGEON GENERAL, WOMEN SHOULD NOT DRINK ALCOHOLIC BEVERAGES DURING PREGNANCY BECAUSE OF THE RISK OF BIRTH DEFECTS. (2) CONSUMPTION OF ALCOHOLIC BEVERAGES IMPAIRS YOUR ABILITY TO DRIVE A CAR OR OPERATE MACHINERY, AND MAY CAUSE HEALTH PROBLEMS.</p>
  </div>
</div>`;

const css = `
@import url('https://fonts.googleapis.com/css2?family=Lato:wght@400;700;900&family=Pacifico&family=Playfair+Display:ital,wght@0,400;0,700;1,400;1,700&display=block');
*{box-sizing:border-box;margin:0;padding:0}
body{background:#fff}
.label{width:3.5in;height:4.5in;overflow:hidden;position:relative}
.back{width:100%;height:100%;background:#fdf3df;position:relative;font-family:Lato;color:#2b1424}
.back .wm{position:absolute;inset:0;width:100%;height:100%}
.back .in{position:absolute;inset:0.12in;border:1.5px solid #c9824a;border-radius:10px;padding:0.1in 0.17in 0.08in;display:flex;flex-direction:column;align-items:center;text-align:center}
.b-brand{font-weight:700;font-size:7.5pt;letter-spacing:2.5px;color:#c9824a;margin-top:2px}
.b-name{font-family:Pacifico;font-size:25pt;line-height:1.25;color:#7b2d5e}
.story{font-family:'Playfair Display';font-size:8.2pt;line-height:1.4;margin:2px 0 8px}
.story em{color:#b5452f}
.hdr{width:100%;display:flex;align-items:center;gap:6px;font-weight:900;font-size:8pt;letter-spacing:2.5px;text-transform:uppercase;color:#145a73}
.hdr::before,.hdr::after{content:'';flex:1;height:1px;background:#c9824a}
.ing{list-style:none;display:grid;grid-template-columns:1fr 1fr;grid-template-rows:repeat(4,auto) auto;grid-auto-flow:column;gap:4px 10px;width:100%;margin:8px 0 6px;padding-left:6px;font-size:9.2pt;font-weight:700;text-align:left}
.ing li::before{content:'✿';color:#e07a3f;margin-right:5px;font-size:7pt}
.ing li.love{grid-column:1/-1;text-align:center;font-family:Pacifico;font-weight:400;font-size:15pt;color:#c0392b;margin-top:4px;grid-row:5}
.ing li.love::before{content:none}
.serve{font-size:7pt;font-weight:700;letter-spacing:.5px;color:#145a73;margin-bottom:4px}
.contains{font-size:6.8pt;margin-bottom:8px}
.batch{display:flex;gap:12px;width:100%;font-size:6.8pt;margin-bottom:7px}
.batch span{flex:1;display:flex;align-items:flex-end;gap:3px;white-space:nowrap}
.batch i{flex:1;border-bottom:.8px solid #2b1424;height:8px}
.warn{font-size:5.1pt;line-height:1.3;text-align:justify;margin-top:auto}
`;
const page = (body, pageCss) => `<!doctype html><html><head><meta charset="utf-8"><style>${css}${pageCss}</style></head><body>${body}</body></html>`;
const frontDiv = `<div class="label">${front}</div>`, backDiv = `<div class="label">${back}</div>`;

(async () => {
  fs.mkdirSync('print', { recursive: true });
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ deviceScaleFactor: 300 / 96, viewport: { width: 336, height: 432 } });
  const p = await ctx.newPage();
  const shoot = async (html, out) => { await p.setContent(html, { waitUntil: 'networkidle' }); await p.evaluate(() => document.fonts.ready); await p.locator('.label').screenshot({ path: out }); };
  await shoot(page(frontDiv, ''), 'print/front-label-300dpi.png');
  await shoot(page(backDiv, ''), 'print/back-label-300dpi.png');
  // exact-size 2-page PDF (page 1 front, page 2 back) for online printers
  await p.setContent(page(frontDiv + backDiv, '@page{size:3.5in 4.5in;margin:0}'), { waitUntil: 'networkidle' });
  await p.evaluate(() => document.fonts.ready);
  await p.pdf({ path: 'print/cremas-labels-3.5x4.5in.pdf', width: '3.5in', height: '4.5in', printBackground: true });
  // letter sheet: 2 fronts + 2 backs with thin cut guides, for home sticker paper
  const cell = d => `<div style="outline:0.5px dashed #999">${d}</div>`;
  const sheet = `<div style="width:8.5in;height:11in;display:grid;grid-template-columns:3.5in 3.5in;grid-template-rows:4.5in 4.5in;gap:0.25in;justify-content:center;align-content:center">${cell(frontDiv)}${cell(backDiv)}${cell(frontDiv)}${cell(backDiv)}</div>`;
  await p.setContent(page(sheet, '@page{size:letter;margin:0}'), { waitUntil: 'networkidle' });
  await p.evaluate(() => document.fonts.ready);
  await p.pdf({ path: 'print/cremas-print-sheet-letter.pdf', format: 'Letter', printBackground: true });
  await browser.close();
  console.log('done');
})();
