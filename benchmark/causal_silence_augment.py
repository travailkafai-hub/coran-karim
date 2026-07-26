"""Augmentation par insertion de silences INTERNES, pour l'entrainement causal.

POURQUOI (mesure du 2026-07-26, `simulate_sliding_window.py --n 30`) : dans le
regime segmente de l'app, le modele causal est a PARITE avec l'offline sur
recitation fluide (30,9 % contre 30,1 % de WER) mais nettement DERRIERE sur
recitation hesitante -- 79,4 % contre 66,2 %, soit +13 pt.

Cause identifiee : le corpus d'entrainement est fait d'enregistrements de
studio, UN VERSET PAR FICHIER (`data/train_wav_local/<Reciteur>/<s>_<a>.wav`),
donc de la recitation continue SANS aucune pause interne. Le modele causal n'a
jamais vu d'audio entrecoupe de silences. L'offline non plus, mais lui voit le
segment entier des deux cotes ; le causal a un contexte gauche borne
(att_context_size[0]=70 frames ~ 5,6 s) et ZERO contexte droit -- un reciteur
qui s'arrete 2 s lui remplit ce contexte de silence et il decroche.

C'est precisement le cas d'usage mis en priorite par l'utilisateur le
2026-07-25 (recitation adulte/enfant, debutant qui s'arrete), donc l'ecart
compte plus que celui mesure sur clips propres.

── POURQUOI C'EST SUR POUR DU CTC ──
Le silence n'ajoute AUCUN token : la transcription de reference est
rigoureusement inchangee. C'est ce qui distingue cette augmentation d'un
decoupage ou d'un recouvrement (qui, eux, obligent a retoucher le texte et ont
tous echoue -- cf. FONCTIONNALITES_FUTURES.md §4). CTC absorbe le silence en
blank.

── DEUX CHOIX DE CONCEPTION, TOUS DEUX MESURES AILLEURS ──
1. Les pauses sont posees sur de VRAIS creux d'energie, pas a des offsets
   tires au hasard. Une coupure au milieu d'un phoneme apprendrait au modele a
   traverser une discontinuite acoustique qui n'existe pas dans la realite ;
   un reciteur s'arrete ENTRE deux mots. Meme raisonnement que la recherche de
   micro-silence de `BufferedTranscriber.findCutOffset` (mesure : a 20 ms de
   resolution il y a assez d'inter-mots pour decouper mot par mot).
2. `prob` < 1 : une partie des clips reste CONTINUE. La performance fluide est
   deja a parite -- l'augmenter a 100 % risquerait de l'echanger contre le gain
   sur l'hesitant au lieu de l'ajouter. On ne remplace pas un regime par
   l'autre, on couvre les deux.
"""
import numpy as np

from nemo.collections.asr.parts.preprocessing.perturb import (
    Perturbation, register_perturbation)


class InternalSilencePerturbation(Perturbation):
    """Insere [min_pauses..max_pauses] silences dans l'audio, sur les creux
    d'energie les plus francs, pour simuler une recitation hesitante.

    Contrairement a `SilencePerturbation` de NeMo (qui n'ajoute qu'aux DEUX
    EXTREMITES), les pauses sont posees A L'INTERIEUR : c'est la seule forme
    qui reproduit un reciteur qui s'arrete au milieu d'un passage, et donc la
    seule qui adresse l'ecart mesure sur le regime hesitant.
    """

    def __init__(
        self,
        min_pause_secs: float = 0.5,
        max_pause_secs: float = 2.5,
        min_pauses: int = 1,
        max_pauses: int = 3,
        prob: float = 0.5,
        window_ms: int = 20,
        rng: int = None,
    ):
        self._min_pause = min_pause_secs
        self._max_pause = max_pause_secs
        self._min_pauses = min_pauses
        self._max_pauses = max_pauses
        self._prob = prob
        self._window_ms = window_ms
        self._rng = np.random.default_rng(rng)

    def _quietest_offsets(self, samples, sr, n):
        """Les [n] creux d'energie les mieux separes, hors bords.

        Fenetre de 20 ms comme `findCutOffset` cote Kotlin : a 80 ms les
        frontieres de mots sont invisibles (mesure du 2026-07-25 : 15 silences
        vus a 80 ms contre 38 a 20 ms sur le meme audio).
        """
        win = max(1, int(sr * self._window_ms / 1000))
        n_win = len(samples) // win
        if n_win < 8:
            return []
        frames = samples[: n_win * win].reshape(n_win, win)
        rms = np.sqrt((frames.astype(np.float64) ** 2).mean(axis=1))
        # Bords exclus : une pause collee au debut/fin est deja couverte par
        # SilencePerturbation et n'apprend rien sur la traversee d'une pause.
        margin = max(1, n_win // 10)
        order = np.argsort(rms[margin:n_win - margin]) + margin
        # Espacement minimal : deux pauses collees forment une seule longue
        # pause, ce qui ne diversifie rien.
        min_gap = max(1, n_win // (self._max_pauses + 2))
        picked = []
        for idx in order:
            if all(abs(idx - p) >= min_gap for p in picked):
                picked.append(int(idx))
            if len(picked) >= n:
                break
        return sorted(p * win for p in picked)

    def perturb(self, data):
        if self._rng.random() > self._prob:
            return
        sr = data.sample_rate
        n_pauses = int(self._rng.integers(self._min_pauses, self._max_pauses + 1))
        offsets = self._quietest_offsets(data._samples, sr, n_pauses)
        if not offsets:
            return
        pieces, prev = [], 0
        for off in offsets:
            pieces.append(data._samples[prev:off])
            secs = self._rng.uniform(self._min_pause, self._max_pause)
            pieces.append(np.zeros(int(secs * sr), dtype=data._samples.dtype))
            prev = off
        pieces.append(data._samples[prev:])
        data._samples = np.concatenate(pieces)


def register():
    """Idempotent : NeMo leve si un nom est deja enregistre, et ce module peut
    etre importe plusieurs fois (workers du DataLoader)."""
    from nemo.collections.asr.parts.preprocessing.perturb import perturbation_types
    if "internal_silence" not in perturbation_types:
        register_perturbation("internal_silence", InternalSilencePerturbation)
