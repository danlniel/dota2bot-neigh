#!/usr/bin/env python3
"""Local model server for dota2bot-neigh.

Two Lua clients talk to this server during a game:

  * /policy   — bots VM (bots/FunLib/ml_bridge.lua). Receives compact team
                snapshots, returns FightIQ parameter overrides.
  * /director — FretBots addon VM (bots/FretBots/MLDirector.lua). Receives the
                full hero stats table, returns a difficulty directive.

Every request is appended to ml/data/session-<date>.jsonl so games double as
training data collection. Decision logic lives in Policy below: today a
transparent heuristic, with a hook to load trained weights from ml/model.json
(produced by ml/train.py) when present.

Run:  python3 ml/server.py       (stdlib only, no dependencies)
"""
import json
import os
import subprocess
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Defaults are localhost-only. For a shared deployment (e.g. Docker on a home
# server) set ML_HOST=0.0.0.0 and ML_API_KEY to require an Authorization header.
HOST = os.environ.get("ML_HOST", "127.0.0.1")
PORT = int(os.environ.get("ML_PORT", "5544"))
API_KEY = os.environ.get("ML_API_KEY", "")
DATA_DIR = os.environ.get("ML_DATA_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
MODEL_PATH = os.environ.get("ML_MODEL_PATH") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "model.json")
HERE = os.path.dirname(os.path.abspath(__file__))
# auto-run the balance report + retrain after this many completed games (0 = off)
REPORT_EVERY = int(os.environ.get("ML_REPORT_EVERY", "2"))


class Policy:
    """Decision logic. Heuristic baseline; swaps to trained weights if ml/model.json exists."""

    # ---- bots VM: FightIQ parameter tuning -------------------------------
    def features(self, snapshot: dict, client: str = "?") -> dict:
        """Feature vector shared by serving and training (see ml/train.py).

        Enemy networth isn't visible to the bots VM, so the gap comes from the
        addon VM's /director stream, cached per client (fresh <60s or 0).
        """
        players = snapshot.get("players", [])
        t = snapshot.get("time", 0)
        ally_kills = sum(p.get("kills", 0) for p in players if p.get("team") == "ally")
        enemy_kills = sum(p.get("kills", 0) for p in players if p.get("team") == "enemy")
        ally_nw = sum(p.get("networth", 0) for p in players if p.get("team") == "ally")
        towers = snapshot.get("towers") or {}

        nw_gap = 0.0
        state = self._director_state.get(client)
        if state and time.time() - state["ts"] < 60:
            ally_side = "Radiant" if snapshot.get("team") == 2 else "Dire"
            enemy_side = "Dire" if ally_side == "Radiant" else "Radiant"
            nw_gap = (state.get(ally_side, 0) - state.get(enemy_side, 0)) / 1000.0

        return {
            "kill_diff": ally_kills - enemy_kills,
            "time_norm": min(t / 2400.0, 1.5),
            "ally_nw_pm": ally_nw / max(1.0, t / 60.0) / 1000.0,  # team GPM in k
            "tower_gap": towers.get("ally", 0) - towers.get("enemy", 0),
            "nw_gap": nw_gap,
        }

    def fightiq(self, snapshot: dict, client: str = "?") -> dict:
        """Return FightIQ overrides for the requesting team.

        Baseline heuristic: when the bot team is behind on kills, play more
        disciplined (higher commit margin — only take clearly-won fights).
        When ahead, press the advantage with a lower margin.
        """
        feats = self.features(snapshot, client)
        kill_diff = feats["kill_diff"]

        if self.model is not None:
            return self._model_fightiq(feats)

        if kill_diff <= -8:
            margin = 1.18   # far behind: only take stomps
        elif kill_diff <= -3:
            margin = 1.10
        elif kill_diff >= 8:
            margin = 0.98   # far ahead: force fights, close the game
        elif kill_diff >= 3:
            margin = 1.02
        else:
            margin = 1.05
        return {"Commit_Margin": round(margin, 3)}

    def _model_fightiq(self, feats: dict) -> dict:
        """Linear model over the feature vector: margin = bias + w · feats."""
        w = self.model.get("fightiq", {})
        weights = w.get("weights", {})
        margin = w.get("bias", 1.05) + sum(weights.get(k, 0.0) * v for k, v in feats.items())
        return {"Commit_Margin": round(max(0.9, min(1.3, margin)), 3)}

    # ---- FretBots VM: adaptive difficulty --------------------------------
    # Fully automatic: nobody sets difficulty. The game starts at a neutral
    # level and this controller steers it to keep the match close.
    MIN_GAME_TIME = 240      # let the laning phase establish a signal first
    ADJUST_COOLDOWN = int(os.environ.get("ML_ADJUST_COOLDOWN", "60"))  # s between changes
    DEADBAND = float(os.environ.get("ML_DEADBAND", "3"))  # |advantage| below = balanced
    # Networth is CONTAMINATED by the director's own output (difficulty gold,
    # GPM top-ups all land in bot networth), so it must never outvote kills —
    # weighting it like kills created a feedback loop that oscillated
    # difficulty all game (observed in real session data 2026-07-11).
    NW_KILL_EQUIV = 5000.0   # gold per kill-equivalent (was 1000)

    def __init__(self):
        self.model = None
        self._last_adjust = {}     # client -> unix ts of last difficulty change
        self._director_state = {}  # client -> {"Radiant": nw, "Dire": nw, "ts": ...}
        self._last_game_time = {}  # client -> last seen game clock (for boundary detection)
        self._last_direction = {}  # client -> sign of last advantage reading (hysteresis)
        self._games_done = 0
        self._auto_lock = threading.Lock()
        if os.path.exists(MODEL_PATH):
            with open(MODEL_PATH) as f:
                self.model = json.load(f)
            print(f"[policy] loaded trained model from {MODEL_PATH}")
        else:
            print("[policy] no trained model found, using heuristic baseline")

    # ---- automation: report + retrain every N completed games ------------
    def note_game_boundary(self, client: str, game_time: float):
        """A game-clock reset on a client means its previous game finished."""
        last = self._last_game_time.get(client)
        self._last_game_time[client] = game_time
        if last is not None and game_time < last - 60 and last > 300:
            self._games_done += 1
            print(f"[auto] game completed on {client} ({self._games_done}/{REPORT_EVERY} until report)")
            if REPORT_EVERY > 0 and self._games_done >= REPORT_EVERY:
                self._games_done = 0
                threading.Thread(target=self._report_and_retrain, daemon=True).start()

    def _report_and_retrain(self):
        if not self._auto_lock.acquire(blocking=False):
            return  # a run is already in progress
        try:
            stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            report = subprocess.run(
                [sys.executable, os.path.join(HERE, "report.py")],
                capture_output=True, text=True, timeout=120).stdout
            print(f"[auto] balance report ({stamp}):\n{report}")
            os.makedirs(DATA_DIR, exist_ok=True)
            with open(os.path.join(DATA_DIR, "report-latest.txt"), "w") as f:
                f.write(f"generated {stamp}\n\n{report}")
            with open(os.path.join(DATA_DIR, "report-history.log"), "a") as f:
                f.write(f"\n===== {stamp} =====\n{report}")

            trained = subprocess.run(
                [sys.executable, os.path.join(HERE, "train.py")],
                capture_output=True, text=True, timeout=300).stdout
            print(f"[auto] trainer:\n{trained}")
            if "wrote" in trained and os.path.exists(MODEL_PATH):
                with open(MODEL_PATH) as f:
                    self.model = json.load(f)
                print("[auto] new model loaded in-process (no restart needed)")
        except Exception as e:  # automation must never take the server down
            print(f"[auto] report/retrain failed: {e}")
        finally:
            self._auto_lock.release()

    def director(self, snapshot: dict, client: str = "?") -> dict:
        """Adaptive difficulty controller.

        Advantage of the human team over the enemy team, in "kill equivalents":
            advantage = kill_gap + networth_gap / 1000
        Steering: outside the deadband, move difficulty one step toward
        balance, at most once per cooldown window. Kills + networth together
        react faster and more fairly than kills alone (a farming human is
        "winning" before the kills show it).
        """
        heroes = snapshot.get("heroes", {})
        side_kills = {"Radiant": 0, "Dire": 0}
        side_nw = {"Radiant": 0, "Dire": 0}
        human_side = None
        for side in ("Radiant", "Dire"):
            for h in heroes.get(side, []):
                side_kills[side] += int(str(h.get("kda", "0/0/0")).split("/")[0])
                side_nw[side] += int(h.get("networth", 0) or 0)
                if not h.get("is_bot"):
                    human_side = side

        # cache side networth so /policy can compute the networth gap
        self._director_state[client] = {
            "Radiant": side_nw["Radiant"], "Dire": side_nw["Dire"], "ts": time.time(),
        }
        self.note_game_boundary(client, snapshot.get("game_time", 0))

        difficulty = snapshot.get("difficulty", 5)
        directive = {"difficulty": difficulty, "announce": False}
        if human_side is None:  # bot-vs-bot game: nothing to balance for
            return directive
        if snapshot.get("game_time", 0) < self.MIN_GAME_TIME:
            return directive

        now = time.time()

        enemy_side = "Dire" if human_side == "Radiant" else "Radiant"
        kill_gap = side_kills[human_side] - side_kills[enemy_side]
        nw_gap = side_nw[human_side] - side_nw[enemy_side]
        advantage = kill_gap + nw_gap / self.NW_KILL_EQUIV

        # hysteresis: two consecutive readings must agree on direction before
        # any change (kills the flip-flopping a single noisy reading causes)
        direction = 1 if advantage >= self.DEADBAND else (-1 if advantage <= -self.DEADBAND else 0)
        prev_direction = self._last_direction.get(client, 0)
        self._last_direction[client] = direction

        if now - self._last_adjust.get(client, 0) < self.ADJUST_COOLDOWN:
            return directive

        if direction == 1 and prev_direction == 1 and difficulty < 10:
            directive["difficulty"] = difficulty + 1
        elif direction == -1 and prev_direction == -1 and difficulty > 0:
            directive["difficulty"] = difficulty - 1

        if directive["difficulty"] != difficulty:
            directive["announce"] = True
            self._last_adjust[client] = now
        return directive


START_TIME = time.time()


class Handler(BaseHTTPRequestHandler):
    policy = Policy()
    log_path = os.path.join(DATA_DIR, f"session-{datetime.now():%Y%m%d}.jsonl")

    def do_GET(self):
        if self.path == "/health":
            self._respond({
                "status": "ok",
                "model": "trained" if self.policy.model else "heuristic",
                "uptime_s": int(time.time() - START_TIME),
            })
        else:
            self._respond({"error": "unknown endpoint"}, 404)

    def _respond(self, obj: dict, code: int = 200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _log(self, endpoint: str, request_obj: dict, response_obj: dict):
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(self.log_path, "a") as f:
            f.write(json.dumps({
                "ts": time.time(),
                "client": self.client_address[0],  # lets train.py separate concurrent games
                "endpoint": endpoint,
                "request": request_obj,
                "response": response_obj,
            }) + "\n")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        if length > 1_000_000:  # snapshots are a few KB; reject junk
            self._respond({"error": "payload too large"}, 413)
            return
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._respond({"error": "bad json"}, 400)
            return

        # key may come as a header (addon VM client) or in the body
        if API_KEY:
            supplied = self.headers.get("Authorization", "") or payload.get("api_key", "")
            if supplied != API_KEY:
                self._respond({"error": "unauthorized"}, 401)
                return
        payload.pop("api_key", None)  # never write secrets into the dataset

        if self.path == "/policy":
            result = {"fightiq": self.policy.fightiq(payload, self.client_address[0])}
        elif self.path == "/director":
            result = self.policy.director(payload, self.client_address[0])
        else:
            self._respond({"error": "unknown endpoint"}, 404)
            return

        self._log(self.path, payload, result)
        self._respond(result)

    def log_message(self, fmt, *args):  # quiet the default per-request stderr noise
        pass


if __name__ == "__main__":
    print(f"model server listening on http://{HOST}:{PORT}  (dataset -> {DATA_DIR})")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
