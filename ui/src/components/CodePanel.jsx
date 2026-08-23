import { useEffect, useRef, useState } from "react";
import { fetchBranchFile } from "../lib/api";
import { tokenizeLine } from "../lib/verilogHighlight";

// Lines are actually added to the DOM one at a time (not just CSS-faded in
// all at once) so the panel reads as code landing live, not a file that
// popped in. Total reveal time is capped so a big file doesn't drag.
const MIN_STEP_MS = 18;
const MAX_STEP_MS = 90;
const MAX_REVEAL_MS = 2200;

const AGENT_PATH = {
  coder: (chip) => `rtl/${chip}.v`,
  style: (chip) => `rtl/${chip}.v`,
  testbencher: (chip) => `rtl/${chip}_tb_extra.v`,
};
const CODE_STAGES = new Set(["generate", "coverage", "cleanup"]);

function lastCodeEvent(events) {
  for (let i = events.length - 1; i >= 0; i--) {
    const e = events[i];
    if (e.status === "pass" && CODE_STAGES.has(e.stage) && AGENT_PATH[e.agent]) return e;
  }
  return null;
}

// Shows the ACTUAL committed RTL, fetched straight from the git branch --
// updates live as each agent (coder -> testbencher -> style) pushes its
// commit, so you watch the real code land rather than a waveform of a
// binary counter sweep.
export default function CodePanel({ events }) {
  const latest = lastCodeEvent(events);
  const [code, setCode] = useState(null);
  const [error, setError] = useState(null);
  const [visibleCount, setVisibleCount] = useState(0);
  const timerRef = useRef(null);

  const path = latest ? AGENT_PATH[latest.agent](latest.chip) : null;

  useEffect(() => {
    if (!latest) return;
    setCode(null);
    setError(null);
    setVisibleCount(0);
    fetchBranchFile(latest.branch, path)
      .then(setCode)
      .catch((e) => setError(String(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [latest?.branch, latest?.agent, latest?.ts]);

  useEffect(() => {
    clearInterval(timerRef.current);
    if (!code) return undefined;

    const totalLines = code.split("\n").length;
    const stepMs = Math.min(MAX_STEP_MS, Math.max(MIN_STEP_MS, MAX_REVEAL_MS / totalLines));
    setVisibleCount(0);
    let shown = 0;
    timerRef.current = setInterval(() => {
      shown += 1;
      setVisibleCount(shown);
      if (shown >= totalLines) clearInterval(timerRef.current);
    }, stepMs);

    return () => clearInterval(timerRef.current);
  }, [code]);

  if (!latest) return <div className="proof-empty">No code pushed yet</div>;
  if (error) return <div className="proof-empty">Could not load {path} ({error})</div>;
  if (!code) return <div className="proof-empty code-panel-loading">Loading {path}…</div>;

  const lines = code.split("\n");
  const shownLines = lines.slice(0, visibleCount);
  const stillWriting = visibleCount < lines.length;

  return (
    <div className="code-panel">
      <div className="code-panel-header">
        <span className="code-panel-live-dot" aria-hidden="true" />
        <span className="code-panel-agent">{latest.agent}</span> just wrote{" "}
        <span className="code-panel-path">{path}</span>
      </div>
      <pre className="code-panel-body">
        {shownLines.map((line, i) => (
          <div className="code-line code-line-in" key={i}>
            <span className="code-line-no">{i + 1}</span>
            <span className="code-line-text">
              {tokenizeLine(line).map((tok, j) => (
                <span key={j} className={`tok-${tok.kind}`}>
                  {tok.text}
                </span>
              ))}
            </span>
          </div>
        ))}
        {stillWriting && (
          <div className="code-line code-line-cursor" aria-hidden="true">
            <span className="code-line-no" />
            <span className="code-cursor" />
          </div>
        )}
      </pre>
    </div>
  );
}
