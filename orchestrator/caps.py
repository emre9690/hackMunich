"""Hard ceilings enforced before any real Devin session is created (brief §4).

These are safety guardrails against a runaway loop burning the token/ACU
budget -- they are not stage gates and are never relaxed by the caller.
"""
from __future__ import annotations

from dataclasses import dataclass, field

MAX_ATTEMPTS_PER_CHIP = 6
SESSION_WALLCLOCK_TIMEOUT_SECONDS = 15 * 60
MAX_CONCURRENT_SESSIONS = 4
MAX_TOTAL_SESSIONS_PER_RUN = 20


class SessionBudgetExceeded(RuntimeError):
    pass


@dataclass
class SessionBudget:
    """Tracks session counts for one orchestrator run; refuses to exceed caps."""

    max_concurrent: int = MAX_CONCURRENT_SESSIONS
    max_total: int = MAX_TOTAL_SESSIONS_PER_RUN
    _active: int = field(default=0, init=False)
    _total_created: int = field(default=0, init=False)

    def can_start(self) -> bool:
        return self._active < self.max_concurrent and self._total_created < self.max_total

    def acquire(self) -> None:
        if not self.can_start():
            raise SessionBudgetExceeded(
                f"session budget exceeded: active={self._active}/{self.max_concurrent} "
                f"total={self._total_created}/{self.max_total}"
            )
        self._active += 1
        self._total_created += 1

    def release(self) -> None:
        self._active = max(0, self._active - 1)

    @property
    def total_created(self) -> int:
        return self._total_created

    @property
    def active(self) -> int:
        return self._active
