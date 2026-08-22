import { useEffect, useState } from "react";
import { useEvents } from "./lib/useEvents";
import { startRun, fetchChips } from "./lib/api";
import PipelineGraph from "./components/PipelineGraph";
import AgentStatus from "./components/AgentStatus";
import ProofPanel from "./components/ProofPanel";

export default function App() {
  const { events, connected } = useEvents();
  const [chips, setChips] = useState([]);
  const [chip, setChip] = useState("74138");
  const [launching, setLaunching] = useState(false);
  const [launchError, setLaunchError] = useState(null);

  useEffect(() => {
    fetchChips()
      .then((d) => {
        setChips(d.chips);
        if (d.chips.length) setChip(d.chips[0]);
      })
      .catch(() => {});
  }, []);

  const branch = events.length ? events[events.length - 1].branch : null;

  async function handleLaunch() {
    setLaunching(true);
    setLaunchError(null);
    try {
      await startRun({ chip, attempts: 1 });
    } catch (e) {
      setLaunchError(String(e));
    } finally {
      setLaunching(false);
    }
  }

  return (
    <div className="app">
      <header className="app-header">
        <div className="app-title">
          <span className="app-title-mark">◆</span> CHIP RECREATION — COMMAND ROOM
        </div>
        <div className="app-header-right">
          {branch && <span className="app-branch">{branch}</span>}
          <span className={`conn-dot ${connected ? "conn-on" : "conn-off"}`} />
          <span className="conn-label">{connected ? "LIVE" : "DISCONNECTED"}</span>
        </div>
      </header>

      <div className="app-controls">
        <select value={chip} onChange={(e) => setChip(e.target.value)}>
          {chips.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
        <button onClick={handleLaunch} disabled={launching}>
          {launching ? "Launching…" : "Launch Attempt"}
        </button>
        {launchError && <span className="app-launch-error">{launchError}</span>}
      </div>

      <main className="app-main">
        <section className="app-graph-section">
          <PipelineGraph events={events} />
          <AgentStatus events={events} />
        </section>
        <section className="app-proof-section">
          <ProofPanel events={events} />
        </section>
      </main>
    </div>
  );
}
