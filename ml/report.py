#!/usr/bin/env python3
"""Game analysis over the collected dataset.

Turns the raw /director stream (logged every ~10s during every game) into a
readable per-game report, so bot changes can be judged by numbers instead of
"felt smarter". Pure analysis of data already on disk — no game-side changes.

Per game:
  * duration, final kill gap, final networth gap (human team vs enemy team)
  * a verdict (STOMP for you / close / STOMP against you)
  * the adaptive director's difficulty trajectory (start -> end, # adjustments)
    -> fewer, smaller adjustments in close games = bots holding their own
  * an ASCII timeline of the human team's advantage through the game
  * total deaths per side (are the enemy bots actually killing the human team?)

Aggregate:
  * how many games ended balanced, avg length, avg difficulty adjustments
  * the roadmap-05 gate: balanced games with <=2 adjustments -> safe to cut
    another stat-bonus step.

Run:  python3 ml/report.py       (stdlib only; ML_DATA_DIR honored)
"""
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.environ.get("ML_DATA_DIR") or os.path.join(HERE, "data")
DATA_GLOB = os.path.join(DATA_DIR, "session-*.jsonl")

NW_KILL_EQUIV = 5000.0  # gold per "kill-equivalent" — matches the director
BALANCED_BAND = 12.0    # |advantage| below this at game end = a close game


def load():
    recs = []
    for path in sorted(glob.glob(DATA_GLOB)):
        with open(path) as f:
            for line in f:
                try:
                    recs.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return recs


def split_games(rows):
    """Split a client's chronological director rows into games on clock resets."""
    games, cur, last_t = [], [], None
    for r in rows:
        t = r["t"]
        if last_t is not None and t < last_t - 30:
            if cur:
                games.append(cur)
            cur = []
        cur.append(r)
        last_t = t
    if cur:
        games.append(cur)
    return games


def parse_director(recs):
    by_client = {}
    for rec in recs:
        if rec.get("endpoint") != "/director":
            continue
        req, resp = rec.get("request", {}), rec.get("response", {})
        heroes = req.get("heroes", {})
        side = {s: {"kills": 0, "deaths": 0, "nw": 0} for s in ("Radiant", "Dire")}
        human_side = None
        for s in ("Radiant", "Dire"):
            for h in heroes.get(s, []):
                kda = str(h.get("kda", "0/0/0")).split("/")
                side[s]["kills"] += int(kda[0]) if len(kda) > 0 else 0
                side[s]["deaths"] += int(kda[1]) if len(kda) > 1 else 0
                side[s]["nw"] += int(h.get("networth", 0) or 0)
                if not h.get("is_bot"):
                    human_side = s
        by_client.setdefault(rec.get("client", "?"), []).append({
            "t": req.get("game_time", 0),
            "d_req": req.get("difficulty"),
            "d_resp": resp.get("difficulty"),
            "side": side,
            "human_side": human_side,
        })
    for rows in by_client.values():
        rows.sort(key=lambda r: r["t"])
    return by_client


def advantage(row):
    """Human team's advantage in kill-equivalents (positive = human winning)."""
    hs = row["human_side"] or "Radiant"
    es = "Dire" if hs == "Radiant" else "Radiant"
    kg = row["side"][hs]["kills"] - row["side"][es]["kills"]
    nwg = (row["side"][hs]["nw"] - row["side"][es]["nw"]) / NW_KILL_EQUIV
    return kg + nwg


def sparkline(values):
    bars = " ▁▂▃▄▅▆▇█"
    if not values:
        return ""
    lo, hi = min(values), max(values)
    span = (hi - lo) or 1.0
    return "".join(bars[min(8, int((v - lo) / span * 8))] for v in values)


def verdict(adv):
    if adv >= 20:
        return "STOMP — you crushed the bots"
    if adv >= BALANCED_BAND:
        return "you won comfortably"
    if adv > -BALANCED_BAND:
        return "CLOSE game"
    if adv > -20:
        return "bots won comfortably"
    return "STOMP — bots crushed you"


def analyze(game):
    last = game[-1]
    hs = last["human_side"]
    if hs is None:
        return None  # bot-vs-bot, nothing to say about challenge
    es = "Dire" if hs == "Radiant" else "Radiant"
    advs = [advantage(r) for r in game]
    ups = sum(1 for r in game if r["d_resp"] and r["d_req"] and r["d_resp"] > r["d_req"])
    downs = sum(1 for r in game if r["d_resp"] and r["d_req"] and r["d_resp"] < r["d_req"])
    diffs = [r["d_req"] for r in game if r["d_req"] is not None]
    return {
        "minutes": last["t"] / 60.0,
        "final_adv": advs[-1],
        "peak_you": max(advs),
        "peak_bots": min(advs),
        "verdict": verdict(advs[-1]),
        "diff_start": diffs[0] if diffs else None,
        "diff_end": diffs[-1] if diffs else None,
        "adjust": ups + downs,
        "ups": ups, "downs": downs,
        "spark": sparkline(advs),
        "human_deaths": last["side"][hs]["deaths"],
        "bot_deaths": last["side"][es]["deaths"],
        "human_kills": last["side"][hs]["kills"],
        "bot_kills": last["side"][es]["kills"],
    }


def main():
    by_client = parse_director(load())
    games = []
    for rows in by_client.values():
        for g in split_games(rows):
            a = analyze(g)
            if a and a["minutes"] >= 3:  # ignore stubs
                games.append(a)

    if not games:
        print(f"no completed games in {DATA_GLOB} — play a few with the server running.")
        return

    for i, g in enumerate(games, 1):
        print(f"\n── Game {i} ─ {g['minutes']:.0f} min ─ {g['verdict']} "
              f"(final advantage {g['final_adv']:+.0f} kill-equiv)")
        print(f"   score   : your team {g['human_kills']}k / {g['human_deaths']}d   "
              f"vs enemy bots {g['bot_kills']}k / {g['bot_deaths']}d")
        print(f"   difficulty: {g['diff_start']} -> {g['diff_end']}  "
              f"({g['adjust']} adjustments: {g['ups']}↑ {g['downs']}↓)")
        print(f"   swing   : your best {g['peak_you']:+.0f}, bots' best {g['peak_bots']:+.0f}")
        print(f"   timeline: {g['spark']}  (your advantage over time; higher = you ahead)")

    n = len(games)
    balanced = sum(1 for g in games if abs(g["final_adv"]) < BALANCED_BAND)
    avg_adj = sum(g["adjust"] for g in games) / n
    avg_len = sum(g["minutes"] for g in games) / n
    print(f"\n══ {n} game(s): {balanced} close, avg {avg_len:.0f} min, "
          f"avg {avg_adj:.1f} difficulty adjustments/game")
    if balanced == n and avg_adj <= 2:
        print("   ✓ games are close with light director intervention — "
              "safe to cut another stat-bonus step (roadmap 05).")
    elif balanced >= n * 0.6:
        print("   ~ mostly close — keep current bonuses, play a few more before cutting.")
    else:
        print("   ✗ games one-sided — tune Commit_Margin / difficulty band before cutting bonuses.")


if __name__ == "__main__":
    main()
