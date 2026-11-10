"""paltalk_ui.room_status on fake views: a room tab that shows 0 chatters is
not an open room (the 9 November false start). Run: python tests/test_room_status.py"""
import sys
import types
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "relay"))
import paltalk_ui as pt  # noqa: E402


class El:
    def __init__(self, aid, name="", kind="Text"):
        self.element_info = types.SimpleNamespace(automation_id=aid, name=name, control_type=kind)

    def is_visible(self):
        return True


def view(*elements):
    v = pt.View()
    v.ok = True
    v.elements = list(elements)
    return v


panel = El("main.ui::rooms::RoomWidget", kind="Pane")
topic = El("main.ui::rooms::RoomWidget.topic", "naqsh bandia owaisiah")
tab = El("main.list.RoomItem_Our Sheikh", kind="Group")

empty = view(panel, topic, tab, El("main.list.RoomItem_Our Sheikh.count", "0 chatters"))
status, why = pt.room_status(empty, ["naqsh bandia"], "Our Sheikh")
assert status == "unknown" and "0 chatters" in why, (status, why)

full = view(panel, topic, tab, El("main.list.RoomItem_Our Sheikh.count", "46 chatters"))
assert pt.room_status(full, ["naqsh bandia"], "Our Sheikh")[0] == "in"

no_count = view(panel, topic, tab)  # Paltalk shows no count: as before
assert pt.room_status(no_count, ["naqsh bandia"], "Our Sheikh")[0] == "in"

assert pt.room_chatters(view(tab, El("main.list.RoomItem_Our Sheikh.c", "1 chatter"))) == 1
assert pt.room_chatters(view(El("elsewhere", "0 chatters"))) is None, "only the room's own tab counts"
print("room status ok")
