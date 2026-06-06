import asyncio
from pathlib import Path

from backend.services.event_bus import EventBus
from backend.services.watch_service import WatchService


class WindowRegistry:
    def __init__(self) -> None:
        self._entries: dict[str, dict] = {}
        self._loop: asyncio.AbstractEventLoop | None = None

    def set_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        self._loop = loop

    def create(self, window_id: str, file_path: str | None = None) -> None:
        bus = EventBus()
        if self._loop is not None:
            bus.set_loop(self._loop)
        watch = WatchService(event_bus=bus)
        if file_path:
            watch.set_file(file_path)
        self._entries[window_id] = {
            "watch": watch,
            "bus": bus,
            "path": Path(file_path) if file_path else None,
        }

    def get_watch(self, window_id: str) -> WatchService | None:
        entry = self._entries.get(window_id)
        return entry["watch"] if entry else None

    def get_bus(self, window_id: str) -> EventBus | None:
        entry = self._entries.get(window_id)
        return entry["bus"] if entry else None

    def remove(self, window_id: str) -> None:
        entry = self._entries.pop(window_id, None)
        if entry:
            entry["watch"].stop()

    def find_by_path(self, path: str) -> str | None:
        p = Path(path)
        for wid, entry in self._entries.items():
            if entry["path"] == p:
                return wid
        return None

    def set_path(self, window_id: str, path: str) -> None:
        entry = self._entries.get(window_id)
        if entry:
            entry["path"] = Path(path)

    def snapshot(self) -> list[tuple[str, Path | None]]:
        return [(wid, entry["path"]) for wid, entry in self._entries.items()]


window_registry = WindowRegistry()
