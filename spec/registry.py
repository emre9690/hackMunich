"""Maps a chip id to its golden model + metadata.

HUMAN-OWNED. Chip golden models live under spec/chips/ and are loaded here
by chip id. No Devin writes to anything under /spec/.
"""
from __future__ import annotations

import importlib
from dataclasses import dataclass
from typing import Callable, Iterator

# Chip filenames (74138, 82s100) start with a digit, so they aren't valid
# Python identifiers and can't be reached with a literal `import` statement.
# importlib.import_module works fine with such dotted names.
_KNOWN_CHIP_IDS = ("ski", )


@dataclass(frozen=True)
class Port:
    name: str
    width: int = 1  # bit width; this MVP only uses 1-bit signals


@dataclass(frozen=True)
class ChipSpec:
    chip_id: str
    module_name: str  # expected Verilog module name, e.g. "decoder_74138"
    inputs: list[Port]
    outputs: list[Port]
    golden_fn: Callable[[dict[str, int]], dict[str, int]]

    @property
    def input_bits(self) -> int:
        return sum(p.width for p in self.inputs)

    @property
    def vector_count(self) -> int:
        return 2 ** self.input_bits

    def iter_vectors(self) -> Iterator[tuple[dict[str, int], dict[str, int]]]:
        """Exhaustively yield (input_map, expected_output_map) for every combination."""
        names = [p.name for p in self.inputs]
        n = len(names)
        for combo in range(2 ** n):
            bits = [(combo >> (n - 1 - i)) & 1 for i in range(n)]
            in_map = dict(zip(names, bits))
            out_map = self.golden_fn(in_map)
            yield in_map, out_map


def load_chip(chip_id: str) -> ChipSpec:
    if chip_id not in _KNOWN_CHIP_IDS:
        raise ValueError(f"unknown chip id {chip_id!r}, known: {_KNOWN_CHIP_IDS}")
    module = importlib.import_module(f"spec.chips.{chip_id}")
    return module.SPEC


def available_chips() -> tuple[str, ...]:
    return _KNOWN_CHIP_IDS
