// Génère un médaillon d'enluminure (rosette dorée, symétrie radiale) en SVG pur,
// par construction géométrique — pas de tracé à la main, pas de copie d'une œuvre existante.
const fs = require("fs");

const GOLD = "#c8a23c";
const GOLD_DARK = "#8a6a1e";
const GOLD_LIGHT = "#e6cf8f";
const GREEN = "#114d39";
const GREEN_DARK = "#0c3b2c";
const CREAM = "#fbf7ee";

const CX = 100, CY = 100;

function polar(cx, cy, r, deg) {
  const rad = (deg - 90) * Math.PI / 180;
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}

// Anneau festonné (scalloped ring) : rayon modulé par une sinusoïde à N lobes.
function scallopRing(cx, cy, rBase, amp, lobes, steps = 360) {
  let d = "";
  for (let i = 0; i <= steps; i++) {
    const t = (i / steps) * 360;
    const r = rBase + amp * Math.cos(lobes * t * Math.PI / 180);
    const [x, y] = polar(cx, cy, r, t);
    d += (i === 0 ? "M" : "L") + x.toFixed(2) + "," + y.toFixed(2) + " ";
  }
  return d + "Z";
}

// Pétale (goutte) pointant vers l'extérieur, répété N fois par rotation.
function petalRing(cx, cy, rInner, rOuter, count, widthDeg) {
  let paths = [];
  for (let i = 0; i < count; i++) {
    const a = (360 / count) * i;
    const tip = polar(cx, cy, rOuter, a);
    const left = polar(cx, cy, rInner, a - widthDeg / 2);
    const right = polar(cx, cy, rInner, a + widthDeg / 2);
    const base = polar(cx, cy, rInner * 0.86, a);
    paths.push(
      `M ${base[0].toFixed(2)},${base[1].toFixed(2)} ` +
      `Q ${left[0].toFixed(2)},${left[1].toFixed(2)} ${tip[0].toFixed(2)},${tip[1].toFixed(2)} ` +
      `Q ${right[0].toFixed(2)},${right[1].toFixed(2)} ${base[0].toFixed(2)},${base[1].toFixed(2)} Z`
    );
  }
  return paths.join(" ");
}

// Petits points de séparation (perles) entre pétales.
function beadRing(cx, cy, r, count, radius) {
  let circles = "";
  for (let i = 0; i < count; i++) {
    const a = (360 / count) * i + (360 / count) / 2;
    const [x, y] = polar(cx, cy, r, a);
    circles += `<circle cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="${radius}" fill="${GOLD_DARK}" />\n`;
  }
  return circles;
}

const svg = `<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="goldGrad" cx="45%" cy="35%" r="75%">
      <stop offset="0%" stop-color="${GOLD_LIGHT}" />
      <stop offset="55%" stop-color="${GOLD}" />
      <stop offset="100%" stop-color="${GOLD_DARK}" />
    </radialGradient>
    <radialGradient id="greenGrad" cx="45%" cy="35%" r="75%">
      <stop offset="0%" stop-color="${GREEN}" />
      <stop offset="100%" stop-color="${GREEN_DARK}" />
    </radialGradient>
  </defs>

  <!-- anneau extérieur festonné (16 lobes) -->
  <path d="${scallopRing(CX, CY, 92, 6, 16)}" fill="url(#goldGrad)" stroke="${GOLD_DARK}" stroke-width="0.6" />

  <!-- anneau de perles -->
  ${beadRing(CX, CY, 78, 24, 1.6)}

  <!-- couronne de pétales pointant vers l'intérieur -->
  <path d="${petalRing(CX, CY, 74, 50, 16, 11)}" fill="${GOLD}" stroke="${GOLD_DARK}" stroke-width="0.5" />

  <!-- second rang de pétales, décalé, plus fin -->
  <path d="${petalRing(CX, CY, 58, 46, 16, 7)}" fill="${GOLD_LIGHT}" stroke="${GOLD_DARK}" stroke-width="0.4" opacity="0.9" />

  <!-- anneau fin séparant la couronne du médaillon central -->
  <circle cx="${CX}" cy="${CY}" r="48" fill="none" stroke="${GOLD_DARK}" stroke-width="1.2" />
  <circle cx="${CX}" cy="${CY}" r="45" fill="none" stroke="${GOLD_LIGHT}" stroke-width="0.6" />

  <!-- médaillon central : fond vert, réservé au texte (arabe) superposé par l'appli -->
  <circle cx="${CX}" cy="${CY}" r="44" fill="url(#greenGrad)" />
</svg>
`;

// Écrit directement l'asset réel utilisé par l'app Flutter.
const outPath = __dirname + "/../app/assets/illumination/medallion.svg";
fs.writeFileSync(outPath, svg);
console.log("OK — " + outPath + " régénéré");
