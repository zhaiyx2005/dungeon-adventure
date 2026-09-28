# -*- coding: utf-8 -*-
"""地牢冒险记 —— 程序化音频生成器

把全部音效与 BGM 用**纯 Python**（无第三方依赖）合成出来，写进 assets/audio/。
之所以不用素材文件：项目当前全部美术都是程序绘制的占位色块，音频同样保持
"可确定性重跑、不依赖外部素材"的路线；改参数重跑即可，不需要美术交付。

音色构成：
  * 加法合成（多个正弦/三角/锯齿谐波）
  * 噪声音色（白噪 + 状态变量滤波器 SVF，取 low/band/high 输出）
  * 包络（指数衰减 / ADSR / 音头音尾防爆音淡入淡出）
  * 简易立体声（声场 pan + 轻微失谐 detune）
  * BGM 用「多轨叠加 + 反馈延迟 + 循环折叠（crossfade fold）」做出无缝循环

用法：
    python tools/generate_audio.py
    python tools/generate_audio.py --only sfx        # 只生成音效
    python tools/generate_audio.py --only bgm        # 只生成音乐
"""

from __future__ import annotations

import argparse
import array
import math
import os
import random
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio")

SR_SFX = 44100          # 音效采样率（短，可以高一点，保证"脆"）
SR_BGM = 22050          # 音乐采样率（长，用 22050 控制体积）
TAU = 2.0 * math.pi

# BGM 循环折叠长度（秒）：把尾巴混回开头，实现无缝循环
LOOP_FOLD = 0.35


# ---------------------------------------------------------------------------
# 波形（相位参数统一为 0..1 的循环相位）
# ---------------------------------------------------------------------------

def w_sin(p: float) -> float:
    return math.sin(TAU * p)


def w_tri(p: float) -> float:
    return 4.0 * abs(p - 0.5) - 1.0


def w_sqr(p: float) -> float:
    return 1.0 if p < 0.5 else -1.0


def w_saw(p: float) -> float:
    return 2.0 * p - 1.0


def note(midi: float) -> float:
    """MIDI 音高 → 频率（A4 = 69 = 440Hz）"""
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


# ---------------------------------------------------------------------------
# 包络
# ---------------------------------------------------------------------------

def env_ad(t: float, tau: float, attack: float = 0.004) -> float:
    """音头 attack + 指数衰减（打击类最常用）"""
    if t < attack:
        return (t / attack) if attack > 0.0 else 1.0
    return math.exp(-(t - attack) / tau)


def env_ar(t: float, dur: float, attack: float, release: float) -> float:
    """线性起音 + 线性释放的梯形包络（持续音用）"""
    if t < attack:
        return t / attack if attack > 0.0 else 1.0
    if t > dur - release:
        left = dur - t
        return max(0.0, left / release) if release > 0.0 else 0.0
    return 1.0


def env_arch(t: float, dur: float) -> float:
    """两头低中间高的拱形包络（破空 / whoosh 用）"""
    if dur <= 0.0:
        return 0.0
    x = t / dur
    if x < 0.0 or x > 1.0:
        return 0.0
    return math.sin(math.pi * x) ** 1.4


# ---------------------------------------------------------------------------
# 缓冲区：立体声浮点缓冲 + 叠加式合成
# ---------------------------------------------------------------------------

class Buf:
    def __init__(self, seconds: float, sr: int, channels: int = 2):
        self.sr = sr
        self.channels = channels
        self.n = int(round(seconds * sr))
        self.a = [0.0] * self.n
        self.b = [0.0] * self.n if channels == 2 else None

    # -- 单音（可给频率/振幅传函数做滑音或任意包络）--
    def tone(self, freq, amp, dur, start: float = 0.0, wave=w_sin,
             attack: float = 0.004, tau: float | None = None,
             detune: float = 0.0, pan: float = 0.0, phase: float = 0.0,
             env=None) -> None:
        sr = self.sr
        i0 = int(round(start * sr))
        n = int(round(dur * sr))
        if n <= 0 or i0 >= self.n:
            return
        gl, gr = 0.5 * (1.0 - pan), 0.5 * (1.0 + pan)
        ph = phase
        ph2 = phase
        ratio = 1.0 + detune
        two_osc = abs(detune) > 1e-9
        for i in range(n):
            idx = i0 + i
            if idx >= self.n:
                break
            t = i / sr
            f = freq(t) if callable(freq) else freq
            a = amp(t) if callable(amp) else amp
            if env is not None:
                a *= env(t)
            elif tau is not None:
                a *= env_ad(t, tau, attack)
            elif attack > 0.0 and t < attack:
                a *= t / attack
            if a > 1e-7:
                v = wave(ph)
                if two_osc:
                    v = 0.5 * (v + wave(ph2))
                v *= a
                self.a[idx] += v * gl
                if self.b is not None:
                    self.b[idx] += v * gr
            step = f / sr
            ph += step
            if ph >= 1.0:
                ph -= math.floor(ph)
            if two_osc:
                ph2 += step * ratio
                if ph2 >= 1.0:
                    ph2 -= math.floor(ph2)

    # -- 噪声（经状态变量滤波器整形）--
    #
    # 用 Zavalishin 的 TPT（trapezoidal）SVF，而不是经典的 Chamberlin SVF：
    # Chamberlin 在 f=2*sin(pi*fc/sr) 接近 2（即截止频率接近奈奎斯特）时会发散，
    # 一旦发散就产生 inf，归一化时 inf*0 → NaN，最后写 PCM 直接抛
    # "cannot convert float NaN to integer"。TPT 形式对任意 g>0 都稳定。
    #
    # 系数只在截止频率变化超过 2% 时重算（切频扫频很平滑，省掉大量 tan/除法）。
    def noise(self, dur, amp, start: float = 0.0, mode: str = "band",
              cutoff=1200.0, q: float = 1.0, pan: float = 0.0,
              seed: int = 1, env=None) -> None:
        sr = self.sr
        i0 = int(round(start * sr))
        n = int(round(dur * sr))
        if n <= 0 or i0 >= self.n:
            return
        rng = random.Random(seed)
        gl, gr = 0.5 * (1.0 - pan), 0.5 * (1.0 + pan)
        k = max(q, 0.05)                # 调用方传的是阻尼系数（越小越共鸣）
        ic1 = ic2 = 0.0
        a1 = a2 = a3 = 0.0
        last_fc = -1.0
        for i in range(n):
            idx = i0 + i
            if idx >= self.n:
                break
            t = i / sr
            fc = cutoff(t) if callable(cutoff) else cutoff
            fc = min(max(fc, 20.0), sr * 0.45)
            if last_fc < 0.0 or abs(fc - last_fc) > 0.02 * last_fc:
                g = math.tan(math.pi * fc / sr)
                a1 = 1.0 / (1.0 + g * (g + k))
                a2 = g * a1
                a3 = g * a2
                last_fc = fc
            x = rng.uniform(-1.0, 1.0) - rng.uniform(-1.0, 1.0)
            v3 = x - ic2
            v1 = a1 * ic1 + a2 * v3
            v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2.0 * v1 - ic1
            ic2 = 2.0 * v2 - ic2
            if mode == "low":
                y = v2
            elif mode == "high":
                y = x - k * v1 - v2
            else:
                y = v1
            a = amp(t) if callable(amp) else amp
            if env is not None:
                a *= env(t)
            if a > 1e-7:
                y *= a
                self.a[idx] += y * gl
                if self.b is not None:
                    self.b[idx] += y * gr

    # -- 一阶低通（把锯齿磨圆，做"弦乐/铜管"感）--
    def tone_lp(self, freq, amp, dur, start: float = 0.0, wave=w_saw,
                cutoff: float = 1800.0, attack: float = 0.01,
                tau: float | None = None, detune: float = 0.0,
                pan: float = 0.0, env=None) -> None:
        sr = self.sr
        i0 = int(round(start * sr))
        n = int(round(dur * sr))
        if n <= 0 or i0 >= self.n:
            return
        gl, gr = 0.5 * (1.0 - pan), 0.5 * (1.0 + pan)
        ph = ph2 = 0.0
        z = z2 = 0.0
        ratio = 1.0 + detune
        two_osc = abs(detune) > 1e-9
        k = 1.0 - math.exp(-TAU * cutoff / sr)
        for i in range(n):
            idx = i0 + i
            if idx >= self.n:
                break
            t = i / sr
            f = freq(t) if callable(freq) else freq
            a = amp(t) if callable(amp) else amp
            if env is not None:
                a *= env(t)
            elif tau is not None:
                a *= env_ad(t, tau, attack)
            elif attack > 0.0 and t < attack:
                a *= t / attack
            v = wave(ph)
            z += k * (v - z)
            y = z
            if two_osc:
                v2 = wave(ph2)
                z2 += k * (v2 - z2)
                y = 0.5 * (y + z2)
            if a > 1e-7:
                self.a[idx] += y * a * gl
                if self.b is not None:
                    self.b[idx] += y * a * gr
            step = f / sr
            ph += step
            if ph >= 1.0:
                ph -= math.floor(ph)
            if two_osc:
                ph2 += step * ratio
                if ph2 >= 1.0:
                    ph2 -= math.floor(ph2)

    # -- 打击类：音高下坠的正弦（底鼓 / 闷响）--
    def thump(self, f0: float, f1: float, dur: float, amp: float,
              start: float = 0.0, sweep: float = 0.08, tau: float = 0.09,
              pan: float = 0.0) -> None:
        def fr(t: float) -> float:
            if t >= sweep:
                return f1
            x = t / sweep
            return f0 + (f1 - f0) * (x * x)

        self.tone(fr, amp, dur, start=start, tau=tau, attack=0.002, pan=pan)

    # -- 叠加另一条缓冲（可带增益、偏移、环绕回开头）--
    def mix_in(self, other: "Buf", gain: float = 1.0, offset: float = 0.0,
               wrap: bool = False) -> None:
        off = int(round(offset * self.sr))
        for i in range(other.n):
            j = (i + off) % self.n if wrap else i + off
            if j >= self.n:
                break
            self.a[j] += other.a[i] * gain
            if self.b is not None and other.b is not None:
                self.b[j] += other.b[i] * gain

    # -- 反馈延迟（简单多抽头）--
    def delay(self, src: "Buf", taps: int, step: float, fb: float,
              wet: float) -> None:
        g = wet
        for k in range(1, taps + 1):
            self.mix_in(src, gain=g, offset=step * k, wrap=True)
            g *= fb

    # -- 归一化到目标峰值 --
    def normalize(self, peak: float) -> float:
        m = self._sanitize()
        if m < 1e-9:
            return 0.0
        k = peak / m
        for i in range(self.n):
            self.a[i] *= k
        if self.b is not None:
            for i in range(self.n):
                self.b[i] *= k
        return k

    # -- 兜底清扫 NaN / inf，并返回原始峰值 --
    # 滤波器一旦发散就是 inf，再乘 0 会变 NaN；这里把非有限值直接置 0，
    # 免得一路流到 write_wav 抛 "cannot convert float NaN to integer"。
    def _sanitize(self) -> float:
        m = 0.0
        bad = 0
        aa = self.a
        for i in range(self.n):
            v = aa[i]
            if v != v or v == float("inf") or v == float("-inf"):
                aa[i] = 0.0
                bad += 1
            elif abs(v) > m:
                m = abs(v)
        if self.b is not None:
            bb = self.b
            for i in range(self.n):
                v = bb[i]
                if v != v or v == float("inf") or v == float("-inf"):
                    bb[i] = 0.0
                    bad += 1
                elif abs(v) > m:
                    m = abs(v)
        if bad:
            print("  [warn] 清扫了 %d 个非有限采样（滤波器发散？）" % bad)
        return m

    # -- 音头音尾防爆音 --
    def declick(self, fin: float = 0.003, fout: float = 0.01) -> None:
        ni = min(self.n, int(round(fin * self.sr)))
        no = min(self.n, int(round(fout * self.sr)))
        for i in range(ni):
            g = i / max(1, ni)
            self.a[i] *= g
            if self.b is not None:
                self.b[i] *= g
        for i in range(no):
            g = i / max(1, no)
            j = self.n - 1 - i
            self.a[j] *= g
            if self.b is not None:
                self.b[j] *= g

    # -- 循环折叠：把尾部 [L, L+FOLD] 淡入混回开头，得到无缝循环 --
    def fold_loop(self, loop_seconds: float) -> None:
        L = int(round(loop_seconds * self.sr))
        F = int(round(LOOP_FOLD * self.sr))
        if L <= 0 or L + F > self.n:
            return
        for i in range(F):
            g = i / F                      # 开头权重渐增
            head = self.a[i] * g + self.a[L + i] * (1.0 - g)
            self.a[i] = head
            if self.b is not None:
                hb = self.b[i] * g + self.b[L + i] * (1.0 - g)
                self.b[i] = hb
        del self.a[L:]
        if self.b is not None:
            del self.b[L:]
        self.n = L

    # -- 输出 --
    def frames(self):
        if self.b is None:
            return [self.a]
        return [self.a, self.b]


def write_wav(path: str, buf: Buf) -> dict:
    chans = buf.frames()
    nch = len(chans)
    n = buf.n
    pcm = array.array("h", bytes(2 * n * nch))
    peak = 0.0
    sq = 0.0
    for i in range(n):
        for c in range(nch):
            v = chans[c][i]
            if v > 1.0:
                v = 1.0
            elif v < -1.0:
                v = -1.0
            if abs(v) > peak:
                peak = abs(v)
            sq += v * v
            pcm[i * nch + c] = int(v * 32767.0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(nch)
        w.setsampwidth(2)
        w.setframerate(buf.sr)
        w.writeframes(pcm.tobytes())
    rms = math.sqrt(sq / max(1, n * nch))
    return {
        "path": os.path.basename(path),
        "sec": n / buf.sr,
        "ch": nch,
        "sr": buf.sr,
        "peak": peak,
        "rms": rms,
        "kb": os.path.getsize(path) / 1024.0,
    }


# ===========================================================================
# 音效
# ===========================================================================

def sfx_ui_click() -> Buf:
    b = Buf(0.085, SR_SFX, 1)
    # 木头/按键的"嗒"：两个快速衰减的高频正弦 + 极短噪声音头
    b.tone(1500.0, 0.85, 0.060, tau=0.014, attack=0.001)
    b.tone(2350.0, 0.42, 0.045, tau=0.008, attack=0.001)
    b.tone(760.0, 0.30, 0.070, tau=0.022, attack=0.001)
    b.noise(0.008, 0.30, mode="high", cutoff=3000.0, q=1.4, seed=11)
    b.normalize(0.80)
    b.declick(0.001, 0.008)
    return b


def sfx_ui_confirm() -> Buf:
    b = Buf(0.30, SR_SFX, 1)
    # 上行两音（C6 → G6），柔和的三角波
    b.tone(note(84), 0.55, 0.13, tau=0.045, attack=0.003)
    b.tone(note(84) * 2.0, 0.16, 0.11, start=0.0, tau=0.030, attack=0.003)
    b.tone(note(91), 0.55, 0.20, start=0.085, tau=0.055, attack=0.003)
    b.tone(note(91) * 2.0, 0.16, 0.16, start=0.085, tau=0.038, attack=0.003)
    b.normalize(0.80)
    b.declick(0.002, 0.02)
    return b


def sfx_ui_deny() -> Buf:
    b = Buf(0.30, SR_SFX, 1)
    # 下行两音 + 轻微方波毛刺，表示"不行"
    b.tone_lp(note(67), 0.55, 0.12, tau=0.040, cutoff=1400.0, attack=0.002)
    b.tone_lp(note(60), 0.60, 0.20, start=0.080, tau=0.060, cutoff=1100.0, attack=0.002)
    b.noise(0.05, 0.10, start=0.005, mode="band", cutoff=900.0, q=0.9, seed=13)
    b.normalize(0.78)
    b.declick(0.002, 0.02)
    return b


def sfx_atk_slash() -> Buf:
    """物理攻击起手：破空声（带通噪声扫频）+ 末尾一记短促的挥击收尾"""
    b = Buf(0.34, SR_SFX, 2)

    def band(t: float) -> float:
        # 300 → 2600Hz 快扫，再回落，模拟"唰"
        x = t / 0.34
        if x < 0.55:
            return 300.0 + (2600.0 - 300.0) * (x / 0.55) ** 1.7
        y = (x - 0.55) / 0.45
        return 2600.0 - (2600.0 - 700.0) * y

    b.noise(0.34, 0.95, mode="band", cutoff=band, q=0.75, pan=-0.25,
            seed=21, env=lambda t: env_arch(t, 0.34))
    b.noise(0.34, 0.30, mode="high", cutoff=4200.0, q=1.1, pan=0.30,
            seed=22, env=lambda t: env_arch(t, 0.34) * 0.6)
    # 破空的同时有一点点低频"风压"
    b.tone(180.0, 0.18, 0.30, tau=0.075, attack=0.03, pan=-0.1)
    b.normalize(0.88)
    b.declick(0.002, 0.02)
    return b


def sfx_atk_cast() -> Buf:
    """法术起手：咏唱上滑 + 泛音微光 + 收尾铃声"""
    b = Buf(0.52, SR_SFX, 2)

    def sweep(t: float) -> float:
        x = min(1.0, t / 0.40)
        return 190.0 + (900.0 - 190.0) * (x ** 1.35)

    b.tone(sweep, 0.50, 0.46, attack=0.06, pan=-0.12,
           env=lambda t: env_ar(t, 0.46, 0.09, 0.14))
    b.tone(lambda t: sweep(t) * 2.0, 0.17, 0.42, attack=0.10, pan=0.15,
           env=lambda t: env_ar(t, 0.42, 0.14, 0.16))
    b.tone(lambda t: sweep(t) * 3.01, 0.09, 0.38, attack=0.14, pan=0.0,
           env=lambda t: env_ar(t, 0.38, 0.16, 0.14))
    # 咏唱的气声
    b.noise(0.44, 0.16, mode="band", cutoff=lambda t: 900.0 + 1400.0 * t,
            q=1.2, seed=31, env=lambda t: env_arch(t, 0.44))
    # 收尾的一记水晶铃
    b.tone(1320.0, 0.34, 0.20, start=0.30, tau=0.070, attack=0.003)
    b.tone(1980.0, 0.17, 0.16, start=0.30, tau=0.052, attack=0.003)
    b.normalize(0.88)
    b.declick(0.002, 0.02)
    return b


def sfx_hit_phys() -> Buf:
    """物理受击：闷响（音高下坠）+ 中频爆点 + 一点低频冲击"""
    b = Buf(0.30, SR_SFX, 2)
    b.thump(150.0, 52.0, 0.26, 0.95, sweep=0.07, tau=0.085, pan=-0.15)
    b.noise(0.13, 0.55, mode="low", cutoff=900.0, q=0.9, pan=0.12, seed=41,
            env=lambda t: env_ad(t, 0.045, 0.001))
    b.tone(300.0, 0.30, 0.09, tau=0.028, attack=0.001, pan=0.0)
    b.noise(0.05, 0.22, mode="high", cutoff=2600.0, q=1.3, pan=0.2, seed=42,
            env=lambda t: env_ad(t, 0.016, 0.001))
    b.normalize(0.92)
    b.declick(0.001, 0.02)
    return b


def sfx_hit_magic() -> Buf:
    """法术受击：高频噼啪 + 下坠能量 + 低频"包"的一下"""
    b = Buf(0.34, SR_SFX, 2)

    def band(t: float) -> float:
        x = min(1.0, t / 0.30)
        return 5200.0 - (5200.0 - 900.0) * (x ** 1.2)

    b.noise(0.30, 0.80, mode="band", cutoff=band, q=0.6, pan=0.18, seed=51,
            env=lambda t: env_ad(t, 0.055, 0.001))
    b.noise(0.06, 0.55, mode="high", cutoff=6500.0, q=1.5, pan=-0.2, seed=52,
            env=lambda t: env_ad(t, 0.018, 0.001))
    b.tone(lambda t: 780.0 - 460.0 * min(1.0, t / 0.26), 0.32, 0.30,
           attack=0.002, tau=0.075, pan=-0.1)
    b.thump(120.0, 55.0, 0.22, 0.42, sweep=0.05, tau=0.06, pan=0.0)
    b.normalize(0.92)
    b.declick(0.001, 0.02)
    return b


def sfx_crit() -> Buf:
    """暴击叠加层：金属重击（非谐泛音）+ 更亮的爆点"""
    b = Buf(0.46, SR_SFX, 2)
    base = 190.0
    for i, r in enumerate([1.0, 1.83, 2.71, 3.62, 4.51]):
        amp = 0.55 * (0.72 ** i)
        b.tone(base * r, amp, 0.42 - i * 0.03, tau=0.16 - i * 0.02,
               attack=0.001, pan=(-0.25 + 0.12 * i))
    b.thump(230.0, 70.0, 0.30, 0.75, sweep=0.06, tau=0.10)
    b.noise(0.10, 0.55, mode="high", cutoff=5200.0, q=1.0, seed=61,
            env=lambda t: env_ad(t, 0.028, 0.001))
    b.tone(1760.0, 0.24, 0.22, start=0.005, tau=0.085, attack=0.001)
    b.normalize(0.95)
    b.declick(0.001, 0.02)
    return b


def sfx_shield() -> Buf:
    """防御 / 护盾生成：金属共鸣 + 上扬的"罩子合拢"声 + 低频托底"""
    b = Buf(0.55, SR_SFX, 2)
    for i, f in enumerate([520.0, 782.0, 1170.0, 1563.0, 2085.0]):
        b.tone(f, 0.42 * (0.78 ** i), 0.50 - i * 0.045,
               tau=0.20 - i * 0.022, attack=0.004, pan=(-0.3 + 0.15 * i))
    # 合拢的向上扫频
    b.noise(0.42, 0.42, mode="band",
            cutoff=lambda t: 220.0 + 1700.0 * min(1.0, t / 0.38) ** 1.5,
            q=0.8, seed=71, env=lambda t: env_ar(t, 0.42, 0.10, 0.18))
    b.tone(110.0, 0.32, 0.42, attack=0.06, tau=0.16)
    b.normalize(0.88)
    b.declick(0.002, 0.025)
    return b


def sfx_heal() -> Buf:
    """治疗：柔和上行三音（C E G）+ 温暖泛音"""
    b = Buf(0.66, SR_SFX, 2)
    for i, m in enumerate([72, 76, 79]):
        t0 = i * 0.14
        b.tone(note(m), 0.50, 0.42, start=t0, attack=0.05,
               pan=(-0.22 + 0.22 * i),
               env=lambda t: env_ar(t, 0.42, 0.06, 0.20))
        b.tone(note(m + 12), 0.13, 0.34, start=t0, attack=0.07, pan=0.0,
               env=lambda t: env_ar(t, 0.34, 0.09, 0.18))
    b.tone(note(84), 0.20, 0.34, start=0.30, tau=0.13, attack=0.006)
    b.normalize(0.82)
    b.declick(0.003, 0.03)
    return b


def sfx_mana() -> Buf:
    """回蓝：水晶叮（两个纯五度高频）"""
    b = Buf(0.36, SR_SFX, 2)
    b.tone(1568.0, 0.50, 0.30, tau=0.10, attack=0.002, pan=-0.16)
    b.tone(2349.0, 0.28, 0.26, tau=0.075, attack=0.002, pan=0.16)
    b.tone(3136.0, 0.12, 0.20, tau=0.050, attack=0.002, pan=0.0)
    b.noise(0.18, 0.14, mode="band",
            cutoff=lambda t: 1800.0 + 3600.0 * t, q=1.1, seed=81,
            env=lambda t: env_ad(t, 0.05, 0.002))
    b.normalize(0.80)
    b.declick(0.002, 0.02)
    return b


def sfx_combo() -> Buf:
    """联合卡发动：华丽上行琶音 + 泛音微光 + 收尾重击"""
    b = Buf(1.05, SR_SFX, 2)
    arp = [72, 76, 79, 84, 86, 88]          # C E G C E G（上行）
    for i, m in enumerate(arp):
        t0 = i * 0.072
        pan = -0.45 + 0.18 * i
        b.tone(note(m), 0.42, 0.55 - i * 0.02, start=t0, attack=0.004,
               tau=0.22 - i * 0.015, pan=pan)
        b.tone(note(m) * 2.0, 0.13, 0.40, start=t0, attack=0.004,
               tau=0.13, pan=-pan * 0.6)
    # 上扬的魔法气流
    b.noise(0.55, 0.30, mode="band",
            cutoff=lambda t: 500.0 + 4200.0 * min(1.0, t / 0.5) ** 1.4,
            q=0.85, seed=91, env=lambda t: env_arch(t, 0.55))
    # 收尾：一记明亮的金属重音
    for i, f in enumerate([880.0, 1320.0, 1760.0, 2640.0]):
        b.tone(f, 0.30 * (0.75 ** i), 0.50 - i * 0.05, start=0.42,
               tau=0.19 - i * 0.02, attack=0.003, pan=(-0.2 + 0.13 * i))
    b.thump(160.0, 62.0, 0.42, 0.55, start=0.42, sweep=0.07, tau=0.13)
    b.normalize(0.94)
    b.declick(0.002, 0.03)
    return b


def sfx_victory() -> Buf:
    """胜利：小号式上行（C E G C），最后一音带颤音拖长"""
    b = Buf(1.30, SR_SFX, 2)
    ms = [72, 76, 79, 84]
    for i, m in enumerate(ms):
        t0 = i * 0.16
        last = i == len(ms) - 1
        dur = 0.70 if last else 0.30
        amp = 0.52
        if last:
            def fr(t, m=m):
                return note(m) * (1.0 + 0.006 * math.sin(TAU * 6.0 * t))
            b.tone_lp(fr, amp, dur, start=t0, wave=w_sqr, cutoff=2400.0,
                      attack=0.015, pan=0.0,
                      env=lambda t, d=dur: env_ar(t, d, 0.03, 0.30))
        else:
            b.tone_lp(note(m), amp, dur, start=t0, wave=w_sqr, cutoff=2300.0,
                      attack=0.012, pan=0.0,
                      env=lambda t, d=dur: env_ar(t, d, 0.025, 0.12))
        b.tone_lp(note(m + 12), 0.14, dur * 0.9, start=t0, wave=w_sqr,
                  cutoff=3200.0, attack=0.015, pan=0.12,
                  env=lambda t, d=dur: env_ar(t, d, 0.03, 0.14))
    b.tone(note(48), 0.30, 0.60, start=0.48, attack=0.02, tau=0.28)
    b.normalize(0.90)
    b.declick(0.004, 0.04)
    return b


def sfx_defeat() -> Buf:
    """失败：下行低音（A F D A↓），缓慢、暗"""
    b = Buf(1.60, SR_SFX, 2)
    ms = [69, 65, 62, 45]
    for i, m in enumerate(ms):
        t0 = i * 0.30
        last = i == len(ms) - 1
        dur = 0.95 if last else 0.46
        b.tone_lp(note(m), 0.50, dur, start=t0, wave=w_saw,
                  cutoff=700.0 - i * 90.0, attack=0.04, pan=(-0.12 + 0.09 * i),
                  env=lambda t, d=dur: env_ar(t, d, 0.06, 0.30))
        b.tone(note(m) / 2.0, 0.24, dur, start=t0, attack=0.05,
               pan=0.0, env=lambda t, d=dur: env_ar(t, d, 0.08, 0.32))
    b.noise(1.0, 0.10, mode="low", cutoff=420.0, q=0.9, start=0.4, seed=101,
            env=lambda t: env_ar(t, 1.0, 0.2, 0.5))
    b.normalize(0.86)
    b.declick(0.006, 0.06)
    return b


SFX_BUILDERS = {
    "sfx_ui_click": sfx_ui_click,
    "sfx_ui_confirm": sfx_ui_confirm,
    "sfx_ui_deny": sfx_ui_deny,
    "sfx_atk_slash": sfx_atk_slash,
    "sfx_atk_cast": sfx_atk_cast,
    "sfx_hit_phys": sfx_hit_phys,
    "sfx_hit_magic": sfx_hit_magic,
    "sfx_crit": sfx_crit,
    "sfx_shield": sfx_shield,
    "sfx_heal": sfx_heal,
    "sfx_mana": sfx_mana,
    "sfx_combo": sfx_combo,
    "sfx_victory": sfx_victory,
    "sfx_defeat": sfx_defeat,
}


# ===========================================================================
# BGM
# ===========================================================================

BAR_TITLE = 3.0            # 80 BPM，4/4 → 每小节 3 秒
BARS_TITLE = 8             # 8 小节 = 24 秒
TITLE_CHORDS = [           # (根音 MIDI 低八度, 三和弦 MIDI)
    (38, [50, 53, 57]),    # Dm : D3 F3 A3
    (34, [46, 50, 53]),    # Bb : Bb2 D3 F3
    (41, [53, 57, 60]),    # F  : F3 A3 C4
    (36, [48, 52, 55]),    # C  : C3 E3 G3
]
TITLE_BASS = [38.0, 34.0, 41.0, 36.0]
# 旋律：(起始秒, MIDI, 时长)  —— D 小调五声（D F G A C）
TITLE_MELODY = [
    (0.00, 74, 1.10), (1.50, 69, 0.90),
    (3.00, 72, 1.10), (4.50, 74, 1.80),
    (6.00, 77, 1.10), (7.50, 74, 0.90),
    (9.00, 72, 2.40),
    (12.00, 69, 1.10), (13.50, 74, 1.10),
    (15.00, 77, 2.20),
    (18.00, 67, 1.10), (19.50, 69, 1.10),
    (21.00, 72, 2.40),
]


def bgm_title() -> Buf:
    """开屏 / 城镇主题：舒缓的弦垫 + 五声拨弦旋律 + 远处太鼓 + 反馈延迟"""
    dur = BAR_TITLE * BARS_TITLE
    b = Buf(dur + LOOP_FOLD, SR_BGM, 2)

    # ---- 弦垫（每个和弦持续 2 小节 = 6 秒，轻微失谐做合唱感）----
    for ci, (_, triad) in enumerate(TITLE_CHORDS):
        t0 = ci * 2 * BAR_TITLE
        cdur = 2 * BAR_TITLE
        for vi, m in enumerate(triad):
            f = note(m)
            pan = (-0.35 + 0.35 * vi)
            b.tone(f, 0.20, cdur, start=t0, detune=0.0035, pan=pan,
                   attack=0.9,
                   env=lambda t, d=cdur: env_ar(t, d, 1.1, 1.1))
            b.tone(f * 2.0, 0.045, cdur, start=t0, detune=-0.002, pan=-pan * 0.5,
                   attack=0.9,
                   env=lambda t, d=cdur: env_ar(t, d, 1.3, 1.0))

    # ---- 低音（每和弦一个全音符，最后一小节折成两半增加动感）----
    for ci, root in enumerate(TITLE_BASS):
        t0 = ci * 2 * BAR_TITLE
        b.tone(note(root), 0.42, 2 * BAR_TITLE, start=t0, attack=0.25,
               env=lambda t, d=2 * BAR_TITLE: env_ar(t, d, 0.35, 0.5))
        b.tone(note(root) * 2.0, 0.11, 2 * BAR_TITLE, start=t0, attack=0.3,
               env=lambda t, d=2 * BAR_TITLE: env_ar(t, d, 0.40, 0.5))

    # ---- 拨弦旋律（三角波 + 八度叠层，走延迟）----
    mel = Buf(dur + LOOP_FOLD, SR_BGM, 2)
    for t0, m, ln in TITLE_MELODY:
        mel.tone(note(m), 0.34, ln, start=t0, wave=w_tri, attack=0.006,
                 tau=ln * 0.55, pan=-0.18)
        mel.tone(note(m + 12), 0.10, ln * 0.7, start=t0, wave=w_tri,
                 attack=0.006, tau=ln * 0.35, pan=0.22)
        mel.tone(note(m - 12), 0.12, ln, start=t0, wave=w_tri, attack=0.010,
                 tau=ln * 0.6, pan=0.0)
    b.mix_in(mel)
    b.delay(mel, taps=3, step=0.75, fb=0.30, wet=0.22)

    # ---- 远处太鼓：每小节第一拍 ----
    for bar in range(BARS_TITLE):
        t0 = bar * BAR_TITLE
        b.thump(96.0, 44.0, 0.55, 0.34, start=t0, sweep=0.09, tau=0.16)
        b.noise(0.16, 0.09, mode="low", cutoff=520.0, q=0.9, start=t0,
                seed=200 + bar, env=lambda t: env_ad(t, 0.05, 0.002))

    # ---- 极低电平的气流 ----
    b.noise(dur + LOOP_FOLD, 0.030, mode="band",
            cutoff=lambda t: 700.0 + 300.0 * math.sin(TAU * t / 9.0),
            q=1.6, seed=210)

    # ---- 整体呼吸感（两个周期都是 dur 的整数分频 → 循环安全）----
    # 没有这一层的话，24 秒弦垫会一路平推，听起来像"风机"而不是音乐。
    # 周期 24s 的乐句起伏 + 周期 6s 的轻微呼吸，两者都满足 env(0) == env(dur)，
    # 折叠成循环后不会在接缝处跳变。
    for i in range(b.n):
        t = i / b.sr
        g = 0.84 + 0.16 * math.sin(TAU * t / dur - math.pi * 0.5) \
            + 0.05 * math.sin(TAU * t / (dur / 4.0))
        b.a[i] *= g
        if b.b is not None:
            b.b[i] *= g

    b.normalize(0.62)
    b.fold_loop(dur)
    return b


BPM_BATTLE = 120.0
BEAT = 60.0 / BPM_BATTLE          # 0.5 秒
BAR = BEAT * 4                    # 2 秒
BARS_BATTLE = 10                  # 10 小节 = 20 秒
BATTLE_ROOTS = [38, 38, 34, 34, 41, 41, 36, 36, 38, 38]   # D D Bb Bb F F C C D D
BATTLE_STABS = [                  # 每小节的起手和弦（三和弦）
    [50, 53, 57], [50, 53, 57], [46, 50, 53], [46, 50, 53],
    [53, 57, 60], [53, 57, 60], [48, 52, 55], [48, 52, 55],
    [50, 53, 57], [50, 53, 57],
]
BATTLE_LEAD = [
    (4.00, 74, 0.40), (4.50, 72, 0.40), (5.00, 70, 0.85),
    (6.00, 69, 0.40), (6.50, 70, 0.40), (7.00, 72, 0.85),
    (10.00, 74, 0.40), (10.50, 72, 0.40), (11.00, 70, 0.85),
    (12.00, 77, 0.40), (12.50, 74, 0.40), (13.00, 72, 0.85),
    (15.50, 69, 0.40), (16.00, 70, 0.40), (16.50, 74, 1.60),
]


def bgm_battle() -> Buf:
    """战斗主题：驱动型底鼓/军鼓 + 八分音符低音 + 和弦顿奏 + 紧张的铜管动机"""
    dur = BAR * BARS_BATTLE
    b = Buf(dur + LOOP_FOLD, SR_BGM, 2)

    # ---- 鼓组 ----
    for bar in range(BARS_BATTLE):
        t0 = bar * BAR
        for k in (0.0, 2.0):
            b.thump(140.0, 48.0, 0.30, 0.62, start=t0 + k * BEAT,
                    sweep=0.05, tau=0.10)
        b.thump(130.0, 46.0, 0.22, 0.34, start=t0 + 3.5 * BEAT,
                sweep=0.04, tau=0.075)
        for k in (1.0, 3.0):
            b.noise(0.19, 0.36, mode="band", cutoff=2100.0, q=0.55,
                    start=t0 + k * BEAT, seed=300 + bar * 2 + int(k),
                    env=lambda t: env_ad(t, 0.045, 0.001))
            b.noise(0.06, 0.20, mode="high", cutoff=5200.0, q=1.4,
                    start=t0 + k * BEAT, seed=310 + bar * 2 + int(k),
                    env=lambda t: env_ad(t, 0.015, 0.001))
            b.thump(220.0, 170.0, 0.10, 0.16, start=t0 + k * BEAT,
                    sweep=0.03, tau=0.035)
        for i in range(8):
            tt = t0 + i * BEAT * 0.5
            amp = 0.13 if i % 2 == 0 else 0.075
            if i == 7:
                amp = 0.16
            b.noise(0.075 if i < 7 else 0.16, amp, mode="high",
                    cutoff=7200.0, q=1.6, start=tt, seed=320 + bar * 8 + i,
                    env=lambda t: env_ad(t, 0.020, 0.001))

    # ---- 八分音符低音ostinato ----
    for bar in range(BARS_BATTLE):
        root = BATTLE_ROOTS[bar]
        t0 = bar * BAR
        for i in range(8):
            m = root if i % 4 != 3 else root + 7
            acc = 0.40 if i % 2 == 0 else 0.28
            b.tone_lp(note(m), acc, 0.20, start=t0 + i * BEAT * 0.5,
                      wave=w_saw, cutoff=900.0, attack=0.004,
                      pan=(-0.10 if i % 2 == 0 else 0.10),
                      env=lambda t: env_ad(t, 0.070, 0.004))
        b.tone(note(root - 12), 0.26, 0.44, start=t0, attack=0.006,
               env=lambda t: env_ad(t, 0.16, 0.006))

    # ---- 和弦顿奏（切分）----
    for bar in range(BARS_BATTLE):
        t0 = bar * BAR
        for off in (0.75, 1.5, 2.75):
            for vi, m in enumerate(BATTLE_STABS[bar]):
                b.tone_lp(note(m), 0.11, 0.15, start=t0 + off * BEAT,
                          wave=w_saw, cutoff=2000.0, attack=0.006,
                          detune=0.004, pan=(-0.3 + 0.3 * vi),
                          env=lambda t: env_ad(t, 0.045, 0.006))

    # ---- 铜管动机 ----
    for t0, m, ln in BATTLE_LEAD:
        b.tone_lp(note(m), 0.26, ln, start=t0, wave=w_saw,
                  cutoff=2600.0, attack=0.02, detune=0.005, pan=-0.12,
                  env=lambda t, d=ln: env_ar(t, d, 0.03, min(0.3, d * 0.45)))
        b.tone_lp(note(m - 12), 0.10, ln, start=t0, wave=w_tri,
                  cutoff=1200.0, attack=0.03, pan=0.15,
                  env=lambda t, d=ln: env_ar(t, d, 0.04, min(0.3, d * 0.45)))

    b.normalize(0.60)
    b.fold_loop(dur)
    return b


BGM_BUILDERS = {
    "bgm_title": bgm_title,
    "bgm_battle": bgm_battle,
}


# ===========================================================================

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["sfx", "bgm"], default=None)
    args = ap.parse_args()

    rows = []
    if args.only in (None, "sfx"):
        for name, fn in SFX_BUILDERS.items():
            info = write_wav(os.path.join(OUT_DIR, name + ".wav"), fn())
            info["kind"] = "sfx"
            rows.append(info)
    if args.only in (None, "bgm"):
        for name, fn in BGM_BUILDERS.items():
            info = write_wav(os.path.join(OUT_DIR, name + ".wav"), fn())
            info["kind"] = "bgm"
            rows.append(info)

    print("%-20s %-4s %6s %5s %7s %7s %8s" %
          ("file", "kind", "sec", "ch", "sr", "peak", "kb"))
    print("-" * 66)
    for r in rows:
        print("%-20s %-4s %6.2f %5d %7d %7.3f %8.1f" %
              (r["path"], r["kind"], r["sec"], r["ch"], r["sr"],
               r["peak"], r["kb"]))
    print("-" * 66)
    print("共 %d 个文件，写入 %s" % (len(rows), OUT_DIR))
    bad = [r["path"] for r in rows if r["peak"] < 0.2 or r["rms"] < 0.01]
    if bad:
        print("!! 电平异常（几乎无声）：%s" % ", ".join(bad))
        return 1
    if any(r["peak"] > 0.999 for r in rows):
        print("!! 存在削波风险")
        return 1
    print("电平自检通过（无静音、无削波）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
