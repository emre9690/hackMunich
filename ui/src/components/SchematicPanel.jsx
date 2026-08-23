import { useEffect, useState } from "react";
import { fetchChipPorts, fetchChipSampleVectors } from "../lib/api";

const PIN_GAP = 26;
const BODY_PAD_Y = 20;
const BODY_WIDTH = 150;
const STUB_LEN = 34;
const LABEL_MAX = 64;
const TABLE_ROW_COUNT = 8;

// "drafter" events fire for a chip long before it's ever approved/
// registered (the whole datasheet-drafting + human-review window) -- if the
// schematic followed those, it would 404 against /api/chips/*/ports for
// the entire drafting phase, which reads as a bug rather than the expected
// "not registered yet" state. Only RTL-pipeline agents count as "current."
function currentChip(events) {
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].chip && events[i].agent !== "drafter") return events[i].chip;
  }
  return null;
}

// "running" while any agent is actively working, "verified" once the most
// recent harness verify event for THIS chip passed, "failed" if it didn't,
// "idle" before anything has happened yet.
function schematicStatus(events, chipId) {
  const relevant = events.filter((e) => e.chip === chipId);
  if (!relevant.length) return "idle";
  const last = relevant[relevant.length - 1];
  if (last.status === "running") return "running";
  for (let i = relevant.length - 1; i >= 0; i--) {
    const e = relevant[i];
    if (e.agent === "harness" && e.stage === "verify") {
      return e.status === "pass" ? "verified" : "failed";
    }
  }
  return last.status === "pass" ? "running" : last.status;
}

export default function SchematicPanel({ events }) {
  const chipId = currentChip(events);
  const [ports, setPorts] = useState(null);
  const [error, setError] = useState(null);
  // Real (input, output) rows from the golden model -- a static reference
  // table, not an animation. Best-effort: if this fails to load, the
  // pinout diagram still renders fine without it.
  const [sampleRows, setSampleRows] = useState(null);

  useEffect(() => {
    if (!chipId) {
      setPorts(null);
      setSampleRows(null);
      return;
    }
    setError(null);
    setSampleRows(null);
    fetchChipPorts(chipId)
      .then(setPorts)
      .catch((e) => setError(String(e)));
    fetchChipSampleVectors(chipId, TABLE_ROW_COUNT)
      .then((d) => setSampleRows(d.rows))
      .catch(() => setSampleRows(null));
  }, [chipId]);

  if (!chipId) {
    return (
      <div className="schematic-panel schematic-idle">
        <div className="proof-empty">Hardware view appears once a chip is selected</div>
      </div>
    );
  }
  if (error) {
    return (
      <div className="schematic-panel schematic-idle">
        <div className="proof-empty">Could not load pinout ({error})</div>
      </div>
    );
  }
  if (!ports) {
    return (
      <div className="schematic-panel schematic-idle">
        <div className="proof-empty">Loading pinout…</div>
      </div>
    );
  }

  const status = schematicStatus(events, chipId);
  const rows = Math.max(ports.inputs.length, ports.outputs.length, 1);
  const bodyHeight = rows * PIN_GAP + BODY_PAD_Y * 2;
  const width = BODY_WIDTH + STUB_LEN * 2 + LABEL_MAX * 2;
  const bodyX = STUB_LEN + LABEL_MAX;
  const bodyY = 0;
  const centerY = bodyHeight / 2;

  const pinY = (i, count) => bodyY + BODY_PAD_Y + (bodyHeight - BODY_PAD_Y * 2) * (count === 1 ? 0.5 : i / (count - 1));
  const columns = [...ports.inputs, ...ports.outputs];

  // Module names vary a lot in length (decoder_74138 vs
  // BCD_TO_7SEG_SN5446A) -- scale the font down for longer names instead
  // of a single fixed size, so it always fits inside the fixed-width chip
  // body rather than overflowing past its edges.
  const partName = ports.module_name || chipId;
  const partFontSize = Math.min(13, Math.max(7, (BODY_WIDTH - 16) / (partName.length * 0.62)));

  return (
    <div className={`schematic-panel schematic-${status}`}>
      <svg
        viewBox={`0 0 ${width} ${bodyHeight}`}
        width="100%"
        height={Math.min(bodyHeight, 360)}
        preserveAspectRatio="xMidYMid meet"
      >
        {/* Trace lines only span the actual stub (fixed STUB_LEN), never the
            label region -- labels sit in the open space past the stub with
            a clean gap, so a long name (e.g. RBO_n) can never end up
            visually overlapping the dashed line. */}
        {ports.inputs.map((name, i) => {
          const y = pinY(i, ports.inputs.length);
          const stubStart = bodyX - STUB_LEN;
          return (
            <g key={`in-${name}`} className="schematic-pin" style={{ animationDelay: `${i * 90}ms` }}>
              <line x1={stubStart} y1={y} x2={bodyX} y2={y} className="schematic-trace" />
              <circle cx={bodyX} cy={y} r={2.5} className="schematic-pad" />
              <text x={stubStart - 6} y={y - 4} textAnchor="end" className="schematic-label">
                {name}
              </text>
            </g>
          );
        })}

        {ports.outputs.map((name, i) => {
          const y = pinY(i, ports.outputs.length);
          const pinEdge = bodyX + BODY_WIDTH;
          const stubEnd = pinEdge + STUB_LEN;
          return (
            <g key={`out-${name}`} className="schematic-pin" style={{ animationDelay: `${i * 90 + 120}ms` }}>
              <line x1={pinEdge} y1={y} x2={stubEnd} y2={y} className="schematic-trace" />
              <circle cx={pinEdge} cy={y} r={2.5} className="schematic-pad" />
              <text x={stubEnd + 6} y={y - 4} textAnchor="start" className="schematic-label">
                {name}
              </text>
            </g>
          );
        })}

        <rect
          x={bodyX}
          y={bodyY}
          width={BODY_WIDTH}
          height={bodyHeight}
          rx={6}
          className="schematic-body"
        />
        <path
          d={`M ${bodyX + BODY_WIDTH / 2 - 9} ${bodyY} a 9 9 0 0 0 18 0`}
          className="schematic-notch"
        />
        <text
          x={bodyX + BODY_WIDTH / 2}
          y={centerY - 2}
          textAnchor="middle"
          className="schematic-part"
          style={{ fontSize: partFontSize }}
        >
          {partName}
        </text>
        <text x={bodyX + BODY_WIDTH / 2} y={centerY + 14} textAnchor="middle" className="schematic-part-sub">
          {status === "verified" ? "VERIFIED" : status === "failed" ? "FAILING" : status === "running" ? "SYNTHESIZING…" : "IDLE"}
        </text>
      </svg>

      {sampleRows && (
        <div className="schematic-table-wrap">
          <div className="schematic-table-title">Truth table (sample)</div>
          <div className="draft-table-wrap">
            <table className="draft-table">
              <thead>
                <tr>
                  {columns.map((c) => (
                    <th key={c}>{c}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {sampleRows.map((row, i) => (
                  <tr key={i}>
                    {columns.map((c) => (
                      <td key={c}>{row[c]}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
