// Minimal VCD (Value Change Dump) parser -- just enough to render the
// top-level testbench signals (inputs/outputs of the DUT, not its internals)
// as a step waveform. Real proof artifact from harness/check_vectors.py,
// not synthetic data.

export function parseVcd(text) {
  const lines = text.split("\n");
  const idToName = new Map();
  let depth = 0;
  let headerDone = false;

  const samples = []; // [{ time, values: { name: '0'|'1' } }]
  let current = {};
  let currentTime = 0;
  let haveSample = false;

  const pushSample = () => {
    if (haveSample) {
      samples.push({ time: currentTime, values: { ...current } });
    }
  };

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    if (!headerDone) {
      if (line.startsWith("$scope")) {
        depth += 1;
        continue;
      }
      if (line.startsWith("$upscope")) {
        depth -= 1;
        continue;
      }
      if (line.startsWith("$var")) {
        // $var wire 1 ! A0 $end   (only capture top-level: depth === 1)
        const parts = line.split(/\s+/);
        const [, , , id, name] = parts;
        if (depth === 1) {
          idToName.set(id, name);
        }
        continue;
      }
      if (line.startsWith("$enddefinitions")) {
        headerDone = true;
        continue;
      }
      continue;
    }

    if (line.startsWith("#")) {
      pushSample();
      currentTime = parseInt(line.slice(1), 10);
      haveSample = true;
      continue;
    }

    if (line.startsWith("b") || line.startsWith("B")) {
      // vector change: "b<bits> <id>"
      const spaceIdx = line.indexOf(" ");
      const bits = line.slice(1, spaceIdx);
      const id = line.slice(spaceIdx + 1).trim();
      const name = idToName.get(id);
      if (name) current[name] = bits;
      continue;
    }

    // scalar change: "<0|1|x|z><id>" with no space
    const value = line[0];
    const id = line.slice(1);
    const name = idToName.get(id);
    if (name) current[name] = value;
  }
  pushSample();

  return { signals: [...idToName.values()], samples };
}
