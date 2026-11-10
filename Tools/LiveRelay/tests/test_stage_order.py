"""The stage order, with the one step back after the 7th Latifa.
Run: python tests/test_stage_order.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "relay"))
from audio_picker import ahead  # noqa: E402

assert ahead("latifa-2", "latifa-1")
assert not ahead("latifa-1", "latifa-2")
assert ahead("latifa-1", "latifa-7"), "after the 7th the Zikr returns to the 1st"
assert ahead("raabta", "latifa-1"), "then Raabta"
assert not ahead("latifa-1", "raabta"), "a late '1st latifa' after Raabta is behind"
assert not ahead("latifa-6", "latifa-7")
assert ahead("ahadiyat", "raabta")
assert ahead("latifa-1", None)
print("stage order ok")
