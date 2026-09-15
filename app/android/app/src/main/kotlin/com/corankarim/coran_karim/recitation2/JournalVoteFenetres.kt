package com.corankarim.coran_karim.recitation2

import org.json.JSONArray
import org.json.JSONObject

/** Une ligne JSON PAR observation, y compris apres un verrouillage et sans
 * changement de statut. Ne pas reconstruire les votes depuis les couleurs.
 * schema/version identifient le code de mesure, l'APK reste a empreinter. */
object JournalVoteFenetres {
    private fun nombre(v: Number?): Any =
        if (v != null && v.toDouble().isFinite()) v else JSONObject.NULL

    fun observation(o: RegistreDePreuves.Observation, attendu: String?, tentative: Long): String {
        val lecture = o.lectureVote
        val mesure = lecture?.confiance
        val j = JSONObject().put("schema", 1).put("mode", "observation")
            .put("tentative", tentative).put("mot", o.motIndex).put("fenetre", o.fenetreId)
            .put("attendu", attendu ?: JSONObject.NULL).put("entendu", o.entendu)
            .put("debut", o.debutAbs).put("fin", o.finAbs)
            .put("fenetre_debut", nombre(lecture?.fenetreDebut))
            .put("fenetre_fin", nombre(lecture?.fenetreFin))
            .put("gop", nombre(o.gop)).put("forced", nombre(o.forced)).put("free", nombre(o.free))
            .put("frames", o.frames).put("interieur", o.interieur).put("couvert", o.couvert)
            .put("sans_creneau", o.sansCreneau).put("atteste", o.atteste)
            .put("marge_lettres", nombre(o.margeLettres)).put("marge_harakat", nombre(o.margeHarakat))
            .put("poids", nombre(mesure?.poids)).put("tokens_emis", nombre(mesure?.tokens))
            .put("pic_minimum", nombre(mesure?.minimum))
            .put("confiance_entropie", nombre(mesure?.confianceEntropie))
            .put("source_poids", ConfianceLectureCtc.SOURCE)
            .put("exclusion", lecture?.exclusion ?: JSONObject.NULL)
            .put("t3_etat", o.etatTete3).put("t3_logit", nombre(o.mesureTete3?.logit))
            .put("t3_jugement_logit", nombre(o.mesureTete3Jugement?.logit))
        return "[vote-observation] $j"
    }

    fun resultat(mot: Int, fenetre: Long, tentative: Long, r: VoteFenetres.Resultat): String {
        val candidats = JSONArray()
        for (c in r.candidats) candidats.put(JSONObject().put("texte", c.texte)
            .put("poids", c.poids).put("fenetres", JSONArray(c.fenetres)))
        return "[vote-resultat] " + JSONObject().put("schema", 1).put("mode", "observation")
            .put("mot", mot).put("fenetre", fenetre).put("tentative", tentative)
            .put("etat", r.etat).put("gagnant", r.gagnant ?: JSONObject.NULL)
            .put("candidats", candidats).put("exclusions", JSONObject(r.exclusions))
            .put("statut_app", JSONObject.NULL).toString()
    }

    /** La [politique] est journalisee telle qu'elle a REELLEMENT juge : deux
     *  riwayat ont deux fichiers de poids, et un log qui nommerait l'autre
     *  rendrait la trace inexploitable pour la calibration. */
    fun jugementTete3(mot: Int, tentative: Long, vote: VoteFenetres.Resultat,
                     avis: JugementTete3.Avis, couleurTexte: Couleur, statut: Statut,
                     preuve: RegistreDePreuves.Observation?,
                     politique: JugementTete3.Politique): String {
        val cs = JSONArray()
        for (c in avis.contributions) cs.put(JSONObject().put("fenetre", c.fenetre)
            .put("logit", c.logit).put("activation", c.activation).put("poids", c.poids))
        val couleur = when (statut) {
            is Statut.Definitif -> statut.couleur
            is Statut.Provisoire -> statut.couleur
            else -> null
        }
        return "[t3-jugement] " + JSONObject().put("schema", 1).put("mode", "decision")
            .put("politique", politique.version).put("modele_sha256", politique.sha256)
            .put("riwaya", politique.riwaya)
            .put("mot", mot).put("tentative", tentative).put("etat", avis.etat.name)
            .put("activation_moyenne", nombre(avis.activationMoyenne))
            .put("contributions", cs).put("vote_texte", vote.etat)
            .put("gagnant_texte", vote.gagnant ?: JSONObject.NULL)
            .put("couleur_texte", couleurTexte.name).put("couleur", couleur?.name ?: JSONObject.NULL)
            .put("definitif", statut is Statut.Definitif)
            .put("preuve_fenetre", preuve?.fenetreId ?: JSONObject.NULL).toString()
    }
}
