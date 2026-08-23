const STATUS_LABEL = {
  running: "RUNNING",
  pass: "PASS",
  fail: "FAIL",
  stalled: "STALLED",
  error: "ERROR",
  skipped: "SKIPPED",
};

export default function AgentStatus({ events }) {
  // Most recent event per (agent, stage) pair, newest first.
  const seen = new Set();
  const rows = [];
  for (let i = events.length - 1; i >= 0 && rows.length < 12; i--) {
    const e = events[i];
    const key = `${e.agent}:${e.stage}`;
    if (seen.has(key)) continue;
    seen.add(key);
    rows.push(e);
  }

  return (
    <div className="agent-status">
      <h3>Live Agent Status</h3>
      {rows.length === 0 && <div className="agent-status-empty">No activity yet</div>}
      <div className="agent-status-list">
        {rows.map((e, i) => (
          <div className={`agent-status-row status-${e.status}`} key={i}>
            <div className="agent-status-top">
              <span className="agent-status-agent">{e.agent}</span>
              <span className="agent-status-stage">{e.stage}</span>
              <span className={`agent-status-badge badge-${e.status}`}>
                {STATUS_LABEL[e.status] ?? e.status}
              </span>
            </div>
            <div className="agent-status-detail">{e.detail}</div>
            {e.session_url && (
              <a className="agent-status-link" href={e.session_url} target="_blank" rel="noreferrer">
                view Devin session ↗
              </a>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
