package com.corankarim.coran_karim.recitation2

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import org.json.JSONObject

/** Entrees de la tete 3 conformes au SentencePiece d'entrainement.
 *
 * Cause mesuree le 15/09 : lookup/glouton de l'aligneur != BPE. Sur les memes
 * tenseurs T805/68, le logit etait +9.64 au lieu de -11.88. Les references
 * anterieures recevaient les ids Python et ne testaient pas cette etape.
 * Cette classe ne modifie ni l'aligneur, ni le texte compare par le vote.
 *
 * Contrat limite aux packs exportes par exporter_tokenizers_tete3.py : pieces
 * normales + unk, BPE sans dropout, prefixe espace, espaces conserves. Le trie
 * nmt_nfkc est celui du .model ; java.text.Normalizer n'est pas equivalent.
 * Formats consultes : google/sentencepiece src/{bpe_model,normalizer}.cc et
 * third_party/darts_clone/darts.h. Algorithme de fusion simple pour des mots
 * courts : meilleure paire, puis paire la plus a gauche en cas d'egalite.
 */
class TokeniseurBpeTete3 private constructor(
    val modeleSha256: String,
    private val pieces: List<String>, private val scores: FloatArray,
    normalisation: ByteArray,
) {
    private val ids = pieces.withIndex().filter { it.index != 0 }.associate { it.value to it.index }
    private val trie: IntArray
    private val remplacements: ByteArray

    init {
        val b = ByteBuffer.wrap(normalisation).order(ByteOrder.LITTLE_ENDIAN)
        val n = b.int
        require(n >= 1024 && n % 1024 == 0 && n + 4 < normalisation.size)
        trie = IntArray(n / 4) { b.int }
        remplacements = normalisation.copyOfRange(n + 4, normalisation.size)
        require(remplacements.last() == 0.toByte())
    }

    private fun offset(unite: Int) = (unite ushr 10) shl ((unite and 512) ushr 6)

    fun normaliser(texte: String): String {
        if (texte.isEmpty()) return ""
        val entree = texte.toByteArray(Charsets.UTF_8)
        val sortie = ByteArrayOutputStream(entree.size + 4)
        var debut = 0
        while (debut < entree.size) {
            var noeud = offset(trie[0])
            var longueur = 0
            var valeur = -1
            for (i in debut until entree.size) {
                val octet = entree[i].toInt() and 255
                val index = noeud xor octet
                if (index !in trie.indices) break
                val unite = trie[index]
                if ((unite and (Int.MIN_VALUE or 255)) != octet) break
                noeud = index xor offset(unite)
                if ((unite and 256) != 0) {
                    valeur = trie[noeud] and Int.MAX_VALUE
                    longueur = i - debut + 1
                }
            }
            if (longueur > 0) {
                var fin = valeur
                while (remplacements[fin] != 0.toByte()) fin++
                sortie.write(remplacements, valeur, fin - valeur)
                debut += longueur
            } else {
                // String -> UTF-8 produit des sequences valides.
                val premier = entree[debut].toInt() and 255
                val n = when { premier < 128 -> 1; premier < 224 -> 2; premier < 240 -> 3; else -> 4 }
                sortie.write(entree, debut, n)
                debut += n
            }
        }
        return "\u2581" + sortie.toString("UTF-8").replace(' ', '\u2581')
    }

    fun tokeniser(texte: String): IntArray {
        val normalise = normaliser(texte)
        val symboles = ArrayList<String>()
        var p = 0
        while (p < normalise.length) {
            val fin = p + Character.charCount(normalise.codePointAt(p))
            symboles.add(normalise.substring(p, fin)); p = fin
        }
        while (symboles.size > 1) {
            var meilleur = -1
            var score = Float.NEGATIVE_INFINITY
            for (i in 0 until symboles.size - 1) {
                val id = ids[symboles[i] + symboles[i + 1]] ?: continue
                if (scores[id] > score) { meilleur = i; score = scores[id] }
            }
            if (meilleur < 0) break
            symboles[meilleur] += symboles.removeAt(meilleur + 1)
        }
        val resultat = ArrayList<Int>()
        for (s in symboles) {
            val id = ids[s] ?: 0
            // SentencePiece regroupe les symboles inconnus consecutifs.
            if (id != 0 || resultat.lastOrNull() != 0) resultat.add(id)
        }
        return resultat.toIntArray()
    }

    companion object {
        fun charger(json: String, normalisation: ByteArray, vocabulaire: List<String>): TokeniseurBpeTete3 {
            val j = JSONObject(json)
            require(j.getString("format") == "sentencepiece_bpe_tete3_v1")
            val a = j.getJSONArray("pieces")
            val pieces = (0 until a.length()).map(a::getString)
            require(pieces == vocabulaire) { "Tokenizer tete3 incompatible avec le vocabulaire courant" }
            val sha = MessageDigest.getInstance("SHA-256").digest(normalisation)
                .joinToString("") { "%02x".format(it) }
            require(sha == j.getString("normalizer_sha256")) { "Normalisation tete3 incorrecte" }
            val s = j.getJSONArray("scores")
            require(s.length() == pieces.size)
            val scores = FloatArray(s.length()) { s.getDouble(it).toFloat() }
            require(scores.all { it.isFinite() })
            return TokeniseurBpeTete3(j.getString("model_sha256"), pieces, scores, normalisation)
        }
    }
}
