"""Hard ceilings enforced before any real Devin session is created (brief §4).

These are safety guardrails against a runaway loop burning the token/ACU
budget -- they are not stage gates and are never relaxed by the caller.
"""
from __future__ import annotations

import threading
from dataclasses import dataclass, field

MAX_ATTEMPTS_PER_CHIP = 6
SESSION_WALLCLOCK_TIMEOUT_SECONDS = 15 * 60
MAX_CONCURRENT_SESSIONS = 4
MAX_TOTAL_SESSIONS_PER_RUN = 20


class SessionBudgetExceeded(RuntimeError):
    pass


@dataclass
class SessionBudget:
    """Tracks session counts for one orchestrator run; refuses to exceed caps.

    Thread-safe and blocking on the concurrency cap (Stage 6 runs multiple
    attempt pipelines in parallel threads that all share one budget): a
    caller past max_concurrent waits for a slot rather than erroring, but
    the lifetime max_total cap is a hard refusal, never waited out.
    """

    max_concurrent: int = MAX_CONCURRENT_SESSIONS
    max_total: int = MAX_TOTAL_SESSIONS_PER_RUN
    _active: int = field(default=0, init=False)
    _total_created: int = field(default=0, init=False)
    _cv: threading.Condition = field(default_factory=lambda: threading.Condition(), init=False)

    def can_start(self) -> bool:
        with self._cv:
            return self._active < self.max_concurrent and self._total_created < self.max_total

    def acquire(self) -> None:
        with self._cv:
            while True:
                if self._total_created >= self.max_total:
                    raise SessionBudgetExceeded(
                        f"session budget exceeded: total={self._total_created}/{self.max_total} "
                        "lifetime sessions for this run"
                    )
                if self._active < self.max_concurrent:
                    self._active += 1
                    self._total_created += 1
                    return
                self._cv.wait()

    def release(self) -> None:
        with self._cv:
            self._active = max(0, self._active - 1)
            self._cv.notify_all()

    @property
    def total_created(self) -> int:
        with self._cv:
            return self._total_created

    @property
    def active(self) -> int:
        with self._cv:
            return self._active
