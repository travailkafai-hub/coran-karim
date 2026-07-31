"""Les confusions de recitation, et leur rendement MESURE. Source unique.

Ce module ne depend de rien : il est importe aussi bien par les generateurs
(venv TTS) que par les bancs (venv NeMo). La table vivait dans
`generate_phrases_concat.py`, qui charge XTTS a l'import -- inutilisable depuis
un banc. La dupliquer aurait garanti qu'elle diverge : c'est une table de
MESURES, pas une constante de gout.

RENDEMENT = part des clips ou la faute S'ENTEND reellement, mesuree sur mot
isole par rapport de vraisemblance CTC (controle du 2026-07-31, 18 195 clips du
corpus `tts_augmentation`).

⚠️ Ce rendement vaut pour un MOT ISOLE. En synthese de PHRASE entiere, XTTS
corrige le texte qu'on lui donne exactement comme l'ASR : 29 % a 2-3 mots, 10 %
a 3-6 mots. C'est ce qui a impose l'assemblage mot a mot.
"""

# Vraies confusions de recitation : meme point d'articulation, l'emphase seule
# change. Ce sont celles qu'on cherche a detecter, et XTTS les rend tres bien
# tant qu'il n'a pas de contexte a corriger.
CONFUSABLES = [
    ("ط", "ت"),   # 99 %
    ("ت", "ط"),   # 99 %
    ("ض", "د"),   # 99 %
    ("د", "ض"),   # 99 %
    ("ق", "ك"),   # 98 %
    ("ك", "ق"),   # 98 %
    ("ص", "س"),   # 98 %
    ("ه", "ح"),   # 97 %
    ("ح", "ه"),   # 97 %
    ("ء", "ع"),   # 97 %
    ("ذ", "ز"),   # 97 %
    ("س", "ص"),   # 96 %
    ("ع", "ء"),   # 95 %
    # Famille jim/ha/kha : ABSENTE du corpus d'origine, signalee par
    # l'utilisateur apres son propre test (« mon cas c'etait remplacer jim par
    # ha »). Rendement inconnu -- c'est le controle qui tranchera.
    ("ج", "ح"), ("ح", "خ"), ("ج", "خ"),
]

# NE PAS SUPPRIMER : seule substitution du corpus d'origine que XTTS ne rend
# jamais en phrase (0/4), alors que ز->ذ passe a 97 % sur mot isole. Exclue de
# la GENERATION tant que ce n'est pas explique -- mais elle reste une confusion
# legitime, donc elle demeure dans la table pour les BANCS.
EXCLUES_GENERATION = {"ز->ذ"}

FATHA, DAMMA, KASRA, SUKUN = "َ", "ُ", "ِ", "ْ"
SHORT_HARAKAT = [FATHA, DAMMA, KASRA, SUKUN]


def variantes(mot):
    """Toutes les confusions plausibles de ce mot -- une lettre, ou une harakat.

    Sert au banc des regles de gop : comparer le mot attendu a sa meilleure
    confusion REELLE, plutot qu'a un decodage libre qui est un max sur tout le
    lexique et donc une borne tres lache.
    """
    out = []
    for a, b in CONFUSABLES:
        for src, dst in ((a, b), (b, a)):
            j = mot.find(src)
            if j >= 0:
                out.append(mot[:j] + dst + mot[j + 1:])
    for k, c in enumerate(mot):
        if c in SHORT_HARAKAT:
            for h in SHORT_HARAKAT:
                if h != c:
                    out.append(mot[:k] + h + mot[k + 1:])
    return list(dict.fromkeys(out))
