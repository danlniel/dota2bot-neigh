"""Run from repo root: python3 tests/test_server_director.py -v"""
import os
import sys
import tempfile
import unittest

os.environ.setdefault("ML_DATA_DIR", tempfile.mkdtemp())
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ml"))
import server  # noqa: E402  (imported after ML_DATA_DIR is set)


def snapshot(t, human_kills, bot_kills, human_nw=10000, bot_nw=10000, difficulty=5, human=True):
    return {
        "game_time": t,
        "difficulty": difficulty,
        "heroes": {
            "Radiant": [{"kda": f"{human_kills}/0/0", "networth": human_nw, "is_bot": not human}],
            "Dire": [{"kda": f"{bot_kills}/0/0", "networth": bot_nw, "is_bot": True}],
        },
    }


class DirectorTest(unittest.TestCase):
    def setUp(self):
        self.policy = server.Policy()

    def test_bot_game_explains_itself(self):
        d = self.policy.director(snapshot(600, 10, 0, human=False))
        self.assertEqual(d["difficulty"], 5)
        self.assertIn("no human", d["reason"])

    def test_grace_period_reports_score(self):
        d = self.policy.director(snapshot(120, 3, 1))
        self.assertEqual(d["difficulty"], 5)
        self.assertIn("4:00", d["reason"])
        self.assertIn("kills 3-1", d["reason"])

    def test_even_game_holds(self):
        d = self.policy.director(snapshot(600, 5, 4))
        self.assertFalse(d["announce"])
        self.assertIn("even", d["reason"])

    def test_lead_needs_two_readings_then_steps_up(self):
        first = self.policy.director(snapshot(600, 10, 2))
        self.assertEqual(first["difficulty"], 5)
        self.assertIn("confirming", first["reason"])
        second = self.policy.director(snapshot(610, 10, 2))
        self.assertEqual(second["difficulty"], 6)
        self.assertTrue(second["announce"])
        self.assertIn("leads", second["reason"])
        self.assertIn("stronger", second["reason"])
        third = self.policy.director(snapshot(620, 10, 2, difficulty=6))
        self.assertEqual(third["difficulty"], 6, "cooldown blocks a second step")
        self.assertIn("next change allowed", third["reason"])

    def test_trailing_eases_off_and_respects_floor(self):
        self.policy.director(snapshot(600, 0, 10))
        d = self.policy.director(snapshot(610, 0, 10))
        self.assertEqual(d["difficulty"], 4)
        self.assertIn("ease off", d["reason"])
        p = server.Policy()
        p.director(snapshot(600, 0, 10, difficulty=0))
        d = p.director(snapshot(610, 0, 10, difficulty=0))
        self.assertEqual(d["difficulty"], 0)
        self.assertIn("min difficulty", d["reason"])

    def test_networth_counts_toward_advantage(self):
        # 2 kills + 5k networth = 3 kill-equivalents = outside the deadband
        self.policy.director(snapshot(600, 4, 2, human_nw=20000, bot_nw=15000))
        d = self.policy.director(snapshot(610, 4, 2, human_nw=20000, bot_nw=15000))
        self.assertEqual(d["difficulty"], 6)
        self.assertIn("networth +5.0k", d["reason"])

    def test_dataset_file_follows_the_date(self):
        path = server.Handler.log_path()
        self.assertTrue(os.path.basename(path).startswith("session-"))
        self.assertIn(server.datetime.now().strftime("%Y%m%d"), path)


if __name__ == "__main__":
    unittest.main()
