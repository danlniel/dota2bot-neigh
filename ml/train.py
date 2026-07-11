#!/usr/bin/env python3
"""Offline trainer for the fight-commit policy.

Reads the JSONL dataset that ml/server.py accumulates during games, fits a
linear model mapping game-state features -> Commit_Margin, and writes
ml/model.json, which server.py automatically loads on next start.

Features (must match Policy.features in server.py):
    kill_diff   team kill gap (ally - enemy)
    time_norm   game time / 40min, capped at 1.5
    ally_nw_pm  team networth per minute, in thousands
    tower_gap   standing towers (ally - enemy)
    nw_gap      networth gap in thousands, joined from the /director stream

The target is derived by hindsight: for each /policy snapshot, look at the
team's kill differential 5 minutes later. Margins that were in effect while
the team gained ground get up-weighted; ground lost, down-weighted.

This is intentionally the simplest thing that closes the loop:
    play games -> collect data -> train -> better parameters next game.

Run:  python3 ml/train.py       (stdlib only)
"""
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
# honor the same env vars as server.py so Docker retraining works on the volume
DATA_DIR = os.environ.get("ML_DATA_DIR") or os.path.join(HERE, "data")
DATA_GLOB = os.path.join(DATA_DIR, "session-*.jsonl")
MODEL_PATH = os.environ.get("ML_MODEL_PATH") or os.path.join(HERE, "model.json")
HORIZON_SECONDS = 300   # judge each snapshot by kill-diff change over the next 5 min
DIRECTOR_JOIN_S = 45    # max wall-clock distance for the /director networth join

FEATURES = ["kill_diff", "time_norm", "ally_nw_pm", "tower_gap", "nw_gap"]


def load_rows():
    policy_rows, director_rows = [], []
    for path in sorted(glob.glob(DATA_GLOB)):
        with open(path) as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                req = rec.get("request", {})
                client = rec.get("client", "?")
                if rec.get("endpoint") == "/policy":
                    players = req.get("players", [])
                    ally = [p for p in players if p.get("team") == "ally"]
                    enemy = [p for p in players if p.get("team") == "enemy"]
                    t = req.get("time", 0)
                    towers = req.get("towers") or {}
                    policy_rows.append({
                        "ts": rec.get("ts", 0),
                        "client": client,
                        "team": req.get("team"),
                        "time": t,
                        "kill_diff": sum(p.get("kills", 0) for p in ally) - sum(p.get("kills", 0) for p in enemy),
                        "ally_nw": sum(p.get("networth", 0) for p in ally),
                        "tower_gap": towers.get("ally", 0) - towers.get("enemy", 0),
                        "margin": (req.get("fightiq") or {}).get("Commit_Margin", 1.05),
                    })
                elif rec.get("endpoint") == "/director":
                    heroes = req.get("heroes", {})
                    side_nw = {
                        side: sum(int(h.get("networth", 0) or 0) for h in heroes.get(side, []))
                        for side in ("Radiant", "Dire")
                    }
                    director_rows.append({"ts": rec.get("ts", 0), "client": client, "nw": side_nw})
    return policy_rows, director_rows


def join_networth(policy_rows, director_rows):
    """Attach nw_gap to each policy row from the nearest director row (same client)."""
    by_client = {}
    for d in director_rows:
        by_client.setdefault(d["client"], []).append(d)
    for rows in by_client.values():
        rows.sort(key=lambda d: d["ts"])

    for r in policy_rows:
        best, best_dt = None, DIRECTOR_JOIN_S + 1
        for d in by_client.get(r["client"], []):
            dt = abs(d["ts"] - r["ts"])
            if dt < best_dt:
                best, best_dt = d, dt
        if best:
            ally_side = "Radiant" if r["team"] == 2 else "Dire"
            enemy_side = "Dire" if ally_side == "Radiant" else "Radiant"
            r["nw_gap"] = (best["nw"].get(ally_side, 0) - best["nw"].get(enemy_side, 0)) / 1000.0
        else:
            r["nw_gap"] = 0.0
    return policy_rows


def build_examples(rows):
    """Pair each snapshot with the kill-diff delta over the horizon (same team, same game).

    Sequences are keyed by (client, team) so concurrent lobbies on a shared
    server don't interleave; games within one client are separated by time
    resets (snapshot game-time decreasing).
    """
    examples = []
    by_key = {}
    for r in rows:
        key = (r["client"], r["team"])
        seq = by_key.setdefault(key, [])
        if seq and r["time"] < seq[-1]["time"]:  # new game started
            examples.extend(pair_horizon(seq))
            by_key[key] = [r]
        else:
            seq.append(r)
    for seq in by_key.values():
        examples.extend(pair_horizon(seq))
    return examples


def pair_horizon(seq):
    out = []
    for i, r in enumerate(seq):
        future = next((s for s in seq[i + 1:] if s["time"] - r["time"] >= HORIZON_SECONDS), None)
        if future:
            out.append({
                "feats": {
                    "kill_diff": r["kill_diff"],
                    "time_norm": min(r["time"] / 2400.0, 1.5),
                    "ally_nw_pm": r["ally_nw"] / max(1.0, r["time"] / 60.0) / 1000.0,
                    "tower_gap": r["tower_gap"],
                    "nw_gap": r["nw_gap"],
                },
                "margin": r["margin"],
                "outcome": future["kill_diff"] - r["kill_diff"],  # >0 team gained ground
            })
    return out


def solve(A, b):
    """Gaussian elimination with partial pivoting; returns x or None if singular."""
    n = len(b)
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(A[r][col]))
        if abs(A[pivot][col]) < 1e-9:
            return None
        A[col], A[pivot] = A[pivot], A[col]
        b[col], b[pivot] = b[pivot], b[col]
        for r in range(n):
            if r != col:
                f = A[r][col] / A[col][col]
                for c in range(col, n):
                    A[r][c] -= f * A[col][c]
                b[r] -= f * b[col]
    return [b[i] / A[i][i] for i in range(n)]


def fit(examples):
    """Weighted least squares of margin ~ bias + w · feats, weighted toward
    margins whose outcomes were good. Prints train/holdout RMSE."""
    if len(examples) < 50:
        print(f"only {len(examples)} usable examples — need ~50+; keep playing games first.")
        return None

    split = int(len(examples) * 0.8)
    train, holdout = examples[:split], examples[split:]

    def weight(e):
        return max(0.1, 1.0 + 0.15 * e["outcome"])

    def x_vec(e):
        return [1.0] + [e["feats"][k] for k in FEATURES]

    n = 1 + len(FEATURES)
    A = [[0.0] * n for _ in range(n)]
    bvec = [0.0] * n
    for e in train:
        w, x, y = weight(e), x_vec(e), e["margin"]
        for i in range(n):
            for j in range(n):
                A[i][j] += w * x[i] * x[j]
            bvec[i] += w * x[i] * y

    coef = solve(A, bvec)
    if coef is None:
        print("degenerate data (not enough variation); not writing a model.")
        return None

    def rmse(rows):
        if not rows:
            return float("nan")
        se = 0.0
        for e in rows:
            pred = sum(c * xi for c, xi in zip(coef, x_vec(e)))
            se += (pred - e["margin"]) ** 2
        return (se / len(rows)) ** 0.5

    print(f"train RMSE: {rmse(train):.4f}   holdout RMSE: {rmse(holdout):.4f}   (n={len(examples)})")

    return {"fightiq": {
        "bias": round(coef[0], 4),
        "weights": {k: round(coef[i + 1], 5) for i, k in enumerate(FEATURES)},
    }}


def main():
    policy_rows, director_rows = load_rows()
    print(f"loaded {len(policy_rows)} policy + {len(director_rows)} director snapshots from {DATA_GLOB}")
    examples = build_examples(join_networth(policy_rows, director_rows))
    model = fit(examples)
    if model:
        with open(MODEL_PATH, "w") as f:
            json.dump(model, f, indent=2)
        print(f"wrote {MODEL_PATH}: {model}")
        print("restart ml/server.py to serve the trained policy.")


if __name__ == "__main__":
    main()
