import { useEffect, useRef } from "react";

const MAX_LINES = 150;

// Chronological transcript of every 'running' event -- includes our own
// "creating session" / "polling" lines plus Devin's own narrated progress
// messages, surfaced purely for visibility. This is never how pass/fail is
// decided (that stays the harness's job); it's just watching it happen.
export default function ActivityFeed({ events }) {
  const bottomRef = useRef(null);
  const lines = events.filter((e) => e.status === "running").slice(-MAX_LINES);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: "end" });
  }, [lines.length]);

  return (
    <div className="activity-feed">
      <h3>Live Activity</h3>
      <div className="activity-feed-scroll">
        {lines.length === 0 && <div className="agent-status-empty">No activity yet</div>}
        {lines.map((e, i) => (
          <div className="activity-line" key={i}>
            <span className="activity-time">{formatTime(e.ts)}</span>
            <span className="activity-agent">{e.agent}</span>
            <span className="activity-text">{e.detail}</span>
          </div>
        ))}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}

function formatTime(ts) {
  if (!ts) return "";
  const d = new Date(ts);
  return d.toLocaleTimeString([], { hour12: false });
}
