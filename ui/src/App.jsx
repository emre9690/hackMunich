import { useEffect, useState } from "react";
import { useEvents } from "./lib/useEvents";
import { startRun, fetchChips, resetRuns } from "./lib/api";
import PipelineGraph from "./components/PipelineGraph";
import AgentStatus from "./components/AgentStatus";
import ProofPanel from "./components/ProofPanel";
import Leaderboard from "./components/Leaderboard";

export default function App() {
  const { events, connected, clearEvents } = useEvents();
  const [chips, setChips] = useState([]);
  const [chip, setChip] = useState("74138");
  const [launching, setLaunching] = useState(false);
  const [launchError, setLaunchError] = useState(null);
  const [resetting, setResetting] = useState(false);
  // Stage 6, behind a flag: parallel attempts + leaderboard view. Off by
  // default so the core single-pipeline demo (attempts=1, sequential) is
  // never affected.
  const [attempts, setAttempts] = useState(1);
  const [parallel, setParallel] = useState(false);
  const [showLeaderboard, setShowLeaderboard] = useState(false);

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
      await startRun({ chip, attempts, parallel: parallel && attempts > 1 });
    } catch (e) {
      setLaunchError(String(e));
    } finally {
      setLaunching(false);
    }
  }

  async function handleReset() {
    setResetting(true);
    try {
      await resetRuns();
      clearEvents();
    } catch (e) {
      setLaunchError(String(e));
    } finally {
      setResetting(false);
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
        <label className="app-attempts-label">
          Attempts
          <input
            type="number"
            min={1}
            max={4}
            value={attempts}
            onChange={(e) => setAttempts(Math.max(1, Number(e.target.value) || 1))}
          />
        </label>
        <label className="app-parallel-label">
          <input
            type="checkbox"
            checked={parallel}
            disabled={attempts <= 1}
            onChange={(e) => setParallel(e.target.checked)}
          />
          Parallel
        </label>
        <button onClick={handleLaunch} disabled={launching}>
          {launching ? "Launching…" : "Launch Attempt"}
        </button>
        <button
          className={`app-toggle-btn ${showLeaderboard ? "app-toggle-btn-active" : ""}`}
          onClick={() => setShowLeaderboard((v) => !v)}
        >
          {showLeaderboard ? "Show Proof Panel" : "Show Leaderboard"}
        </button>
        <button className="app-reset-btn" onClick={handleReset} disabled={resetting}>
          {resetting ? "Resetting…" : "↺ Reset"}
        </button>
        {launchError && <span className="app-launch-error">{launchError}</span>}
      </div>

      <main className="app-main">
        <section className="app-graph-section">
          <PipelineGraph events={events} />
          <AgentStatus events={events} />
        </section>
        <section className="app-proof-section">
          {showLeaderboard ? <Leaderboard chip={chip} /> : <ProofPanel events={events} />}
        </section>
      </main>
    </div>
  );
}
