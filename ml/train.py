#!/usr/bin/env python3
"""Offline trainer for the fight-commit policy.

Reads the JSONL dataset that ml/server.py accumulates during games, fits a
small linear model mapping game state -> Commit_Margin, and writes ml/model.json,
which server.py automatically loads on next start.

The target is derived by hindsight: for each /policy snapshot, look at the
team's kill differential N minutes later. If fights taken under a given margin
lost ground, prefer a higher (more disciplined) margin in that state; if they
gained ground, prefer a lower (more aggressive) one.

This is intentionally the simplest thing that closes the loop:
    play games -> collect data -> train -> better parameters next game.
Swap the linear fit for anything stronger (per-hero features, an MLP, contextual
bandit) once enough games are collected — the interfaces won't change.

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
HORIZON_SECONDS = 300  # judge each snapshot by kill-diff change over the next 5 minutes


def load_policy_rows():
    rows = []
    for path in sorted(glob.glob(DATA_GLOB)):
        with open(path) as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if rec.get("endpoint") != "/policy":
                    continue
                req = rec.get("request", {})
                players = req.get("players", [])
                ally = sum(p.get("kills", 0) for p in players if p.get("team") == "ally")
                enemy = sum(p.get("kills", 0) for p in players if p.get("team") == "enemy")
                rows.append({
                    "time": req.get("time", 0),
                    "client": rec.get("client", "?"),
                    "team": req.get("team"),
                    "kill_diff": ally - enemy,
                    "margin": (req.get("fightiq") or {}).get("Commit_Margin", 1.05),
                })
    return rows


def build_examples(rows):
    """Pair each snapshot with the kill-diff delta over the horizon (same team, same game).

    Sequences are keyed by (client, team) so concurrent lobbies on a shared
    server don't interleave; games within one client are separated by time
    resets (snapshot time decreasing).
    """
    examples = []
    by_team = {}
    for r in rows:
        key = (r["client"], r["team"])
        seq = by_team.setdefault(key, [])
        if seq and r["time"] < seq[-1]["time"]:  # new game started
            examples.extend(pair_horizon(seq))
            by_team[key] = [r]
        else:
            seq.append(r)
    for seq in by_team.values():
        examples.extend(pair_horizon(seq))
    return examples


def pair_horizon(seq):
    out = []
    for i, r in enumerate(seq):
        future = next((s for s in seq[i + 1:] if s["time"] - r["time"] >= HORIZON_SECONDS), None)
        if future:
            out.append({
                "kill_diff": r["kill_diff"],
                "time_norm": min(r["time"] / 2400.0, 1.5),
                "margin": r["margin"],
                "outcome": future["kill_diff"] - r["kill_diff"],  # >0 team gained ground
            })
    return out


def fit(examples):
    """Least-squares fit of margin ~ bias + w1*kill_diff + w2*time, weighted toward
    margins whose outcomes were good. With sparse data this collapses gracefully
    toward the heuristic default."""
    if len(examples) < 50:
        print(f"only {len(examples)} usable examples — need ~50+; keep playing games first.")
        return None

    # weight: prefer examples where the margin in effect led to gaining ground
    def weight(e):
        return max(0.1, 1.0 + 0.15 * e["outcome"])

    # normal equations for y=margin, X=[1, kill_diff, time_norm], weights w
    sums = {k: 0.0 for k in ("w", "wx1", "wx2", "wy", "wx1x1", "wx1x2", "wx2x2", "wx1y", "wx2y")}
    for e in examples:
        w = weight(e)
        x1, x2, y = e["kill_diff"], e["time_norm"], e["margin"]
        sums["w"] += w
        sums["wx1"] += w * x1
        sums["wx2"] += w * x2
        sums["wy"] += w * y
        sums["wx1x1"] += w * x1 * x1
        sums["wx1x2"] += w * x1 * x2
        sums["wx2x2"] += w * x2 * x2
        sums["wx1y"] += w * x1 * y
        sums["wx2y"] += w * x2 * y

    # solve 3x3 system via elimination (stdlib-only; fine at this size)
    import itertools
    A = [[sums["w"], sums["wx1"], sums["wx2"]],
         [sums["wx1"], sums["wx1x1"], sums["wx1x2"]],
         [sums["wx2"], sums["wx1x2"], sums["wx2x2"]]]
    b = [sums["wy"], sums["wx1y"], sums["wx2y"]]
    n = 3
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(A[r][col]))
        if abs(A[pivot][col]) < 1e-9:
            print("degenerate data (not enough variation); not writing a model.")
            return None
        A[col], A[pivot] = A[pivot], A[col]
        b[col], b[pivot] = b[pivot], b[col]
        for r in range(n):
            if r != col:
                f = A[r][col] / A[col][col]
                for c in range(col, n):
                    A[r][c] -= f * A[col][c]
                b[r] -= f * b[col]
    bias, w_kd, w_t = (b[i] / A[i][i] for i in range(n))
    return {"fightiq": {"bias": round(bias, 4), "w_kill_diff": round(w_kd, 5), "w_time": round(w_t, 4)}}


def main():
    rows = load_policy_rows()
    print(f"loaded {len(rows)} policy snapshots from {DATA_GLOB}")
    examples = build_examples(rows)
    model = fit(examples)
    if model:
        with open(MODEL_PATH, "w") as f:
            json.dump(model, f, indent=2)
        print(f"wrote {MODEL_PATH}: {model}")
        print("restart ml/server.py to serve the trained policy.")


if __name__ == "__main__":
    main()
