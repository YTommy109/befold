from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, FileSystemEvent
from backend.services.event_bus import EventBus, event_bus as _default_bus


class _ChangeHandler(FileSystemEventHandler):
    def __init__(self, target: Path, bus: EventBus) -> None:
        self._target = target
        self._bus = bus

    def on_modified(self, event: FileSystemEvent) -> None:
        if Path(event.src_path) == self._target:
            self._bus.notify()


class WatchService:
    def __init__(self, event_bus: EventBus | None = None) -> None:
        self._bus = event_bus or _default_bus
        self._observer: Observer | None = None
        self._path: Path | None = None

    def set_file(self, path: str) -> None:
        self.stop()
        self._path = Path(path)
        observer = Observer()
        handler = _ChangeHandler(self._path, self._bus)
        observer.schedule(handler, str(self._path.parent), recursive=False)
        observer.start()
        self._observer = observer

    def get_content(self) -> str | None:
        if self._path is None or not self._path.exists():
            return None
        return self._path.read_text(encoding="utf-8")

    def get_path(self) -> Path | None:
        return self._path

    def stop(self) -> None:
        if self._observer is not None:
            self._observer.stop()
            self._observer.join()
            self._observer = None


watch_service = WatchService()
