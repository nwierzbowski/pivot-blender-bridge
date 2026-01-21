"""Simple TimerManager utility used to start/stop timers by name.

Usage:
    from pivot_lib.timer_manager import timers
    timers.start("standardize")
    ...
    timers.stop("standardize")
    print(timers.get_elapsed_ms("standardize"))

Also provides `timeblock(name)` context manager and `wrap(name)` decorator.
"""
from __future__ import annotations

import time
from contextlib import contextmanager
from threading import Lock
from typing import Dict, Optional


class TimerRecord:
    def __init__(self) -> None:
        self.start: Optional[float] = None
        self.elapsed: float = 0.0
        self.running: bool = False


class TimerManager:
    def __init__(self) -> None:
        self._timers: Dict[str, TimerRecord] = {}
        self._lock = Lock()

    def start(self, name: str) -> None:
        with self._lock:
            rec = self._timers.get(name)
            if rec is None:
                rec = TimerRecord()
                self._timers[name] = rec
            if not rec.running:
                rec.start = time.perf_counter()
                rec.running = True

    def stop(self, name: str) -> Optional[float]:
        """Stop the named timer and return elapsed seconds, or None if not running."""
        with self._lock:
            rec = self._timers.get(name)
            if rec is None or not rec.running or rec.start is None:
                return None
            delta = time.perf_counter() - rec.start
            rec.elapsed += delta
            rec.start = None
            rec.running = False
            return rec.elapsed * 1000.0  # return milliseconds

    def reset(self, name: str) -> None:
        with self._lock:
            self._timers[name] = TimerRecord()

    def get_elapsed(self, name: str) -> Optional[float]:
        """Return total elapsed seconds for `name` (includes accumulated time)."""
        with self._lock:
            rec = self._timers.get(name)
            if rec is None:
                return None
            total = rec.elapsed
            if rec.running and rec.start is not None:
                total += time.perf_counter() - rec.start
            return total

    def get_elapsed_ms(self, name: str) -> Optional[float]:
        secs = self.get_elapsed(name)
        return None if secs is None else secs * 1000.0

    @contextmanager
    def timeblock(self, name: str):
        try:
            self.start(name)
            yield
        finally:
            self.stop(name)

    def wrap(self, name: str):
        """Decorator to time a function into a named timer."""
        def decorator(func):
            def wrapper(*args, **kwargs):
                self.start(name)
                try:
                    return func(*args, **kwargs)
                finally:
                    self.stop(name)
            return wrapper
        return decorator


# module-level singleton for convenience
timers = TimerManager()

__all__ = ["TimerManager", "timers"]
