/**
 * Point d'entrée des envois de collecte (cf. COLLECTE_RECITATIONS.md).
 *
 * ── CE QUE CE WORKER NE FAIT PAS, ET C'EST VOULU ─────────────────────────
 *
 * Il ne déchiffre rien. Il ne peut pas : les paquets sont scellés pour une clé
 * privée qui ne vit que sur la machine d'entraînement. Ce code voit passer des
 * octets opaques, et c'est exactement ce qu'on veut — une faille ici
 * n'exposerait aucune récitation.
 *
 * ── LE PLAN PRÉVOYAIT DES URL SIGNÉES : ON FAIT PLUS SIMPLE ──────────────
 *
 * L'idée initiale était que le Worker délivre une URL S3 signée que
 * l'application utiliserait ensuite. C'était la solution du monde S3, où il
 * faut bien qu'une clé existe quelque part. Ici le Worker a un BINDING R2
 * natif (`env.DEPOT`) : il écrit dans le bucket sans qu'aucune clé d'accès
 * n'existe, ni dans l'APK, ni dans ce code, ni dans une variable
 * d'environnement. Un aller-retour de moins, et une clé de moins à protéger.
 *
 * Les paquets pèsent ~500 Ko, très loin de la limite de taille de requête d'un
 * Worker : l'écriture directe est sans risque de ce côté.
 */

const MAGIQUE = [0x43, 0x4b, 0x52, 0x31]; // "CKR1"
const TAILLE_MIN = 64;                    // en-tête + tag, sans contenu
const TAILLE_MAX = 8 * 1024 * 1024;       // 8 Mo : large pour ~500 Ko attendus

/** Identifiant d'appareil : aléatoire, tiré localement, jamais un vrai ID. */
const ID_APPAREIL = /^[a-f0-9]{32}$/;

function refus(code, raison) {
  // Le corps reste volontairement laconique : rien d'exploitable pour sonder
  // le service, mais le code HTTP suffit à l'application pour décider entre
  // réessayer plus tard et abandonner ce paquet.
  return new Response(JSON.stringify({ erreur: raison }), {
    status: code,
    headers: { 'content-type': 'application/json' },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname === '/sante') {
      // Sert au diagnostic depuis un poste : dit que le Worker répond et que
      // le bucket est bien lié, sans rien révéler de son contenu.
      return new Response(
        JSON.stringify({ ok: true, depot: Boolean(env.DEPOT) }),
        { headers: { 'content-type': 'application/json' } },
      );
    }

    // ── INVENTAIRE, POUR LE RAPATRIEMENT (2026-09-19) ────────────────────
    //
    // `wrangler` sait lire et ecrire un objet, mais pas LISTER un bucket. Sans
    // cette route, PC A ne pourrait pas savoir ce qu'il reste a telecharger --
    // il faudrait gerer des cles d'acces S3, c'est-a-dire reintroduire
    // exactement le secret que le binding R2 permet d'eviter.
    //
    // Protegee par un secret pose avec `wrangler secret put CLE_INVENTAIRE` :
    // il n'est jamais dans le code ni dans le depot. La comparaison est
    // volontairement stricte et l'absence de secret REFUSE l'acces -- un
    // Worker deploye sans secret ne doit pas ouvrir son inventaire a tous.
    if (request.method === 'GET' && url.pathname === '/inventaire') {
      const fourni = request.headers.get('x-cle') || '';
      if (!env.CLE_INVENTAIRE || fourni !== env.CLE_INVENTAIRE) {
        return refus(403, 'acces refuse');
      }
      const liste = await env.DEPOT.list({
        limit: Number(url.searchParams.get('limite') || 1000),
        cursor: url.searchParams.get('curseur') || undefined,
        prefix: url.searchParams.get('prefixe') || undefined,
      });
      return new Response(
        JSON.stringify({
          objets: liste.objects.map((o) => ({
            cle: o.key,
            taille: o.size,
            depose: o.uploaded,
          })),
          // `truncated` dit qu'il reste des objets : sans reprise par curseur,
          // un rapatriement s'arreterait au millieme sans rien signaler.
          suite: liste.truncated ? liste.cursor : null,
        }),
        { headers: { 'content-type': 'application/json' } },
      );
    }

    // Recuperation d'un objet, meme secret. Evite d'avoir a passer par
    // `wrangler r2 object get`, dont l'option `--remote` est facile a oublier
    // (sans elle il interroge un stockage LOCAL simule et repond « key does
    // not exist » sur un objet pourtant bien present -- piege paye le
    // 2026-09-19).
    if (request.method === 'GET' && url.pathname.startsWith('/objet/')) {
      const fourni = request.headers.get('x-cle') || '';
      if (!env.CLE_INVENTAIRE || fourni !== env.CLE_INVENTAIRE) {
        return refus(403, 'acces refuse');
      }
      const cle = decodeURIComponent(url.pathname.slice('/objet/'.length));
      const objet = await env.DEPOT.get(cle);
      if (!objet) return refus(404, 'objet inconnu');
      return new Response(objet.body, {
        headers: { 'content-type': 'application/octet-stream' },
      });
    }

    if (request.method !== 'POST' || url.pathname !== '/envoi') {
      return refus(404, 'route inconnue');
    }
    if (!env.DEPOT) return refus(500, 'depot non lie');

    const appareil = request.headers.get('x-appareil') || '';
    if (!ID_APPAREIL.test(appareil)) return refus(400, 'appareil invalide');

    const taille = Number(request.headers.get('content-length') || 0);
    if (taille > TAILLE_MAX) return refus(413, 'paquet trop gros');

    const paquet = new Uint8Array(await request.arrayBuffer());
    if (paquet.length < TAILLE_MIN || paquet.length > TAILLE_MAX) {
      return refus(413, 'taille hors bornes');
    }
    // Le magique ne prouve pas que le paquet est valide -- seule la clé privée
    // le dira -- mais il écarte d'emblée ce qui n'a pas été produit par
    // l'application, et évite de stocker du bruit.
    for (let i = 0; i < MAGIQUE.length; i++) {
      if (paquet[i] !== MAGIQUE[i]) return refus(400, 'format inconnu');
    }

    // Une clé par appareil et par instant : deux envois ne s'écrasent jamais,
    // et le préfixe permet de retrouver — ou d'effacer — tout ce qu'un
    // appareil a envoyé, ce qu'exige une demande de suppression.
    const cle = `${appareil}/${Date.now()}-${crypto.randomUUID()}.bin`;
    await env.DEPOT.put(cle, paquet, {
      httpMetadata: { contentType: 'application/octet-stream' },
      customMetadata: {
        recuLe: new Date().toISOString(),
        // `cf.country` sert à savoir d'où vient le corpus, jamais à
        // identifier quelqu'un : c'est un pays, pas une position.
        pays: request.cf?.country ?? 'inconnu',
      },
    });

    return new Response(JSON.stringify({ ok: true, cle }), {
      status: 201,
      headers: { 'content-type': 'application/json' },
    });
  },
};
