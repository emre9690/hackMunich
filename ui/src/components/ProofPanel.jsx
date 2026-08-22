import { useEffect, useState } from "react";
import CodePanel from "./CodePanel";
import { apiUrl, exportChipZipUrl } from "../lib/api";

function lastMatching(events, pred) {
  for (let i = events.length - 1; i >= 0; i--) {
    if (pred(events[i])) return events[i];
  }
  return null;
}

// Same "ignore drafter events" rule as the schematic panel -- a chip isn't
// really exportable (no rtl/ yet) until the RTL pipeline has touched it.
function currentChipBranch(events) {
  for (let i = events.length - 1; i >= 0; i--) {
    const e = events[i];
    if (e.chip && e.branch && e.agent !== "drafter") return { chip: e.chip, branch: e.branch };
  }
  return null;
}

function TickingCount({ value }) {
  const [display, setDisplay] = useState(0);
  useEffect(() => {
    if (value == null) return;
    let raf;
    const start = display;
    const startTime = performance.now();
    const duration = 400;
    const step = (now) => {
      const t = Math.min(1, (now - startTime) / duration);
      setDisplay(Math.round(start + (value - start) * t));
      if (t < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);
  return <>{display}</>;
}

export default function ProofPanel({ events }) {
  const verifyEvent = lastMatching(events, (e) => e.stage === "verify" && e.total != null);
  const synthEvent = lastMatching(events, (e) => e.stage === "synthesize");
  const [synthReport, setSynthReport] = useState(null);

  useEffect(() => {
    if (!synthEvent?.artifact_path) {
      setSynthReport(null);
      return;
    }
    fetch(apiUrl(`/api/artifact?path=${encodeURIComponent(synthEvent.artifact_path)}`))
      .then((r) => (r.ok ? r.text() : null))
      .then(setSynthReport)
      .catch(() => setSynthReport(null));
  }, [synthEvent?.artifact_path]);

  const pct = verifyEvent && verifyEvent.total ? (verifyEvent.passed / verifyEvent.total) * 100 : 0;
  const chipBranch = currentChipBranch(events);

  return (
    <div className="proof-panel">
      <div className="proof-panel-header">
        <h3>Proof</h3>
        {chipBranch && (
          <a
            className="proof-export-btn"
            href={exportChipZipUrl(chipBranch.chip, chipBranch.branch)}
            download
          >
            ⬇ Export project (.zip)
          </a>
        )}
      </div>

      <div className="proof-section">
        <div className="proof-section-title">Exhaustive vector verification</div>
        {verifyEvent ? (
          <>
            <div className="proof-vectors">
              <span className={`proof-count status-${verifyEvent.status}`}>
                <TickingCount value={verifyEvent.passed} />
              </span>
              <span className="proof-count-sep">/</span>
              <span className="proof-count-total">{verifyEvent.total}</span>
              <span className="proof-count-label">vectors passed</span>
            </div>
            <div className="proof-bar">
              <div
                className={`proof-bar-fill status-${verifyEvent.status}`}
                style={{ width: `${pct}%` }}
              />
            </div>
          </>
        ) : (
          <div className="proof-empty">No verification run yet</div>
        )}
      </div>

      <div className="proof-section">
        <div className="proof-section-title">Live code</div>
        <CodePanel events={events} />
      </div>

      <div className="proof-section">
        <div className="proof-section-title">FPGA synthesis (Yosys)</div>
        {synthEvent ? (
          <>
            <div className="proof-synth-summary">{synthEvent.detail}</div>
            {synthReport && (
              <pre className="proof-synth-report">{extractStatBlock(synthReport)}</pre>
            )}
          </>
        ) : (
          <div className="proof-empty">Not synthesized yet</div>
        )}
      </div>
    </div>
  );
}

function extractStatBlock(report) {
  const lines = report.split("\n");
  const idx = lines.map((l, i) => (l.trim().endsWith("cells") ? i : -1)).filter((i) => i >= 0);
  if (idx.length === 0) return report.slice(-800);
  const last = idx[idx.length - 1];
  return lines.slice(Math.max(0, last - 6), last + 4).join("\n");
}
