"""Paltalk desktop through UI Automation: find, join and read the room.

The detections are the ones the listener proved in rehearsals on Our Sheikh
(Tools/LiveListener/listener_agent.py). Nothing here clicks with the mouse:
controls are invoked through accessibility, so the relay PC's cursor never
moves. Writing to the room (mic, chat) lives in RoomWriter and is refused
when the relay runs listen-only."""

from __future__ import annotations

import ctypes
import subprocess
import time
from pathlib import Path

import psutil

PALTALK_PATHS = [
    Path(r"C:\Program Files\Paltalk\paltalk.exe"),
    Path(r"C:\Program Files (x86)\Paltalk\paltalk.exe"),
]


def log(message: str) -> None:
    print(f"{time.strftime('%H:%M:%S')} [paltalk] {message}", flush=True)


def paltalk_exe() -> Path | None:
    import os
    local = Path(os.environ.get("LOCALAPPDATA", ""))
    # The current installer puts Paltalk under the user's LocalAppData.
    for path in [*PALTALK_PATHS, local / "Paltalk" / "Paltalk.exe", local / "Programs" / "Paltalk" / "paltalk.exe"]:
        if path.exists():
            return path
    return None


def running() -> bool:
    return any((p.info.get("name") or "").lower() == "paltalk.exe" for p in psutil.process_iter(["name"]))


def main_window():
    """Paltalk's main window. After signing in, Paltalk can leave its old
    sign-in window ("LoggingWidget") open beside the main one, both named
    "Paltalk"; the main one holds ui::MainWidget."""
    from pywinauto import Desktop
    windows = [w for w in Desktop(backend="uia").windows() if (w.element_info.name or "") == "Paltalk"]
    if len(windows) > 1:
        for window in windows:
            try:
                if any((g.element_info.automation_id or "").endswith("ui::MainWidget")
                       for g in window.descendants(control_type="Group")):
                    return window
            except Exception:  # noqa: BLE001
                continue
    return windows[0] if windows else None


def dismiss_prompt() -> bool:
    """Cancels a Paltalk confirmation box (e.g. its camera "Video Settings"
    prompt), which otherwise sits over the room unattended."""
    window = main_window()
    try:
        box = next((g for g in window.descendants(control_type="Group")
                    if (g.element_info.automation_id or "").endswith("ConfirmationMessageBox")), None) if window else None
        if box is None:
            return False
        buttons = {b.element_info.name or "": b for b in box.parent().descendants(control_type="Button")}
        # Only the camera prompt: other boxes may ask something that matters.
        cancel = buttons.get("Cancel") if "Video Settings" in buttons else None
        if cancel is None:
            return False
        cancel.invoke()
        log("cancelled a Paltalk prompt")
        return True
    except Exception:  # noqa: BLE001
        return False


def ensure_running() -> str | None:
    """Starts Paltalk if needed. Returns a problem, or None."""
    if running():
        return None if main_window() else "Paltalk is running but its window is hidden"
    exe = paltalk_exe()
    if not exe:
        return "Paltalk is not installed"
    subprocess.Popen([str(exe)], close_fds=True)
    log("started Paltalk")
    return "Paltalk was not running (started)"


def signed_in() -> bool:
    """Paltalk has passed its loading/sign-in screen: its contacts panel or
    room browser exists. Before that, opening a room link only restarts the
    loading."""
    window = main_window()
    if window is None:
        return False
    try:
        return any(any(key in (e.element_info.automation_id or "") for key in ("LeftPanelWidget", "ROOM_BROWSER_WIDGET", "RoomWidget"))
                   for e in window.descendants(control_type="Group"))
    except Exception:  # noqa: BLE001
        return False


def login_form() -> bool:
    """Paltalk is on its log-in form (signed out: the account was used
    elsewhere, or Paltalk's own login service failed, e.g. "unknown status:
    502"). Starting Paltalk over does not help there: someone must sign in."""
    from pywinauto import Desktop
    try:
        for window in Desktop(backend="uia").windows():
            if (window.element_info.name or "") != "Paltalk":
                continue
            if any((b.element_info.name or "") == "Log in" for b in window.descendants(control_type="Button")):
                return True
    except Exception:  # noqa: BLE001
        pass
    return False


def remote_desktop_connected() -> bool:
    """This desktop is being shown over Remote Desktop (someone is working on
    it), not running on the console unattended."""
    return bool(ctypes.windll.user32.GetSystemMetrics(0x1000))  # SM_REMOTESESSION


def restart() -> None:
    """Closes Paltalk; ensure_running starts it again."""
    for proc in psutil.process_iter(["name"]):
        if (proc.info.get("name") or "").lower() == "paltalk.exe":
            try:
                proc.kill()
            except psutil.Error:
                pass
    log("Paltalk closed for a restart")


def room_panel(window):
    return next((e for e in window.descendants(control_type="Group")
                 if (e.element_info.automation_id or "").endswith("ui::rooms::RoomWidget")), None)


def joined(markers: list[str]) -> str | None:
    """The joined room's matching text line, or None when not in that room.
    The room name is drawn as a picture, so the room is recognised by its
    topic line (or any text) containing one of `markers`."""
    window = main_window()
    if window is None:
        return None
    try:
        panel = room_panel(window)
        if panel is None:
            return None
        if _close_failed_room(panel):
            return None
        wanted = [m.lower() for m in markers if m]
        # Opened by the room's own id (PALTALK_ROOM_LINK), an open room panel
        # is that room; no topic line is needed.
        if not wanted:
            return "room open"
        for label in panel.descendants(control_type="Text"):
            text = label.element_info.name or ""
            if any(m in text.lower() for m in wanted):
                return text
    except Exception:  # noqa: BLE001 - the UI changes under us
        return None
    return None


def close_popups() -> bool:
    """Paltalk's tips ("View a member on webcam"...) open as a layered
    overlay over the room, and the room cannot be read behind them. Their
    own close button only - never the room tab's."""
    window = main_window()
    if window is None:
        return False
    closed = False
    try:
        for button in window.descendants(control_type="Button"):
            aid = button.element_info.automation_id or ""
            if "ui::vog::LayeredWidget" in aid and "close" in (button.element_info.name or "").lower():
                button.invoke()
                closed = True
    except Exception:  # noqa: BLE001 - the UI changes under us
        pass
    if closed:
        log("closed a Paltalk pop-up")
    return closed


def _close_failed_room(panel) -> bool:
    """A room that closed (or never opened) leaves its tab behind with
    "The room you are trying to enter is currently not open... [Close Room]"
    over it - the tab is not the room. Press Close Room, so the next join
    opens the room afresh; True while that notice is up."""
    for overlay in panel.descendants(control_type="Group"):
        if not (overlay.element_info.automation_id or "").endswith("JoinRoomFailedMessageOverlayWidget"):
            continue
        if not overlay.is_visible():
            return False
        for button in overlay.descendants(control_type="Button"):
            try:
                button.invoke()
                log("the room is not open: closed its tab")
            except Exception:  # noqa: BLE001 - the next round tries again
                pass
            break
        return True
    return False


def try_join(room: str, link: str | None = None) -> bool:
    """Opens the room by its deep link (paltalk://group/<id>, what the room's
    public paltalk.im link resolves to), else searches it and opens its tile."""
    if link:
        import os
        try:
            os.startfile(link)
            log(f"opened {link}")
            return True
        except OSError as error:
            log(f"could not open {link}: {error}")
    window = main_window()
    if window is None:
        return False
    try:
        if window.is_minimized():
            window.restore()
        box = next((e for e in window.descendants(control_type="Edit")
                    if (e.element_info.name or "") == "Search Room"), None)
        if box is None:
            # The search lives on the room browser: open it first.
            rooms = next((b for b in window.descendants(control_type="Button")
                          if (b.element_info.name or "") == "ContactList_RoomsButton"), None)
            if rooms is not None:
                rooms.invoke()
                time.sleep(4)
                box = next((e for e in window.descendants(control_type="Edit")
                            if (e.element_info.name or "") == "Search Room"), None)
        if box is None:
            log("search box not found")
            return False
        box.set_edit_text(room)
        # The search's own button, pressed through accessibility: an Enter
        # key only lands when Paltalk is the foreground window, which a
        # remote or console session cannot promise.
        start = next((e for e in window.descendants(control_type="Button")
                      if (e.element_info.name or "") == "Start Search"), None)
        if start is not None:
            start.invoke()
        else:
            try:
                window.set_focus()
                box.set_focus()
            except Exception:  # noqa: BLE001 - Windows may refuse to change focus
                pass
            box.type_keys("{ENTER}", set_foreground=False)
        time.sleep(4)
        wanted = room.strip().lower()
        tiles = [t for t in window.descendants(control_type="Button")
                 if (t.element_info.automation_id or "").endswith("RoomTiles")]
        exact = [t for t in tiles if (t.element_info.name or "").strip().lower() == wanted]
        close = [t for t in tiles if wanted in (t.element_info.name or "").strip().lower()]
        for tile in exact or close:
            log(f"room listed: {tile.element_info.name}; opening it")
            tile.invoke()
            return True
        log(f"room {room!r} not listed (closed?); tiles: {[t.element_info.name for t in tiles][:6]}")
    except Exception as error:  # noqa: BLE001
        log(f"room search failed: {error}")
    return False


def someone_talking() -> bool:
    window = main_window()
    try:
        panel = room_panel(window) if window else None
        return panel is not None and any(
            (e.element_info.automation_id or "").endswith("ui::rooms::TalkerWidget")
            for e in panel.descendants(control_type="Group"))
    except Exception:  # noqa: BLE001
        return False


def toggle_speaker() -> bool:
    window = main_window()
    try:
        panel = room_panel(window) if window else None
        button = next((e for e in panel.descendants(control_type="Button")
                       if (e.element_info.name or "") == "Toggle Speaker"), None) if panel else None
        if button is None:
            return False
        button.invoke()
        return True
    except Exception:  # noqa: BLE001
        return False


def hide_video() -> bool:
    """Closes the room's video area: the relay needs only sound and chat,
    and decoding cameras costs memory a 2 GB server does not have."""
    window = main_window()
    try:
        panel = room_panel(window) if window else None
        button = next((e for e in panel.descendants(control_type="Button")
                       if (e.element_info.name or "") == "Hide Video Area"), None) if panel else None
        if button is None:
            return False
        button.invoke()
        return True
    except Exception:  # noqa: BLE001
        return False


def chat_messages() -> list[tuple[str, str]]:
    """(sender, text) for each message in the room's chat, top to bottom.
    Paltalk names the sender only on the first of consecutive messages, so
    an unnamed message belongs to the previous sender."""
    window = main_window()
    if window is None:
        return []
    found = []
    try:
        items = [i for i in window.descendants()
                 if (i.element_info.automation_id or "").endswith("ui::chatlog::TextMessageWidget")]
        items.sort(key=lambda i: i.rectangle().top)
        previous = ""
        for item in items:
            sender = text = ""
            for part in item.descendants():
                kind = (part.element_info.automation_id or "").rsplit(".", 1)[-1]
                if kind == "QLabel" and not sender:
                    sender = part.window_text() or ""
                elif kind == "QTextBrowser":
                    try:
                        text = part.iface_text.DocumentRange.GetText(-1) or ""
                    except Exception:  # noqa: BLE001
                        text = part.window_text() or ""
            sender = sender.strip() or previous
            previous = sender
            if sender and text.strip():
                found.append((sender, text.strip()))
    except Exception:  # noqa: BLE001
        return []
    return found


class ChatFollower:
    """Yields only messages that appeared since the last read."""

    def __init__(self) -> None:
        self.seen: list[tuple[str, str]] | None = None

    def new(self) -> list[tuple[str, str]]:
        current = chat_messages()
        if self.seen is None:
            self.seen = current
            return []
        start = 0
        for size in range(min(len(self.seen), len(current)), 0, -1):
            if self.seen[-size:] == current[:size]:
                start = size
                break
        if start == 0 and current and self.seen and current[-1] == self.seen[-1]:
            start = len(current)
        fresh = current[start:]
        self.seen = current
        return fresh


def dump_controls(path: Path) -> None:
    """Writes every control in Paltalk's window (type, name, automation id)
    to a file, for finding the mic and chat-input controls in a new client."""
    window = main_window()
    if window is None:
        path.write_text("Paltalk window not found\n", encoding="utf-8")
        return
    lines = []
    for e in window.descendants():
        info = e.element_info
        lines.append(f"{info.control_type}\t{info.name!r}\t{info.automation_id}")
    path.write_text("\n".join(lines), encoding="utf-8")


class RoomWriter:
    """Mic and chat in the room. Only in a room the relay is allowed to speak
    in; the agent never builds one in listen-only mode."""

    MIC_NAMES = ("Talk", "Push to Talk", "Mic", "Microphone", "Lock Mic", "Hold Mic")

    def _panel(self):
        window = main_window()
        return room_panel(window) if window else None

    def mic_button(self):
        panel = self._panel()
        if panel is None:
            return None
        for e in panel.descendants(control_type="Button"):
            name = (e.element_info.name or "").strip()
            if any(name.lower() == n.lower() for n in self.MIC_NAMES) or "talk" in (e.element_info.automation_id or "").lower():
                return e
        return None

    def press_mic(self) -> bool:
        button = self.mic_button()
        if button is None:
            return False
        try:
            button.invoke()
            return True
        except Exception:  # noqa: BLE001
            return False

    def send_chat(self, text: str) -> bool:
        """Types into the room's message box ("Send message") and sends, then
        confirms the line appeared in the chat log. A private room hides its
        chat until "Toggle Chat Visibility" is pressed. Proven 2026-11-06 in
        the simulation room: focus the box, type, Enter (setting the text
        through accessibility did not send)."""
        panel = self._panel()
        if panel is None:
            return False
        try:
            def box_of():
                return next((e for e in panel.descendants(control_type="Edit")
                             if (e.element_info.name or "") == "Send message"
                             or "RoomEditMessageWidget" in (e.element_info.automation_id or "")), None)
            box = box_of()
            if box is None:
                show = next((b for b in panel.descendants(control_type="Button")
                             if (b.element_info.name or "") == "Toggle Chat Visibility"), None)
                if show is not None:
                    show.invoke()
                    time.sleep(2)
                    box = box_of()
            if box is None:
                return False
            box.set_focus()
            box.type_keys(text, with_spaces=True, set_foreground=True)
            time.sleep(0.3)
            box.type_keys("{ENTER}", set_foreground=True)
            time.sleep(1.5)
            return any(t == text for _, t in chat_messages()[-5:])
        except Exception:  # noqa: BLE001
            return False


# MARK: - One look per round (since 2026-11-06)
#
# The relay used to walk Paltalk's accessibility tree five or six times every
# two seconds, and any error in a walk read as "not in the room". On
# 6 November that sent the dua in the middle of the Zikr. Now the window is
# walked once per round with its properties fetched in the same call, and a
# failed read is "unknown" - which never counts as leaving the room.


def _aid(element) -> str:
    try:
        return element.element_info.automation_id or ""
    except Exception:  # noqa: BLE001 - a control that just went away
        return ""


def _name(element) -> str:
    try:
        return element.element_info.name or ""
    except Exception:  # noqa: BLE001
        return ""


def _kind(element) -> str:
    try:
        return element.element_info.control_type or ""
    except Exception:  # noqa: BLE001
        return ""


class View:
    """Paltalk's main window as read in one walk."""

    def __init__(self) -> None:
        self.window = None
        self.elements: list = []
        self.ok = False
        self.error = ""
        self.seconds = 0.0

    def first(self, suffix: str = "", name: str = "", kind: str = "", contains: str = ""):
        for element in self.elements:
            if suffix and not _aid(element).endswith(suffix):
                continue
            if contains and contains not in _aid(element):
                continue
            if name and _name(element) != name:
                continue
            if kind and _kind(element) != kind:
                continue
            return element
        return None

    def all(self, suffix: str = "", contains: str = "", kind: str = "") -> list:
        return [e for e in self.elements
                if (not suffix or _aid(e).endswith(suffix)) and (not contains or contains in _aid(e))
                and (not kind or _kind(e) == kind)]


def look() -> View:
    """One walk of Paltalk's main window, its properties cached in the walk."""
    view = View()
    started = time.time()
    try:
        view.window = main_window()
    except Exception as error:  # noqa: BLE001
        view.error = f"window: {error!r}"[:120]
        return view
    if view.window is None:
        view.error = "no Paltalk window"
        return view
    try:
        try:
            view.elements = view.window.descendants(cache_enable=True)
        except TypeError:
            view.elements = view.window.descendants()
        view.ok = True
    except Exception as error:  # noqa: BLE001 - the UI changed under the walk
        view.error = f"walk: {error!r}"[:120]
    view.seconds = time.time() - started
    return view


def room_status(view: View, markers: list[str], room: str = "") -> tuple[str, str]:
    """("in", text) in the room; ("closed", why) when Paltalk says the room is
    not open; ("out", why) when no room is open at all; ("unknown", why) when
    the window could not be read - which says nothing about the room."""
    if not view.ok:
        return "unknown", view.error or "window not read"
    overlay = view.first(suffix="JoinRoomFailedMessageOverlayWidget")
    if overlay is not None:
        try:
            showing = overlay.is_visible()
        except Exception:  # noqa: BLE001
            showing = False
        if showing:
            try:
                button = next(iter(overlay.descendants(control_type="Button")), None)
                if button is not None:
                    button.invoke()
                    log("the room is not open: closed its tab")
            except Exception:  # noqa: BLE001 - the next round tries again
                pass
            return "closed", "Paltalk says the room is not open"
    panel = view.first(suffix="ui::rooms::RoomWidget")
    tab = view.first(contains=".RoomItem_", kind="Group")
    if room and tab is not None:
        # Active Rooms names each open room ("RoomItem_<name>"): another room
        # open on the relay's Paltalk is not ours - close it.
        tabs = view.all(contains=".RoomItem_", kind="Group")
        ours = [t for t in tabs if _aid(t).endswith(f"RoomItem_{room}")]
        if not ours:
            names = [_aid(t).rsplit("RoomItem_", 1)[-1] for t in tabs]
            for close in view.all(kind="Button"):
                if _name(close).startswith("RoomItem_") and _name(close).endswith("_CloseButton"):
                    try:
                        close.invoke()
                        log(f"closed another room's tab ({_name(close)[9:-12]})")
                    except Exception:  # noqa: BLE001
                        pass
            return "out", f"another room is open ({', '.join(names)[:80]}), not {room!r}"
    if panel is None:
        if tab is not None:
            # Joined, but another page (home, settings) is in front.
            return "unknown", "the room's tab is open but not shown"
        return "out", "no room open in Paltalk"
    wanted = [m.lower() for m in markers if m]
    if not wanted:
        return "in", "room open"
    for element in view.elements:
        if "RoomWidget" in _aid(element) and _kind(element) == "Text":
            text = _name(element)
            if any(m in text.lower() for m in wanted):
                return "in", text
    return "unknown", "a room is open but its topic does not match"


def room_tab_open(view: View) -> bool:
    """A room is listed under Active Rooms (joined, or its tab still open)."""
    return view.ok and (view.first(contains=".RoomItem_", kind="Group") is not None
                        or view.first(suffix="ui::rooms::RoomWidget") is not None)


def speaker_icon(view: View):
    """The room's speaker icon under Active Rooms, or None."""
    for element in view.all(contains=".RoomItem_", kind="Image"):
        if _aid(element).endswith(".QLabel"):
            return element
    return None


def speaker_on(view: View) -> bool | None:
    """Whether the room's speaker is on, read from its icon under Active
    Rooms: a green speaker when on, a grey crossed one when muted. Paltalk
    exposes the state nowhere else (proven 2026-11-06). None when it cannot
    be told (no icon, or the screen is not being drawn)."""
    return icon_on(speaker_icon(view))


def icon_on(icon) -> bool | None:  # noqa: ANN001
    if icon is None:
        return None
    try:
        from PIL import ImageGrab
        box = icon.rectangle()
        if box.width() < 6 or box.height() < 6:
            return None
        pixels = list(ImageGrab.grab(bbox=(box.left, box.top, box.right, box.bottom)).convert("RGB").getdata())
    except Exception:  # noqa: BLE001 - no screen to read (e.g. a session not drawn)
        return None
    green = sum(1 for r, g, b in pixels if g > r + 40 and g > b + 20)
    if green >= 8:
        return True
    # A drawn icon has edges; a flat area means nothing is drawn there.
    if max(sum(p) for p in pixels) - min(sum(p) for p in pixels) < 60:
        return None
    return False


def leave_room(view: View, room: str) -> bool:
    """Closes the room's tab under Active Rooms (its RoomItem close button)."""
    for button in view.all(kind="Button"):
        name = _name(button)
        if name.startswith("RoomItem_") and name.endswith("_CloseButton") and (not room or name == f"RoomItem_{room}_CloseButton"):
            try:
                button.invoke()
                return True
            except Exception:  # noqa: BLE001
                return False
    return False


def press_speaker(view: View) -> bool:
    button = view.first(name="Toggle Speaker", kind="Button")
    if button is None:
        return False
    try:
        button.invoke()
        return True
    except Exception:  # noqa: BLE001
        return False


def close_popups_in(view: View) -> bool:
    closed = False
    for button in view.all(contains="ui::vog::LayeredWidget", kind="Button"):
        if "close" in _name(button).lower():
            try:
                button.invoke()
                closed = True
            except Exception:  # noqa: BLE001
                pass
    if closed:
        log("closed a Paltalk pop-up")
    return closed


def signed_in_view(view: View) -> bool:
    return view.ok and any(any(key in _aid(e) for key in ("LeftPanelWidget", "ROOM_BROWSER_WIDGET", "RoomWidget"))
                           for e in view.elements)


def messages_in(view: View) -> list[tuple[str, str, str]]:
    """(key, sender, text) for each chat message on screen, top to bottom.
    The key is the message's own accessibility id while Paltalk keeps it, so
    a redraw that shows the same messages again is not read as new ones."""
    items = view.all(suffix="ui::chatlog::TextMessageWidget")
    found = []
    try:
        items.sort(key=lambda i: i.rectangle().top)
    except Exception:  # noqa: BLE001
        pass
    previous = ""
    for item in items:
        sender = text = ""
        try:
            for part in item.descendants():
                kind = _aid(part).rsplit(".", 1)[-1]
                if kind == "QLabel" and not sender:
                    sender = part.window_text() or ""
                elif kind == "QTextBrowser":
                    try:
                        text = part.iface_text.DocumentRange.GetText(-1) or ""
                    except Exception:  # noqa: BLE001
                        text = part.window_text() or ""
            key = ".".join(str(n) for n in (item.element_info.runtime_id or ()))
        except Exception:  # noqa: BLE001 - scrolled away while being read
            continue
        sender = sender.strip() or previous
        previous = sender
        if sender and text.strip():
            found.append((key, sender, text.strip()))
    return found


class MessageFollower:
    """Messages that appeared since the last read, each given once: by its
    on-screen identity, and by its words for the same sender within a few
    minutes (Paltalk can rebuild the chat with new identities)."""

    def __init__(self) -> None:
        self.keys: set[str] = set()
        self.words: dict[tuple[str, str], float] = {}
        self.primed = False

    def new(self, view: View) -> list[tuple[str, str]]:
        now = time.time()
        current = messages_in(view)
        fresh = []
        for key, sender, text in current:
            words = (sender.lower(), " ".join(text.lower().split()))
            if key in self.keys:
                continue
            self.keys.add(key)
            seen = self.words.get(words)
            self.words[words] = now
            if not self.primed or (seen is not None and now - seen < 600):
                continue
            fresh.append((sender, text))
        self.primed = True
        if len(self.keys) > 5000:
            self.keys = {key for key, _, _ in current}
        self.words = {w: t for w, t in self.words.items() if now - t < 900}
        return fresh


def _foreground_is_paltalk() -> bool:
    from ctypes import wintypes
    window = main_window()
    if window is None:
        return False
    pid = wintypes.DWORD()
    ctypes.windll.user32.GetWindowThreadProcessId(ctypes.windll.user32.GetForegroundWindow(), ctypes.byref(pid))
    return pid.value == window.process_id()
