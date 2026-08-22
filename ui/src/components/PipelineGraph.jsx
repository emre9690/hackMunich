const NODES = [
  { id: "coder", label: "Coder", agent: "coder", sub: "writes RTL" },
  { id: "harness1", label: "Harness", agent: "harness", gate: true, sub: "verifies" },
  { id: "testbencher", label: "Testbencher", agent: "testbencher", sub: "coverage" },
  { id: "style", label: "Style", agent: "style", sub: "cleanup" },
  { id: "synth", label: "Synth", agent: "synth", sub: "FPGA gates" },
];

function latestByAgent(events) {
  const map = {};
  for (const e of events) {
    map[e.agent] = e;
  }
  return map;
}

// A small top-down IC silhouette (body + pin-1 notch) used as each station's
// icon, so the pipeline itself looks like it belongs to a chip tool rather
// than a generic status-card row. The glyph inside communicates status
// without relying on color alone.
function StationIcon({ status }) {
  return (
    <svg viewBox="0 0 40 40" className="station-icon" aria-hidden="true">
      <rect x="4" y="4" width="32" height="32" rx="5" className="station-icon-body" />
      <path d="M 15 4 a 5 5 0 0 0 10 0" className="station-icon-notch" />
      {status === "pass" && (
        <path d="M13 20.5 L18 26 L27 15" className="station-icon-glyph station-icon-check" />
      )}
      {(status === "fail" || status === "error") && (
        <g className="station-icon-glyph station-icon-x">
          <path d="M14 14 L26 26" />
          <path d="M26 14 L14 26" />
        </g>
      )}
      {status === "running" && (
        <circle cx="20" cy="20" r="9" className="station-icon-spinner" />
      )}
      {status === "stalled" && (
        <g className="station-icon-glyph station-icon-stalled">
          <circle cx="20" cy="20" r="9" />
          <path d="M20 15v6l4 3" />
        </g>
      )}
      {status === "skipped" && (
        <g className="station-icon-glyph station-icon-skip">
          <path d="M14 14 L18 20 L14 26" />
          <path d="M22 14 L26 20 L22 26" />
        </g>
      )}
    </svg>
  );
}

export default function PipelineGraph({ events, starting = false }) {
  const latest = latestByAgent(events);
  const lastEvent = events[events.length - 1];
  const activeAgent = lastEvent?.agent;

  const stationStatus = NODES.map((node) => {
    const event = latest[node.agent];
    const isStarting = node.id === "coder" && starting && !event;
    return {
      node,
      event,
      isStarting,
      status: isStarting ? "running" : event?.status ?? "idle",
    };
  });

  // How far along the rail is "lit" -- up to and including the furthest
  // station that has actually started (idle stations ahead stay unlit).
  let litCount = 0;
  stationStatus.forEach((s, i) => {
    if (s.status !== "idle") litCount = i + 1;
  });
  const railPercent = NODES.length > 1 ? (litCount - 1) / (NODES.length - 1) * 100 : 0;

  return (
    <div className="pipeline-rail-wrap">
      <div className="pipeline-rail" />
      <div
        className="pipeline-rail-lit"
        style={{ width: `${Math.max(0, railPercent)}%` }}
      />
      <div className="pipeline-stations" style={{ "--station-count": NODES.length }}>
        {stationStatus.map(({ node, event, isStarting, status }, i) => {
          const isActive = isStarting || node.agent === activeAgent;
          return (
            <div className="pipeline-station" key={node.id}>
              <div
                className={`pipeline-chip status-${status} ${isActive ? "pipeline-chip-active" : ""} ${
                  node.gate ? "pipeline-chip-gate" : ""
                }`}
                title={event?.detail ?? (isStarting ? "starting up…" : "no events yet")}
              >
                <StationIcon status={status} />
              </div>
              {node.gate && <div className="pipeline-station-gate-tag">GATE</div>}
              <div className="pipeline-station-index">{String(i + 1).padStart(2, "0")}</div>
              <div className="pipeline-station-label">{node.label}</div>
              <div className="pipeline-station-sub">{node.sub}</div>
              <div className={`pipeline-station-status status-${status}`}>
                {isStarting ? "starting…" : status === "skipped" ? "skipped (fast demo)" : status}
              </div>
              {event?.total != null && (
                <div className="pipeline-station-count">
                  {event.passed}/{event.total}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
