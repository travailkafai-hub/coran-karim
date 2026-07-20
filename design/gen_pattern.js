// Génère le motif de fond du défilement du Coran (mushaf_screen) en SVG pur,
// par construction géométrique -- même principe que gen_medallion.js : pas de
// tracé à la main, pas de copie d'une œuvre existante. Référence d'étude :
// pavage traditionnel octogones + carrés (4.8.8), le motif géométrique
// islamique le plus courant (sols/murs de mosquées) -- mais reconstruit ici
// aux formules exactes, pas tracé depuis une planche existante.
//
// Une seule tuile carrée (D x D), pensée pour être répétée côté Flutter par
// plusieurs SvgPicture juxtaposées (pas de <pattern> SVG interne : plus
// simple à faire correspondre à la taille d'écran réelle). Trait fin
// uniquement (pas de remplissage) + faible opacité côté app -- filigrane de
// papier, pas un graphisme qui capte l'attention (retour utilisateur sur la
// V1 du bandeau de sourate : "catastrophique... trop chargée").
const fs = require("fs");

const GOLD = "#c8a23c";

// Pavage 4.8.8 (octogones réguliers + carrés) : pour un octogone de côté `a`,
// le rayon circonscrit et l'espacement de grille centre-à-centre sont fixés
// par la géométrie du pavage (formules exactes, pas ajustées à l'oeil) :
//   R = a / (2 sin(22.5°))      -- rayon circonscrit de l'octogone
//   D = a (1 + √2)              -- espacement de la grille carrée
//   s = a√2                     -- "diamètre" (sommet à sommet) du carré-losange
// Vérifié numériquement : les sommets de l'octogone et du losange coïncident
// exactement (pavage sans jeu ni recouvrement).
const A = 34; // longueur de côté -- petit, pour un filigrane discret
const R = A / (2 * Math.sin(22.5 * Math.PI / 180));
const D = A * (1 + Math.SQRT2);
const S = A * Math.SQRT2;

function polar(cx, cy, r, deg) {
  const rad = (deg - 90) * Math.PI / 180;
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}

// Octogone régulier "à plat" (arêtes horizontales/verticales sur les 4 côtés
// cardinaux) -- sommets tous les 45°, décalés de 22.5° pour centrer une
// arête plate en haut.
function octagonPath(cx, cy, r) {
  let d = "";
  for (let i = 0; i < 8; i++) {
    const deg = 22.5 + i * 45;
    const [x, y] = polar(cx, cy, r, deg);
    d += (i === 0 ? "M" : "L") + x.toFixed(2) + "," + y.toFixed(2) + " ";
  }
  return d + "Z";
}

// Carré tourné à 45° (losange), sommets sur les 4 directions cardinales --
// comble le creux laissé entre 4 octogones voisins dans le pavage 4.8.8.
function diamondPath(cx, cy, halfDiag) {
  const top = polar(cx, cy, halfDiag, 0);
  const right = polar(cx, cy, halfDiag, 90);
  const bottom = polar(cx, cy, halfDiag, 180);
  const left = polar(cx, cy, halfDiag, 270);
  return `M ${top[0].toFixed(2)},${top[1].toFixed(2)} ` +
    `L ${right[0].toFixed(2)},${right[1].toFixed(2)} ` +
    `L ${bottom[0].toFixed(2)},${bottom[1].toFixed(2)} ` +
    `L ${left[0].toFixed(2)},${left[1].toFixed(2)} Z`;
}

// Un octogone identique posé à chacun des 4 coins de la tuile : en répétant
// la tuile bord à bord, les 4 copies partielles se superposent exactement
// (même sommet de grille) -- raccord garanti par construction, pas par
// ajustement visuel.
const corners = [[0, 0], [D, 0], [0, D], [D, D]];
const cornerOctagons = corners
  .map(([cx, cy]) => `<path d="${octagonPath(cx, cy, R)}" />`)
  .join("\n  ");

const centerDiamond = diamondPath(D / 2, D / 2, S / 2);

const svg = `<svg viewBox="0 0 ${D.toFixed(2)} ${D.toFixed(2)}" xmlns="http://www.w3.org/2000/svg">
  <g fill="none" stroke="${GOLD}" stroke-width="1" stroke-linejoin="round">
  ${cornerOctagons}
  <path d="${centerDiamond}" />
  </g>
</svg>
`;

// Écrit directement l'asset réel utilisé par l'app Flutter.
const outPath = __dirname + "/../app/assets/illumination/quran_pattern_tile.svg";
fs.writeFileSync(outPath, svg);
console.log("OK — " + outPath + " régénéré (tuile " + D.toFixed(1) + "×" + D.toFixed(1) + ")");
