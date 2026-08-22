import { useEffect, useState } from "react";
import { fetchBranchFile } from "../lib/api";
import { tokenizeLine } from "../lib/verilogHighlight";

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

  const path = latest ? AGENT_PATH[latest.agent](latest.chip) : null;

  useEffect(() => {
    if (!latest) return;
    setCode(null);
    setError(null);
    fetchBranchFile(latest.branch, path)
      .then(setCode)
      .catch((e) => setError(String(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [latest?.branch, latest?.agent, latest?.ts]);

  if (!latest) return <div className="proof-empty">No code pushed yet</div>;
  if (error) return <div className="proof-empty">Could not load {path} ({error})</div>;
  if (!code) return <div className="proof-empty">Loading {path}…</div>;

  return (
    <div className="code-panel">
      <div className="code-panel-header">
        <span className="code-panel-agent">{latest.agent}</span> just wrote{" "}
        <span className="code-panel-path">{path}</span>
      </div>
      <pre className="code-panel-body">
        {code.split("\n").map((line, i) => (
          <div className="code-line" key={i}>
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
      </pre>
    </div>
  );
}
