"""为《地牢冒险记》补充场景与操作音频。

复用 generate_audio.py 的 Buf、波形和导出逻辑，保持所有素材可确定性重生成。
"""
from generate_audio import Buf, LOOP_FOLD, SR_BGM, SR_SFX, env_ad, env_ar, note, w_saw, w_tri, write_wav
import math
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")


def sfx_card_draw() -> Buf:
    b = Buf(0.16, SR_SFX, 2)
    b.noise(0.12, 0.34, mode="band", cutoff=lambda t: 1200.0 + 1400.0 * t,
            q=0.9, pan=-0.15, seed=701, env=lambda t: env_ad(t, 0.035, 0.001))
    b.tone(1040.0, 0.24, 0.09, tau=0.03, attack=0.001, pan=0.12)
    b.tone(1560.0, 0.13, 0.06, start=0.035, tau=0.02, attack=0.001, pan=0.2)
    b.normalize(0.70)
    b.declick(0.001, 0.012)
    return b


def sfx_card_play() -> Buf:
    b = Buf(0.28, SR_SFX, 2)
    b.thump(180.0, 72.0, 0.20, 0.42, sweep=0.06, tau=0.07, pan=-0.08)
    b.tone(note(60), 0.22, 0.18, tau=0.07, attack=0.002, pan=0.12)
    b.tone(note(72), 0.18, 0.13, start=0.05, tau=0.05, attack=0.002, pan=-0.12)
    b.noise(0.08, 0.22, mode="high", cutoff=3800.0, q=1.2, seed=702,
            env=lambda t: env_ad(t, 0.022, 0.001))
    b.normalize(0.76)
    b.declick(0.001, 0.018)
    return b


def sfx_map_step() -> Buf:
    b = Buf(0.20, SR_SFX, 2)
    b.thump(120.0, 58.0, 0.14, 0.27, sweep=0.04, tau=0.045, pan=-0.15)
    b.tone(720.0, 0.16, 0.11, tau=0.035, attack=0.001, pan=0.16)
    b.normalize(0.62)
    b.declick(0.001, 0.015)
    return b


def sfx_reward() -> Buf:
    b = Buf(0.72, SR_SFX, 2)
    for i, midi in enumerate([76, 81, 84, 88]):
        t = i * 0.105
        b.tone(note(midi), 0.30, 0.33, start=t, attack=0.003, tau=0.12,
               pan=-0.24 + i * 0.16)
        b.tone(note(midi + 12), 0.07, 0.22, start=t + 0.02, attack=0.003,
               tau=0.08, pan=0.18 - i * 0.08)
    b.noise(0.30, 0.12, mode="high", cutoff=5200.0, q=1.2, start=0.25,
            seed=703, env=lambda t: env_ad(t, 0.09, 0.002))
    b.normalize(0.78)
    b.declick(0.002, 0.035)
    return b


def bgm_town() -> Buf:
    dur = 24.0
    b = Buf(dur + LOOP_FOLD, SR_BGM, 2)
    chords = [[62, 65, 69], [57, 60, 64], [59, 62, 66], [55, 59, 62]]
    roots = [50, 45, 47, 43]
    for i, chord in enumerate(chords):
        start = i * 6.0
        for j, midi in enumerate(chord):
            b.tone(note(midi), 0.16, 5.7, start=start, attack=0.8,
                   pan=-0.24 + 0.24 * j,
                   env=lambda t: env_ar(t, 5.7, 0.9, 1.0))
        b.tone(note(roots[i]), 0.30, 5.4, start=start, attack=0.25,
               env=lambda t: env_ar(t, 5.4, 0.35, 0.65))
    melody = [(0.0, 74), (1.0, 76), (2.0, 77), (3.5, 76),
              (6.0, 72), (7.0, 74), (8.5, 76), (10.0, 74),
              (12.0, 69), (13.0, 72), (14.0, 74), (16.0, 72),
              (18.0, 71), (19.0, 69), (20.5, 67), (22.0, 69)]
    for start, midi in melody:
        b.tone(note(midi), 0.24, 0.65, start=start, wave=w_tri,
               attack=0.008, tau=0.22, pan=-0.14)
        b.tone(note(midi + 12), 0.055, 0.42, start=start + 0.02,
               wave=w_tri, attack=0.008, tau=0.14, pan=0.18)
    for i in range(8):
        b.tone(note(roots[i % 4] + 12), 0.12, 0.16, start=i * 3.0,
               wave=w_tri, attack=0.002, tau=0.06, pan=0.20)
    b.normalize(0.58)
    b.fold_loop(dur)
    return b


def bgm_dungeon() -> Buf:
    dur = 20.0
    beat = 0.5
    b = Buf(dur + LOOP_FOLD, SR_BGM, 2)
    roots = [45, 45, 41, 43, 45, 45, 41, 43, 45, 48]
    for bar, root in enumerate(roots):
        start = bar * 2.0
        b.tone(note(root), 0.34, 1.8, start=start, attack=0.06,
               env=lambda t: env_ar(t, 1.8, 0.08, 0.20))
        for j, interval in enumerate([0, 3, 7]):
            b.tone(note(root + 12 + interval), 0.075, 0.35,
                   start=start + j * beat, wave=w_tri, attack=0.004,
                   tau=0.10, pan=-0.22 + j * 0.22)
        b.thump(82.0, 42.0, 0.25, 0.22, start=start, sweep=0.07, tau=0.12)
    b.noise(dur + LOOP_FOLD, 0.022, mode="low", cutoff=260.0, q=1.0, seed=704)
    b.tone(note(69), 0.12, 3.4, start=4.0, attack=0.6, tau=1.1,
           env=lambda t: env_ar(t, 3.4, 0.7, 0.8), pan=0.18)
    b.normalize(0.54)
    b.fold_loop(dur)
    return b


BUILDERS = {
    "sfx_card_draw": sfx_card_draw,
    "sfx_card_play": sfx_card_play,
    "sfx_map_step": sfx_map_step,
    "sfx_reward": sfx_reward,
    "bgm_town": bgm_town,
    "bgm_dungeon": bgm_dungeon,
}


if __name__ == "__main__":
    for name, builder in BUILDERS.items():
        info = write_wav(os.path.join(OUT, name + ".wav"), builder())
        print(name, info)
