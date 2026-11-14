// Builds the Crémas bottle labels: front + back (3.5" x 4.5"), PNG @300 DPI, PDFs, and a letter print sheet.
// Edit the settings below, then run: node build.js
const fs = require('fs');
const { chromium } = require('playwright');

const BRAND   = 'Island Vibes';
const NAME    = 'Crémas';
const TAG     = 'Bringing the island to you';
const VOLUME  = '750 mL';
const ABV     = 'XX% ALC./VOL.';                // <-- put your real alcohol % here

const W = 350, H = 450;
const INK = '#2b1424', INK2 = '#3f1d36', RIM = '#ff9a4d', GOLD = '#ffd27a', CREAM = '#fff6e4';
const f = n => +n.toFixed(2);

// ---------- drawing helpers ----------
function limb(a, b, wa, wb) {
  const dx = b[0] - a[0], dy = b[1] - a[1], L = Math.hypot(dx, dy) || 1, nx = -dy / L, ny = dx / L;
  const p = [[a[0] + nx * wa / 2, a[1] + ny * wa / 2], [b[0] + nx * wb / 2, b[1] + ny * wb / 2], [b[0] - nx * wb / 2, b[1] - ny * wb / 2], [a[0] - nx * wa / 2, a[1] - ny * wa / 2]];
  return `<polygon points="${p.map(q => q.map(f).join(',')).join(' ')}"/><circle cx="${a[0]}" cy="${a[1]}" r="${wa / 2}"/><circle cx="${b[0]}" cy="${b[1]}" r="${wb / 2}"/>`;
}
const chain = (pts, ws) => pts.slice(1).map((p, i) => limb(pts[i], p, ws[i], ws[i + 1])).join('');
function bottle(x, y, rot, s = 1) {
  return `<g transform="translate(${x} ${y}) rotate(${rot}) scale(${s})">
    <rect x="-1.3" y="-17" width="2.6" height="6.5" rx="0.8" fill="#f6e7c8"/>
    <rect x="-1.7" y="-18.6" width="3.4" height="2.2" rx="0.6" fill="#c0392b"/>
    <path d="M-1.3 -11 Q-4 -9.5 -4 -6 L-4 4 Q-4 6 -2 6 L2 6 Q4 6 4 4 L4 -6 Q4 -9.5 1.3 -11 Z" fill="#fff4dd"/>
    <rect x="-4" y="-3.2" width="8" height="5" fill="#e07a3f"/><rect x="-4" y="-3.2" width="8" height="1" fill="${GOLD}"/>
    <rect x="-3" y="-8" width="1.2" height="12" rx="0.6" fill="#fff" opacity="0.7"/>
  </g>`;
}
// figure with sunset rim-light: draws a glow copy offset toward the sun, then the silhouette
function figure(body, tx, ty, flip, rimDx = 0.9, rimDy = -0.4, both = false) {
  const g = `<g transform="translate(${tx} ${ty}) scale(${flip ? -1 : 1} 1)">${body}</g>`;
  let s = `<g fill="${RIM}" transform="translate(${rimDx} ${rimDy})">${g}</g>`;
  if (both) s += `<g fill="${RIM}" transform="translate(${-rimDx} ${rimDy})">${g}</g>`;
  return s + `<g fill="${INK}">${g}</g>`;
}
function seatedBody({ lean = 0, legsAlt = false }) {
  const hip = [0, -6], sh = [lean, -31];
  let s = `<ellipse cx="0" cy="-5" rx="8.5" ry="5.5"/>`;
  s += chain([[1, -5], [17, -19], [26, -1]], [9.5, 6.5, 4]) + `<ellipse cx="29" cy="-0.6" rx="4.6" ry="2"/>`;
  s += chain([[0, -4], legsAlt ? [20, -12] : [15, -15], legsAlt ? [31, -1] : [23, -1]], [9, 6, 3.8]) + `<ellipse cx="${legsAlt ? 34 : 26}" cy="-0.6" rx="4.4" ry="1.9"/>`;
  s += limb(hip, sh, 14, 12.5);
  s += `<path d="M${sh[0] - 6} ${sh[1] + 1} Q${sh[0]} ${sh[1] - 4} ${sh[0] + 6} ${sh[1] + 1} Z"/>`; // shoulders
  s += limb([sh[0], sh[1]], [sh[0] + 1, sh[1] - 6], 4.5, 4.5); // neck
  return s;
}
function frond(cx, cy, ang, len, droop, color, lw = 1.25) {
  const r = ang * Math.PI / 180;
  const ex = cx + Math.cos(r) * len, ey = cy + Math.sin(r) * len + droop;
  const mx = cx + Math.cos(r) * len * 0.55, my = cy + Math.sin(r) * len * 0.55 - Math.abs(droop) * 0.25 - 8;
  const B = t => [(1 - t) ** 2 * cx + 2 * (1 - t) * t * mx + t * t * ex, (1 - t) ** 2 * cy + 2 * (1 - t) * t * my + t * t * ey];
  let s = `<path d="M${cx} ${cy} Q${f(mx)} ${f(my)} ${f(ex)} ${f(ey)}" stroke="${color}" stroke-width="2.6" fill="none" stroke-linecap="round"/>`;
  const n = 18;
  for (let i = 1; i <= n; i++) {
    const t = i / (n + 1), [px, py] = B(t), [qx, qy] = B(t + 0.01);
    const a = Math.atan2(qy - py, qx - px);
    const L = (26 * Math.sin(Math.PI * Math.pow(t, 0.8)) + 5) * lw * (len / 110);
    for (const sg of [1, -1]) {
      const la = a + sg * 0.95 + (Math.cos(a) >= 0 ? 0.45 : -0.45);
      const tx = px + Math.cos(la) * L, ty = py + Math.sin(la) * L + 5 * lw;
      const cxp = px + Math.cos(la) * L * 0.5, cyp = py + Math.sin(la) * L * 0.5 - 1.5;
      const w = 1.9 * lw;
      s += `<path d="M${f(px)} ${f(py)} Q${f(cxp - w)} ${f(cyp - w)} ${f(tx)} ${f(ty)} Q${f(cxp + w)} ${f(cyp + w)} ${f(px)} ${f(py)} Z" fill="${color}"/>`;
    }
  }
  return s;
}
function trunk(p0, c1, c2, p3, w0, w1, color, ring) {
  const B = t => [0, 1].map(k => (1 - t) ** 3 * p0[k] + 3 * (1 - t) ** 2 * t * c1[k] + 3 * (1 - t) * t * t * c2[k] + t ** 3 * p3[k]);
  let s = '', N = 24;
  for (let i = 0; i < N; i++) {
    const a = B(i / N), b = B((i + 1.15) / N), w = w0 + (w1 - w0) * i / N;
    s += limb(a, b, w, w * 0.93).replace(/<(polygon|circle)/g, `<$1 fill="${color}"`);
    const dx = b[0] - a[0], dy = b[1] - a[1], L = Math.hypot(dx, dy), nx = -dy / L, ny = dx / L;
    s += `<path d="M${f(a[0] - nx * w / 2)} ${f(a[1] - ny * w / 2)} q${f(dx * 0.3 + nx * w / 2)} ${f(dy * 0.3 + ny * w / 2 + 2.4)} ${f(nx * w)} ${f(ny * w)}" stroke="${ring}" stroke-width="0.9" fill="none"/>`;
  }
  return s;
}
function hibiscus(x, y, r, rot, c1, c2) {
  let p = '';
  for (let i = 0; i < 5; i++) p += `<path d="M0 0 C ${-r * 0.7} ${-r * 0.3}, ${-r * 0.6} ${-r * 1.05}, 0 ${-r} C ${r * 0.6} ${-r * 1.05}, ${r * 0.7} ${-r * 0.3}, 0 0 Z" fill="${c1}" transform="rotate(${i * 72})"/><path d="M0 0 L0 ${-r * 0.75}" stroke="${c2}" stroke-width="0.5" opacity="0.5" transform="rotate(${i * 72})"/>`;
  return `<g transform="translate(${x} ${y}) rotate(${rot})">${p}<circle r="${r * 0.2}" fill="${c2}"/><path d="M0 0 L${r * 0.45} ${-r * 0.85}" stroke="#ffd166" stroke-width="1" stroke-linecap="round"/><circle cx="${r * 0.45}" cy="${-r * 0.85}" r="1.1" fill="#ffd166"/></g>`;
}
const leaf = (x, y, rot, s, c) => `<path transform="translate(${x} ${y}) rotate(${rot}) scale(${s})" d="M0 0 C 6 -4, 14 -4, 20 0 C 14 4, 6 4, 0 0 Z" fill="${c}"/>`;
const sparkle = (x, y, r, c = '#fff3c4', o = 1) => `<path transform="translate(${x} ${y})" d="M0 ${-r} Q0.6 -0.6 ${r} 0 Q0.6 0.6 0 ${r} Q-0.6 0.6 ${-r} 0 Q-0.6 -0.6 0 ${-r} Z" fill="${c}" opacity="${o}"/>`;

// ---------- FRONT ----------
const HZ = 318, SX = 252, SY = HZ;
const crown = [88, 196];

// people
const P1 = figure(seatedBody({ lean: -6 }) +
  chain([[-6, -29], [-13, -17], [-17, -4]], [5, 4, 3.4]) + `<ellipse cx="-18" cy="-2.5" rx="3" ry="1.6"/>` +       // arm propped behind
  `<circle cx="-7" cy="-42" r="6.6"/>` +                                                                              // head (tilted back laughing)
  `<g transform="rotate(-14 -7 -47)"><ellipse cx="-7" cy="-47" rx="14" ry="2.4"/><path d="M-13 -47 Q-7 -59 -1 -47 Z"/></g>` + // sun hat
  chain([[-4, -31], [5, -46], [9, -62]], [5, 4.2, 3.6]) + `<circle cx="9" cy="-62" r="2.4"/>`, 112, 389, false) +
  bottle(121, 324, 14);
const P2 = figure(seatedBody({ lean: 1, legsAlt: true }) +
  `<circle cx="2" cy="-42" r="6.6"/><path d="M-4.6 -43 Q-4 -51 3 -50.5 Q9 -50 8.6 -43 Q5 -47 -4.6 -43 Z"/>` +       // head + short hair
  chain([[1, -29], [12, -20], [21, -15]], [5, 4, 3.4]) +                                                               // arm on knee
  chain([[3, -30], [16, -31], [28, -40]], [5, 4.2, 3.6]) + `<circle cx="28" cy="-40" r="2.4"/>`, 158, 389, false) +
  bottle(186, 347, 38);
const P3 = figure(seatedBody({ lean: 0 }) +
  `<circle cx="2" cy="-42" r="6.4"/>` +
  [[0, -48, 6], [-5, -46, 5.5], [5, -48, 5.5], [-4, -40, 5], [2, -53, 4.6], [-6, -52, 4]].map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}"/>`).join('') + // afro
  `<circle cx="7.4" cy="-40" r="1.3"/>` +                                                                              // earring
  chain([[0, -29], [11, -17], [19, -14]], [5, 4, 3.4]) +
  chain([[2, -30], [15, -31], [27, -40]], [5, 4.2, 3.6]) + `<circle cx="27" cy="-40" r="2.4"/>`, 231, 389, true) +
  bottle(203, 347, -38);
// dancer standing in front of the sun
const D = (() => {
  let s = '';
  s += chain([[-4, -36], [-6, -19], [-8, -1]], [6.5, 4.6, 3]) + `<ellipse cx="-9.5" cy="-0.6" rx="3.6" ry="1.6"/>`;
  s += chain([[4, -36], [9, -20], [7, -4]], [6.5, 4.6, 3]) + `<path d="M5 -4 L10 -1 L9 0 L4 -2 Z"/>`;
  s += `<path d="M-5 -46 L5 -46 C 9 -39, 16 -31, 23 -26 Q 12 -21 4 -24 Q -4 -21 -13 -25 C -10 -32 -7 -40 -5 -46 Z"/>`; // flowing skirt
  s += `<path d="M-5 -46 C -7 -53, -9 -59, -8 -64 L 8 -64 C 9 -59, 7 -53, 5 -46 Z"/>`;
  s += limb([0, -64], [1, -69], 4.2, 4.2);
  s += `<ellipse cx="1.5" cy="-75" rx="5.4" ry="6.3" transform="rotate(12 1.5 -75)"/>`;
  s += [[-3, -80, 4.6], [-7, -76, 4.4], [-9, -71, 3.8], [-11, -66, 3.2], [2, -82, 4.2], [6, -79, 3.6], [-12, -61, 2.6]].map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}"/>`).join('');
  s += chain([[-7, -63], [-15, -76], [-13, -91]], [4.4, 3.6, 3]) + `<circle cx="-13" cy="-91" r="2.2"/>`;
  s += chain([[7, -63], [16, -73], [22, -86]], [4.4, 3.6, 3]) + `<path d="M22 -86 l-1.5 -4 M22 -86 l0.5 -4.4 M22 -86 l2.4 -3.6 M22 -86 l3.6 -2" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/><circle cx="22" cy="-86" r="2"/>`;
  return s;
})();
const dancer = `<g color="${INK}">${figure(D, 291, 402, false, 0.8, -0.2, true)}</g>` + bottle(278, 313, -12) +
  sparkle(318, 300, 3.4) + sparkle(262, 292, 2.4) + sparkle(312, 324, 2) +
  `<path d="M318 355 q6 -2 9 3 M321 368 q6 0 8 5 M262 352 q-6 -1 -9 4" stroke="${GOLD}" stroke-width="0.9" fill="none" stroke-linecap="round" opacity="0.8"/>`;

// blanket
const blanket = (() => {
  const tl = [86, 381], tr = [262, 377], br = [272, 400], bl = [78, 404], cols = ['#e07a3f', '#fff3dc', '#3f8ea6', '#fff3dc', '#e63946', '#ffd27a', '#3f8ea6', '#fff3dc', '#e07a3f', '#fff3dc', '#e63946'];
  const L = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  let s = '';
  cols.forEach((c, i) => { const t0 = i / cols.length, t1 = (i + 1) / cols.length; s += `<polygon fill="${c}" points="${[L(tl, tr, t0), L(tl, tr, t1), L(bl, br, t1), L(bl, br, t0)].map(p => p.map(f).join(',')).join(' ')}"/>`; });
  s += `<polygon fill="#5a1f45" opacity="0.32" points="${[tl, tr, br, bl].map(p => p.join(',')).join(' ')}"/>`;
  s += `<polygon fill="${INK}" opacity="0.18" points="${[bl, br, [272, 402.5], [78, 406.5]].map(p => p.join(',')).join(' ')}"/>`;
  return s;
})();

const pineapple = `<g transform="translate(252 384)">
  ${leaf(0, -9, -100, 0.5, '#2e7d4f')}${leaf(0, -9, -70, 0.55, '#3c9a5f')}${leaf(0, -9, -125, 0.45, '#3c9a5f')}${leaf(0, -9, -50, 0.42, '#2e7d4f')}
  <ellipse cx="0" cy="0" rx="6.4" ry="9.5" fill="#f2b33d"/>
  <g stroke="#b9732a" stroke-width="0.7" opacity="0.8"><path d="M-6 -4 L4 6 M-5 -8 L6 2 M-3 -9.5 L6 -3 M-6 2 L0 8"/><path d="M6 -4 L-4 6 M5 -8 L-6 2 M3 -9.5 L-6 -3 M6 2 L0 8"/></g>
  <ellipse cx="-2.5" cy="-2" rx="1.6" ry="5" fill="#fff3c4" opacity="0.35"/></g>
  <g transform="translate(70 395)"><circle r="7" fill="#5a3324"/><circle r="5.6" fill="#fff6e4"/><path d="M1 -1 L9 -14" stroke="#e63946" stroke-width="1.4" stroke-linecap="round"/>${hibiscus(-3, -5, 3.2, 10, '#ff6b81', '#a4243b')}</g>`;

let palm = trunk([50, 462], [70, 380], [58, 280], crown, 18, 9.5, INK, '#5a2d47');
palm += frond(...crown, 210, 85, 30, INK2) + frond(...crown, 248, 46, 6, INK2) + frond(...crown, -40, 70, 16, INK2);
palm += frond(...crown, 175, 80, 46, INK) + frond(...crown, 198, 95, 22, INK) + frond(...crown, -10, 118, 40, INK) + frond(...crown, 18, 98, 62, INK) + frond(...crown, -60, 58, 6, INK) + frond(...crown, 60, 66, 52, INK) + frond(...crown, 230, 58, 8, INK);
palm += `<circle cx="${crown[0] + 5}" cy="${crown[1] + 8}" r="5.4" fill="#4a2a1f"/><circle cx="${crown[0] - 5}" cy="${crown[1] + 9}" r="5" fill="#40241b"/><circle cx="${crown[0] + 1}" cy="${crown[1] + 14}" r="5" fill="#4a2a1f"/><circle cx="${crown[0] + 3}" cy="${crown[1] + 6.5}" r="1.4" fill="${RIM}" opacity="0.6"/>`;

const island = `<path d="M118 ${HZ} Q 130 ${HZ - 9} 150 ${HZ - 11} Q 168 ${HZ - 13} 182 ${HZ - 6} Q 194 ${HZ - 3} 204 ${HZ} Z" fill="#7a3558"/>
  <g transform="translate(156 ${HZ - 11}) scale(0.16)">${trunk([0, 0], [4, -40], [-4, -80], [10, -120], 14, 9, '#7a3558', '#7a3558')}${frond(10, -120, 200, 80, 20, '#7a3558')}${frond(10, -120, -20, 80, 22, '#7a3558')}${frond(10, -120, -70, 50, 6, '#7a3558')}${frond(10, -120, 240, 50, 6, '#7a3558')}</g>
  <g transform="translate(170 ${HZ - 12}) scale(0.12)">${trunk([0, 0], [-4, -40], [6, -80], [-8, -120], 14, 9, '#7a3558', '#7a3558')}${frond(-8, -120, 200, 80, 20, '#7a3558')}${frond(-8, -120, -20, 80, 22, '#7a3558')}${frond(-8, -120, -110, 50, 6, '#7a3558')}</g>`;
const boat = `<g transform="translate(320 ${HZ - 1})"><path d="M-9 0 L9 0 L6 3 L-6 3 Z" fill="#3a1a33"/><path d="M0 -1 L0 -19 L9 -2 Z" fill="#fff0d6" opacity="0.9"/><path d="M-1 -2 L-1 -15 L-8 -2 Z" fill="#ffe0b8" opacity="0.8"/></g>`;
const clouds = [[30, 212, 70, 4], [95, 222, 55, 3.2], [240, 206, 80, 4.4], [300, 226, 46, 3], [180, 238, 60, 3], [20, 248, 40, 2.6], [258, 250, 60, 2.6]]
  .map(([x, y, w, h]) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${h / 2}" fill="#ff9e7a" opacity="0.5"/><rect x="${x + w * 0.15}" y="${y - h * 0.35}" width="${w * 0.55}" height="${h * 0.6}" rx="${h * 0.3}" fill="#ffd0a3" opacity="0.55"/>`).join('');
const reflection = Array.from({ length: 11 }, (_, i) => { const y = HZ + 4 + i * 4.6 + i * i * 0.12, w = 58 - i * 4.8 + (i % 2) * 6; return `<rect x="${f(SX - w / 2 + (i % 3 - 1) * 3)}" y="${f(y)}" width="${f(w)}" height="${f(1.8 - i * 0.07)}" rx="1" fill="#fff3c4" opacity="${f(0.9 - i * 0.055)}"/>`; }).join('');
const seaLines = [[14, 328, 26], [60, 335, 34], [120, 330, 22], [300, 333, 30], [10, 348, 30], [96, 352, 26], [318, 350, 24], [180, 362, 20]].map(([x, y, w]) => `<rect x="${x}" y="${y}" width="${w}" height="1" rx="0.5" fill="#bfe6ef" opacity="0.5"/>`).join('');
const stars = [[40, 60, 1], [300, 40, 1.1], [325, 112, 0.8], [215, 24, 0.9], [14, 128, 0.9], [62, 30, 0.7], [150, 18, 0.8], [338, 170, 0.7], [276, 70, 0.6], [30, 170, 0.6], [110, 140, 0.6]].map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="#fff" opacity="0.75"/>`).join('') + sparkle(318, 72, 3.2, '#fff', 0.85) + sparkle(28, 92, 2.4, '#fff', 0.7);

const front = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 ${W} ${H}" width="100%" height="100%">
<defs>
  <linearGradient id="sky" x1="0" y1="0" x2="0" y2="${HZ}" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#241540"/><stop offset="0.3" stop-color="#5e2759"/><stop offset="0.55" stop-color="#b8405a"/>
    <stop offset="0.75" stop-color="#e9624b"/><stop offset="0.9" stop-color="#f7a046"/><stop offset="1" stop-color="#ffd27a"/>
  </linearGradient>
  <linearGradient id="sea" x1="0" y1="${HZ}" x2="0" y2="400" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#f08c5a"/><stop offset="0.12" stop-color="#c96f6a"/><stop offset="0.4" stop-color="#3f8ea6"/><stop offset="1" stop-color="#145a73"/></linearGradient>
  <linearGradient id="sand" x1="0" y1="370" x2="0" y2="450" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#f6cf92"/><stop offset="1" stop-color="#d9955a"/></linearGradient>
  <linearGradient id="sun" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fffbe0"/><stop offset="1" stop-color="#ffd27a"/></linearGradient>
  <linearGradient id="title" x1="0" y1="0" x2="0" y2="1"><stop offset="0.2" stop-color="#fffaf0"/><stop offset="1" stop-color="#ffe2a8"/></linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#fff2b3" stop-opacity="0.95"/><stop offset="0.4" stop-color="#ffc46b" stop-opacity="0.45"/><stop offset="1" stop-color="#ff8a5b" stop-opacity="0"/></radialGradient>
  <radialGradient id="vig" cx="0.5" cy="0.55" r="0.75"><stop offset="0.6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#14051a" stop-opacity="0.45"/></radialGradient>
  <mask id="sunStripes"><rect x="0" y="0" width="${W}" height="${H}" fill="#fff"/>${[[296, 1.6], [303, 2.1], [309, 2.6], [314.2, 3]].map(([y, h]) => `<rect x="0" y="${y}" width="${W}" height="${h}" fill="#000"/>`).join('')}</mask>
  <filter id="ts" x="-10%" y="-20%" width="120%" height="150%"><feDropShadow dx="0" dy="1.5" stdDeviation="1.4" flood-color="#14051a" flood-opacity="0.6"/></filter>
  <path id="arc" d="M90 56 Q175 22 260 56"/>
  <path id="ring" d="M -18.5 0 A 18.5 18.5 0 1 1 18.5 0 A 18.5 18.5 0 1 1 -18.5 0"/>
</defs>
<rect width="${W}" height="${H}" fill="url(#sky)"/>
${stars}
<circle cx="${SX}" cy="${SY}" r="125" fill="url(#glow)"/>
${clouds}
<circle cx="${SX}" cy="${SY}" r="50" fill="url(#sun)" mask="url(#sunStripes)"/>
<g fill="none" stroke="${INK}" stroke-width="1.3" stroke-linecap="round" opacity="0.75">
  <path d="M186 186 q4.5 -4.5 9 0 q4.5 -4.5 9 0"/><path d="M214 172 q3.5 -3.5 7 0 q3.5 -3.5 7 0"/><path d="M200 200 q3 -3 6 0 q3 -3 6 0"/>
</g>
<rect x="0" y="${HZ}" width="${W}" height="90" fill="url(#sea)"/>
${island}${boat}${reflection}${seaLines}
<path d="M0 370 Q 60 362 120 368 T 240 366 T ${W} 362 L ${W} ${H} L 0 ${H} Z" fill="#fff6e4" opacity="0.85"/>
<path d="M0 373 q8 -3 16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 L ${W} ${H} L 0 ${H} Z" fill="#e9f6f4" opacity="0.6" transform="translate(0 -1)"/>
<path d="M0 376 Q 70 368 140 374 T 260 371 T ${W} 368 L ${W} ${H} L 0 ${H} Z" fill="url(#sand)"/>
${Array.from({ length: 70 }, (_, i) => `<circle cx="${(i * 53.7) % W}" cy="${380 + (i * 37.3) % 34}" r="${0.4 + (i % 3) * 0.2}" fill="#b9733d" opacity="0.35"/>`).join('')}
<ellipse cx="175" cy="404" rx="120" ry="6" fill="#9c5a2e" opacity="0.28"/>
${blanket}
${palm}
${P1}${P2}${P3}
${sparkle(194, 312, 3.4)}<g stroke="#fff3c4" stroke-width="1.1" stroke-linecap="round"><line x1="194" y1="322" x2="194" y2="317"/><line x1="185" y1="324" x2="181" y2="320"/><line x1="203" y1="324" x2="207" y2="320"/></g>
<g fill="#fff3c4" font-family="DejaVu Sans" opacity="0.9"><text x="132" y="304" font-size="10">♪</text><text x="144" y="292" font-size="8">♫</text></g>
${pineapple}
${dancer}
<path d="M318 412 q2 -14 -4 -22 M322 412 q4 -12 12 -18 M326 412 q-1 -10 6 -14" stroke="#2e7d4f" stroke-width="1.8" fill="none" stroke-linecap="round"/>
${leaf(296, 408, -40, 0.9, '#2e7d4f')}${leaf(338, 410, -150, 0.8, '#3c9a5f')}
${hibiscus(331, 399, 10, 20, '#e63946', '#8d1b2a')}${hibiscus(311, 404, 7, -30, '#ff6b81', '#a4243b')}
${leaf(10, 410, -60, 0.8, '#2e7d4f')}${hibiscus(26, 403, 8, 40, '#ff6b81', '#a4243b')}
<rect width="${W}" height="${H}" fill="url(#vig)"/>
<g transform="translate(298 152) rotate(-10)">
  <circle r="27" fill="${INK}" opacity="0.9"/><circle r="25" fill="none" stroke="${GOLD}" stroke-width="0.8"/><circle r="14.5" fill="none" stroke="${GOLD}" stroke-width="0.5" stroke-dasharray="1 1.4"/>
  <text font-family="Lato" font-weight="900" font-size="4.4" fill="${GOLD}"><textPath href="#ring" textLength="114" lengthAdjust="spacing">HANDMADE ✦ SMALL BATCH ✦ WITH LOVE ✦</textPath></text>
  <text y="-1.2" text-anchor="middle" font-family="Lato" font-weight="900" font-size="5.4" letter-spacing="0.5" fill="${CREAM}">REAL</text>
  <text y="5" text-anchor="middle" font-family="Lato" font-weight="900" font-size="4" letter-spacing="0.1" fill="${CREAM}">COCONUT</text>
</g>
<g filter="url(#ts)">
  <text font-family="Lato" font-weight="900" font-size="10.5" letter-spacing="4.5" fill="${GOLD}"><textPath href="#arc" startOffset="50%" text-anchor="middle">✦ ${BRAND.toUpperCase()} ✦</textPath></text>
</g>
<text x="177.5" y="109.5" text-anchor="middle" font-family="Pacifico" font-size="64" fill="#e2574c" opacity="0.95">${NAME}</text>
<text x="175" y="107" text-anchor="middle" font-family="Pacifico" font-size="64" fill="url(#title)" filter="url(#ts)">${NAME}</text>
<g filter="url(#ts)">
  <text x="175" y="133" text-anchor="middle" font-family="Lato" font-weight="900" font-size="9" letter-spacing="3.4" fill="${GOLD}">COCONUT CREAM LIQUEUR</text>
  <line x1="80" y1="143" x2="160" y2="143" stroke="${GOLD}" stroke-width="0.6" opacity="0.7"/><line x1="190" y1="143" x2="270" y2="143" stroke="${GOLD}" stroke-width="0.6" opacity="0.7"/>
  ${hibiscus(175, 143, 4.4, 0, '#e63946', '#8d1b2a')}
</g>
<rect x="0" y="414" width="${W}" height="36" fill="${INK}" opacity="0.94"/>
<line x1="0" y1="414.4" x2="${W}" y2="414.4" stroke="${GOLD}" stroke-width="0.8"/>
<text x="175" y="430" text-anchor="middle" font-family="Playfair Display" font-style="italic" font-size="14" fill="${GOLD}">${TAG}</text>
<text x="175" y="442.5" text-anchor="middle" font-family="Lato" font-weight="700" font-size="6.6" letter-spacing="2" fill="${CREAM}">${VOLUME.toUpperCase()}   ✦   HANDCRAFTED   ✦   ${ABV}</text>
<rect x="7" y="7" width="${W - 14}" height="${H - 14}" rx="9" fill="none" stroke="${GOLD}" stroke-width="0.9" opacity="0.85"/>
<rect x="10" y="10" width="${W - 20}" height="${H - 20}" rx="7" fill="none" stroke="${GOLD}" stroke-width="0.35" opacity="0.6"/>
</svg>`;

// ---------- BACK ----------
const header = `<svg class="hdr-scene" viewBox="0 0 350 110" preserveAspectRatio="xMidYMid slice">
  <defs><linearGradient id="bsky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#241540"/><stop offset="0.45" stop-color="#7b2d5e"/><stop offset="0.8" stop-color="#e9624b"/><stop offset="1" stop-color="#f7a046"/></linearGradient>
  <mask id="bstr"><rect width="350" height="110" fill="#fff"/>${[[80, 1.4], [85, 1.8], [89.4, 2.2]].map(([y, h]) => `<rect y="${y}" width="350" height="${h}" fill="#000"/>`).join('')}</mask>
  <radialGradient id="bglow"><stop offset="0" stop-color="#fff2b3" stop-opacity="0.9"/><stop offset="1" stop-color="#ff8a5b" stop-opacity="0"/></radialGradient></defs>
  <rect width="350" height="110" fill="url(#bsky)"/>
  <circle cx="175" cy="94" r="90" fill="url(#bglow)"/>
  <circle cx="175" cy="94" r="30" fill="#fff0b8" mask="url(#bstr)"/>
  <rect y="94" width="350" height="16" fill="#3f8ea6"/><rect y="94" width="350" height="3" fill="#e98a5b" opacity="0.7"/>
  ${[0, 1, 2, 3].map(i => `<rect x="${163 - i * -3 - i * 3}" y="${97 + i * 3}" width="${24 - i * 5}" height="1.1" rx="0.5" fill="#fff3c4" opacity="0.8" transform="translate(${i * 2.5} 0)"/>`).join('')}
  <g transform="translate(0 6)">${trunk([22, 112], [30, 80], [20, 50], [42, 30], 10, 6, INK, '#5a2d47')}${frond(42, 30, 200, 55, 18, INK)}${frond(42, 30, -15, 70, 22, INK)}${frond(42, 30, 20, 60, 34, INK)}${frond(42, 30, -60, 40, 4, INK)}${frond(42, 30, 240, 36, 4, INK)}</g>
  <g transform="translate(350 6) scale(-1 1)">${trunk([22, 112], [30, 80], [20, 50], [40, 36], 9, 6, INK, '#5a2d47')}${frond(40, 36, 200, 50, 18, INK)}${frond(40, 36, -15, 64, 22, INK)}${frond(40, 36, 20, 54, 30, INK)}${frond(40, 36, -60, 36, 4, INK)}</g>
  <path d="M0 104 q8 -4 16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 t16 0 L350 110 L0 110 Z" fill="#fdf3df"/>
</svg>`;
const ingredients = ['Real Coconut', 'Rum', 'Sugar', 'Evaporated Milk', 'Condensed Milk', 'Ginger', 'Cinnamon'];
const back = `<div class="back">
  ${header}
  <div class="b-top"><div class="b-brand">✦ ${BRAND.toUpperCase()} ✦</div><div class="b-name">${NAME}</div></div>
  <svg class="wm" viewBox="0 0 350 450" opacity="0.45">${frond(370, 470, 222, 190, 20, '#e9d3a8')}</svg>
  <div class="in">
    <p class="story">Close your eyes and take a sip — warm sand, a sea breeze, the sun on your face. Every bottle is handmade in small batches, <em>bringing the island vibe straight to you.</em></p>
    <div class="hdr"><span>What's Inside</span></div>
    <ul class="ing">${ingredients.map(i => `<li>${i}</li>`).join('')}<li class="love">&amp; lots of Love <span>♥</span></li></ul>
    <div class="serve">Shake well &nbsp;✦&nbsp; Serve chilled &nbsp;✦&nbsp; Keep refrigerated</div>
    <div class="contains"><b>Contains:</b> Milk &nbsp;|&nbsp; ${VOLUME} &nbsp;|&nbsp; ${ABV}</div>
    <div class="batch"><span>Made by <i></i></span></div>
    <div class="batch"><span>Batch No. <i></i></span><span>Bottled <i></i></span></div>
    <p class="warn"><b>GOVERNMENT WARNING:</b> (1) ACCORDING TO THE SURGEON GENERAL, WOMEN SHOULD NOT DRINK ALCOHOLIC BEVERAGES DURING PREGNANCY BECAUSE OF THE RISK OF BIRTH DEFECTS. (2) CONSUMPTION OF ALCOHOLIC BEVERAGES IMPAIRS YOUR ABILITY TO DRIVE A CAR OR OPERATE MACHINERY, AND MAY CAUSE HEALTH PROBLEMS.</p>
  </div>
  <div class="frame"></div>
</div>`;

const css = `
@import url('https://fonts.googleapis.com/css2?family=Lato:wght@400;700;900&family=Pacifico&family=Playfair+Display:ital,wght@0,400;0,700;1,400;1,700&display=block');
*{box-sizing:border-box;margin:0;padding:0}
body{background:#fff}
.label{width:3.5in;height:4.5in;overflow:hidden;position:relative}
.back{width:100%;height:100%;background:#fdf3df;position:relative;font-family:Lato;color:#2b1424}
.hdr-scene{position:absolute;left:0;top:0;width:100%;height:1.1in;overflow:hidden}
.b-top{position:absolute;left:0;right:0;top:0.07in;text-align:center;filter:drop-shadow(0 1.5px 1.5px rgba(20,5,26,.6))}
.b-brand{font-weight:900;font-size:6.5pt;letter-spacing:3px;color:${GOLD};margin-top:4px}
.b-name{font-family:Pacifico;font-size:26pt;line-height:1.25;color:${CREAM}}
.back .wm{position:absolute;inset:0;width:100%;height:100%}
.back .in{position:absolute;left:0.2in;right:0.2in;top:1.14in;bottom:0.16in;display:flex;flex-direction:column;align-items:center;text-align:center}
.frame{position:absolute;inset:7px;border:1px solid #c9824a;border-radius:9px;pointer-events:none}
.frame::after{content:'';position:absolute;inset:2.5px;border:.4px solid #c9824a;border-radius:7px;opacity:.6}
.story{font-family:'Playfair Display';font-size:7.8pt;line-height:1.38;margin:0 0 6px}
.story em{color:#b5452f}
.hdr{width:100%;display:flex;align-items:center;gap:6px;font-weight:900;font-size:7.6pt;letter-spacing:2.5px;text-transform:uppercase;color:#145a73}
.hdr::before,.hdr::after{content:'';flex:1;height:1px;background:linear-gradient(90deg,transparent,#c9824a)}
.hdr::after{background:linear-gradient(90deg,#c9824a,transparent)}
.ing{list-style:none;display:grid;grid-template-columns:1fr 1fr;grid-template-rows:repeat(4,auto) auto;grid-auto-flow:column;gap:2.5px 10px;width:100%;margin:6px 0 3px;padding-left:10px;font-size:8.8pt;font-weight:700;text-align:left}
.ing li::before{content:'✿';color:#e07a3f;margin-right:5px;font-size:7pt}
.ing li.love{grid-column:1/-1;grid-row:5;text-align:center;font-family:Pacifico;font-weight:400;font-size:14.5pt;color:#c0392b;margin-top:2px;padding-right:10px}
.ing li.love::before{content:none}
.serve{font-size:6.8pt;font-weight:700;letter-spacing:.5px;color:#145a73;margin-bottom:3px}
.contains{font-size:6.6pt;margin-bottom:6px}
.batch{display:flex;gap:12px;width:100%;font-size:6.6pt;margin-bottom:6px}
.batch span{flex:1;display:flex;align-items:flex-end;gap:3px;white-space:nowrap}
.batch i{flex:1;border-bottom:.8px solid #2b1424;height:8px}
.warn{font-size:4.9pt;line-height:1.3;text-align:justify;margin-top:auto}
`;
const page = (body, pageCss) => `<!doctype html><html><head><meta charset="utf-8"><style>${css}${pageCss}</style></head><body>${body}</body></html>`;
const frontDiv = `<div class="label">${front}</div>`, backDiv = `<div class="label">${back}</div>`;

(async () => {
  fs.mkdirSync('print', { recursive: true });
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ deviceScaleFactor: 300 / 96, viewport: { width: 336, height: 432 } });
  const p = await ctx.newPage();
  const ready = async html => { await p.setContent(html, { waitUntil: 'networkidle' }); await p.evaluate(() => document.fonts.ready); };
  await ready(page(frontDiv, '')); await p.locator('.label').screenshot({ path: 'print/front-label-300dpi.png' });
  await ready(page(backDiv, ''));  await p.locator('.label').screenshot({ path: 'print/back-label-300dpi.png' });
  // SVG ids must be unique when both labels share one page; back uses its own ids so this is fine.
  await ready(page(frontDiv + backDiv, '@page{size:3.5in 4.5in;margin:0}'));
  await p.pdf({ path: 'print/cremas-labels-3.5x4.5in.pdf', width: '3.5in', height: '4.5in', printBackground: true });
  const cell = d => `<div style="outline:0.5px dashed #999">${d}</div>`;
  const sheet = `<div style="width:8.5in;height:11in;display:grid;grid-template-columns:3.5in 3.5in;grid-template-rows:4.5in 4.5in;gap:0.25in;justify-content:center;align-content:center">${cell(frontDiv)}${cell(backDiv)}${cell(frontDiv)}${cell(backDiv)}</div>`;
  await ready(page(sheet, '@page{size:letter;margin:0}'));
  await p.pdf({ path: 'print/cremas-print-sheet-letter.pdf', format: 'Letter', printBackground: true });
  await browser.close();
  console.log('done');
})();
