const NODES = [
  { id: "coder", label: "Coder", agent: "coder" },
  { id: "harness1", label: "Harness", agent: "harness", gate: true },
  { id: "testbencher", label: "Testbencher", agent: "testbencher" },
  { id: "style", label: "Style", agent: "style" },
  { id: "synth", label: "Synth", agent: "synth" },
];

const STATUS_COLOR = {
  idle: "#475569",
  running: "#3b82f6",
  pass: "#22c55e",
  fail: "#ef4444",
  stalled: "#f59e0b",
  error: "#ef4444",
};

function latestByAgent(events) {
  const map = {};
  for (const e of events) {
    map[e.agent] = e;
  }
  return map;
}

export default function PipelineGraph({ events }) {
  const latest = latestByAgent(events);
  const lastEvent = events[events.length - 1];
  const activeAgent = lastEvent?.agent;

  return (
    <div className="pipeline-graph">
      {NODES.map((node, i) => {
        const event = latest[node.agent];
        const status = event?.status ?? "idle";
        const color = STATUS_COLOR[status] ?? STATUS_COLOR.idle;
        const isActive = node.agent === activeAgent;

        return (
          <div className="pipeline-node-wrap" key={node.id}>
            {i > 0 && (
              <div className={`pipeline-edge ${isActive ? "pipeline-edge-active" : ""}`}>
                <div className="pipeline-edge-line" />
                {isActive && <div className="pipeline-edge-pulse" />}
              </div>
            )}
            <div
              className={`pipeline-node ${node.gate ? "pipeline-node-gate" : ""} ${
                status === "running" ? "pipeline-node-running" : ""
              }`}
              style={{ "--node-color": color }}
              title={event?.detail ?? "no events yet"}
            >
              <div className="pipeline-node-dot" />
              <div className="pipeline-node-label">{node.label}</div>
              <div className="pipeline-node-status">{status}</div>
              {event?.total != null && (
                <div className="pipeline-node-count">
                  {event.passed}/{event.total}
                </div>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}
