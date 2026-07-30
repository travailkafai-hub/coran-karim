package com.corankarim.coran_karim.recitation2

/** Les trois couleurs de l'app : vert = correct, orange = douteux, rouge = faux. */
enum class Couleur { VERT, ORANGE, ROUGE }

/**
 * Statut d'un mot. `OMIS` n'est PAS une couleur : c'est "le recitateur est passe
 * outre, et on peut le prouver". Sans ce statut, un mot saute redevient
 * invisible — c'etait le vrai defaut de v22 (`305db63`), ou les mots enjambes
 * quittaient silencieusement le denominateur.
 */
sealed class Statut {
    object Inconnu : Statut()
    data class Provisoire(val couleur: Couleur) : Statut()
    data class Definitif(val couleur: Couleur) : Statut()
    object Omis : Statut()
}

/**
 * COUCHE G — DECISION.
 *
 * CONTRAT :
 *  - SEUL endroit du systeme ou vit un seuil. Aucune autre couche n'en connait ;
 *  - MONOTONIE : un verdict definitif ne change plus jamais. Un provisoire peut
 *    changer ;
 *  - une observation ne compte que si elle est INTERIEURE (couche E) ;
 *  - jamais de verdict sur absence de donnee, jamais de verdict par defaut.
 *
 * ── LA REGLE, ET CE QU'ELLE REMPLACE ───────────────────────────────────────
 *
 * PROVISOIRE des la 1re observation interieure ; DEFINITIF quand [k] = 2
 * observations interieures issues de fenetres DISTINCTES donnent la meme
 * couleur (stable-prefix rule).
 *
 * En v1 : `lock = p.isFinal || (judged == correct && !deferredTajwid)`. Un mot
 * juge correct sur un simple APERCU etait fige immediatement — consequence
 * mesuree : [PIEGE] verrou_sur_apercu, "la majorite des mots sont verrouilles
 * sur des apercus, donc sur un audio INCOMPLET". Ici il n'existe aucun chemin
 * qui verrouille sur une seule observation, ni sur une observation de bord.
 *
 * ── LE CALENDRIER, CHIFFRE (W = 6 s, hop = 1,5 s) ──────────────────────────
 * Soit `t` l'instant ou le mot finit d'etre prononce :
 *   + 1,04 s  contexte droit du modele causal
 *   + 0 a 1,5 s  attente de la prochaine fenetre de la grille
 *   + ~0,4 s  inference (mesure : 413 ms pour 5,7 s de buffer)
 *   = PROVISOIRE a t + 1,4 a 2,9 s
 *   + 1,5 s  seconde observation interieure
 *   = DEFINITIF a t + 2,9 a 4,4 s
 *
 * Ce delai est CONSTANT : il ne depend ni de la longueur d'un segment, ni du
 * rythme des pauses, ni de la duree deja recitee. C'est une propriete de
 * conception, pas une consequence a constater. Reference v1 mesuree dans le
 * log : `VALIDATION retard=10435ms` puis `8463ms`.
 */
class Decideur(
    private val seuilCorrect: Float = -0.45f,
    private val seuilDouteux: Float = -1.60f,
    private val k: Int = 2,
    private val motsPosterieursPourOmission: Int = 3,
    /** De combien de mots la recitation doit avoir depasse un mot avant qu'on
     *  accepte de le condamner. Ce n'est pas une tolerance sur le critere :
     *  c'est le refus de conclure tant que la preuve peut encore arriver. */
    private val depassement: Int = 3,
) {
    private val definitifs = HashMap<Int, Couleur>()
    private val omis = HashSet<Int>()

    /** @return statut courant de chaque mot ayant au moins une observation. */
    fun statuts(registre: RegistreDePreuves, nbMots: Int): Map<Int, Statut> {
        val out = HashMap<Int, Statut>()

        for (i in 0 until nbMots) {
            val dejaFige = definitifs[i]
            if (dejaFige != null) { out[i] = Statut.Definitif(dejaFige); continue }

            val votantes = registre.observationsVotantes(i)
            if (votantes.isEmpty()) continue

            val couleurs = votantes.map { couleur(it) }
            val fenetres = votantes.map { it.fenetreId }

            // ── DEUX MESURES INDEPENDANTES VALENT DEUX FENETRES ─────────────
            //
            // Le decodage libre ne connait pas le texte attendu ; l'alignement
            // force, si. Quand les deux disent la meme chose sur le meme audio
            // -- le libre a entendu CE mot a CET endroit, et le force lui donne
            // un bon score -- on tient deux preuves independantes, pas une.
            //
            // Ce n'est pas une tolerance ajoutee : c'est la reconnaissance
            // qu'exiger deux FENETRES etait une approximation de « exiger deux
            // preuves ». Mesure qui l'impose (2026-07-30) : les mots 170, 171,
            // 174, 205, 67 etaient lus PARFAITEMENT dans leur propre enonce
            // (gop 0,00, texte exact, atteste) puis degrades par le bloc de
            // FUSION qui les tronquait (« ٱلْبَرْ » pour « ٱلْبَرْقُ »). La 2e
            // fenetre apportait une preuve SYSTEMATIQUEMENT moins bonne, et
            // faisait perdre l'accord.
            val nette = votantes.lastOrNull()
            if (nette != null && nette.atteste && couleur(nette) == Couleur.VERT) {
                definitifs[i] = Couleur.VERT
                out[i] = Statut.Definitif(Couleur.VERT)
                continue
            }

            // k dernieres observations, de fenetres DISTINCTES, toutes d'accord.
            if (votantes.size >= k) {
                val dernieres = couleurs.takeLast(k)
                val idsDistincts = fenetres.takeLast(k).toSet().size == k
                if (idsDistincts && dernieres.all { it == dernieres.first() }) {
                    // ── UN NON-VERT NE SE FIGE QUE QUAND LE RECITATEUR EST
                    //    PASSE A LA SUITE ────────────────────────────────────
                    //
                    // La conception d'origine posait trois conditions au
                    // verrouillage ; la troisieme -- « au moins un mot
                    // posterieur a recu des frames » -- n'avait jamais ete
                    // implementee. Elle manquait, et ca se voit :
                    //     mot 171 f36 gop=-12,66  f37 gop=-18,34  -> ROUGE fige
                    //             f39 gop=  0,00 entendu="يَخْطَفُ"  (trop tard)
                    //     mot 172 f36 gop=-11,14  f37 gop=-14,18  -> ROUGE fige
                    //             f39 gop= -4,20 entendu correct
                    // Les deux premieres observations avaient `free` proche de
                    // 0 et `entendu` vide : signature de MAUVAISE POSITION, pas
                    // de mauvaise prononciation ([PIEGE] gop_vs_free). La
                    // monotonie figeait donc une erreur de position.
                    //
                    // Un VERT reste immediat : il est deja atteste deux fois, et
                    // faire attendre un mot juste degrade le temps reel pour
                    // rien. Un NON-VERT, lui, accuse quelqu'un : il attend que
                    // le mot ne puisse plus etre reobserve.
                    val couleurRetenue = dernieres.first()
                    val recitateurPasse = registre.indexMaxVotant() >= i + depassement
                    if (couleurRetenue == Couleur.VERT || recitateurPasse) {
                        definitifs[i] = couleurRetenue
                        out[i] = Statut.Definitif(couleurRetenue)
                        continue
                    }
                }
            }
            out[i] = Statut.Provisoire(couleurs.last())
        }

        // OMISSION : preuve POSITIVE que le recitateur est passe outre — au
        // moins N mots POSTERIEURS sont definitifs alors que celui-ci n'a jamais
        // recu d'observation votante. Ce n'est pas un verdict par absence de
        // donnee : c'est un constat sur des mots qui, eux, ont leur preuve.
        val definitifsTries = definitifs.keys.sorted()
        for (i in 0 until nbMots) {
            if (out[i] != null || omis.contains(i)) {
                if (omis.contains(i) && out[i] == null) out[i] = Statut.Omis
                continue
            }
            val posterieurs = definitifsTries.count { it > i }
            if (posterieurs >= motsPosterieursPourOmission) {
                omis.add(i)
                out[i] = Statut.Omis
            }
        }
        return out
    }

    fun couleur(o: RegistreDePreuves.Observation): Couleur = when {
        o.gop >= seuilCorrect -> Couleur.VERT
        o.gop >= seuilDouteux -> Couleur.ORANGE
        else -> Couleur.ROUGE
    }

    fun reinitialiser() {
        definitifs.clear()
        omis.clear()
    }
}
