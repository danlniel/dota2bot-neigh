#!/usr/bin/env python3
"""Game-balance report over the collected dataset.

This is the measuring stick for roadmap item 5 (natural economy): after each
config step that reduces FretBots bonuses, play a few games and run this to
see whether the bots still hold their own.

Per game it reports:
  * duration seen, final kill gap and networth gap (human side vs enemy side)
  * how often (and which way) the adaptive director changed difficulty
    -> fewer/smaller boosts = the bots needed less artificial help
  * bot-team GPM at the 15-minute mark (from /policy ally networth)

Run:  python3 ml/report.py       (stdlib only; reads the same data dir as server.py)
"""
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.environ.get("ML_DATA_DIR") or os.path.join(HERE, "data")
DATA_GLOB = os.path.join(DATA_DIR, "session-*.jsonl")


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


def split_games(rows, time_key):
    """Split a chronological row list into games on game-clock resets."""
    games, cur, last_t = [], [], None
    for r in rows:
        t = r[time_key]
        if last_t is not None and t < last_t - 30:
            if cur:
                games.append(cur)
            cur = []
        cur.append(r)
        last_t = t
    if cur:
        games.append(cur)
    return games


def director_games(recs):
    by_client = {}
    for rec in recs:
        if rec.get("endpoint") != "/director":
            continue
        req, resp = rec.get("request", {}), rec.get("response", {})
        heroes = req.get("heroes", {})
        side = {s: {"kills": 0, "nw": 0} for s in ("Radiant", "Dire")}
        human_side = None
        for s in ("Radiant", "Dire"):
            for h in heroes.get(s, []):
                side[s]["kills"] += int(str(h.get("kda", "0/0/0")).split("/")[0])
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

    out = []
    for client, rows in by_client.items():
        for game in split_games(rows, "t"):
            ups = sum(1 for r in game if r["d_resp"] is not None and r["d_req"] is not None and r["d_resp"] > r["d_req"])
            downs = sum(1 for r in game if r["d_resp"] is not None and r["d_req"] is not None and r["d_resp"] < r["d_req"])
            last = game[-1]
            hs = last["human_side"] or "Radiant"
            es = "Dire" if hs == "Radiant" else "Radiant"
            out.append({
                "client": client,
                "minutes": last["t"] / 60.0,
                "kill_gap": last["side"][hs]["kills"] - last["side"][es]["kills"],
                "nw_gap_k": (last["side"][hs]["nw"] - last["side"][es]["nw"]) / 1000.0,
                "boosts_up": ups,
                "boosts_down": downs,
            })
    return out


def bot_gpm_at_15(recs):
    """Per (client, team): team GPM around the 15-minute mark from /policy rows."""
    by_key = {}
    for rec in recs:
        if rec.get("endpoint") != "/policy":
            continue
        req = rec.get("request", {})
        ally_nw = sum(p.get("networth", 0) for p in req.get("players", []) if p.get("team") == "ally")
        by_key.setdefault((rec.get("client", "?"), req.get("team")), []).append(
            {"t": req.get("time", 0), "nw": ally_nw})
    out = {}
    for key, rows in by_key.items():
        for gi, game in enumerate(split_games(rows, "t")):
            best = min(game, key=lambda r: abs(r["t"] - 900))
            if abs(best["t"] - 900) < 90 and best["nw"] > 0:
                out[(key[0], key[1], gi)] = best["nw"] / (best["t"] / 60.0)
    return out


def main():
    recs = load()
    games = director_games(recs)
    gpm = bot_gpm_at_15(recs)

    if not games and not gpm:
        print(f"no game data found in {DATA_GLOB} — play with the server running first.")
        return

    print(f"{'client':<16}{'mins':>6}{'kill gap':>10}{'nw gap(k)':>11}{'diff up':>9}{'diff down':>10}")
    for g in games:
        print(f"{g['client']:<16}{g['minutes']:>6.0f}{g['kill_gap']:>10}{g['nw_gap_k']:>11.1f}"
              f"{g['boosts_up']:>9}{g['boosts_down']:>10}")

    if games:
        total_up = sum(g["boosts_up"] for g in games)
        total_down = sum(g["boosts_down"] for g in games)
        balanced = sum(1 for g in games if abs(g["kill_gap"] + g["nw_gap_k"]) <= 10)
        print(f"\n{len(games)} game(s): {balanced} ended balanced (|kill+nw gap| <= 10 kill-equiv); "
              f"director boosted bots up {total_up}x, down {total_down}x.")
        print("goal (roadmap 05): balanced games with <=2 adjustments each -> safe to cut bonuses further.")

    if gpm:
        print("\nbot-team GPM @15min (natural + injected):")
        for (client, team, gi), v in sorted(gpm.items()):
            print(f"  {client} team {team} game {gi + 1}: {v:,.0f}")


if __name__ == "__main__":
    main()
