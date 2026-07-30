package com.corankarim.coran_karim.recitation2

/**
 * INVARIANT n°1 DU CONTRAT v2 — UNE SEULE HORLOGE.
 *
 * Tout objet de cette chaine porte des indices d'echantillon ABSOLUS depuis le
 * debut de session. Aucune couche ne manipule un offset relatif a un buffer.
 *
 * Pourquoi c'est un invariant et pas une convention de style : dans la chaine
 * v1, deux defauts couteux venaient exactement de la : la fenetre de secours
 * tombait 3 s avant le mot (l'origine absolue etait calculee depuis le debut du
 * buffer alors que les logprobs etaient tronques du contexte de chevauchement),
 * et le portier RMS creait une seconde echelle de temps invisible
 * ([PIEGE] "le flux brut et le flux de travail n'ont PAS la meme echelle de
 * temps" — a deja fausse un banc entier). Ici la conversion entre les deux
 * horloges est un objet explicite ([Correspondance]), jamais une soustraction
 * faite au vol dans une couche.
 *
 * Grille temporelle du modele causal v1 (contrat verrouille cote
 * StreamingModelConfig, a ne pas re-deriver) : window_stride 10 ms,
 * sous-echantillonnage 8 => une frame de sortie CTC vaut 80 ms.
 * Contexte d'attention [70, 13] => 13 frames de sortie de lookahead,
 * soit 1,04 s d'audio POSTERIEUR necessaire pour qu'une frame soit vue dans
 * les conditions d'entrainement. C'est ce chiffre qui fixe la marge droite
 * d'interiorite (cf. AligneurForce).
 */
object Horloge {
    const val TAUX = 16_000

    /** hop du mel (10 ms). */
    const val ECH_PAR_FRAME_MEL = 160

    /** sous-echantillonnage de l'encodeur FastConformer. */
    const val SOUS_ECHANTILLONNAGE = 8

    /** une frame de logprobs = 80 ms = 1280 echantillons. */
    const val ECH_PAR_FRAME = ECH_PAR_FRAME_MEL * SOUS_ECHANTILLONNAGE

    const val MS_PAR_FRAME = 80

    /** att_context_size[1] du causal v1 : 13 frames de sortie = 1,04 s. */
    const val LOOKAHEAD_FRAMES = 13

    fun secondesVersEch(s: Double): Int = (s * TAUX).toInt()

    fun echVersSecondes(n: Long): Double = n.toDouble() / TAUX

    fun frameVersEch(f: Int): Long = f.toLong() * ECH_PAR_FRAME

    fun echVersFrame(n: Long): Int = (n / ECH_PAR_FRAME).toInt()

    fun framesPourEch(n: Int): Int = n / ECH_PAR_FRAME
}
