import { useEffect, useRef, useState } from "react";
import { useEvents } from "./lib/useEvents";
import { startRun, fetchChips, resetRuns, killAll } from "./lib/api";
import PipelineGraph from "./components/PipelineGraph";
import ActivityFeed from "./components/ActivityFeed";
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
  const [killing, setKilling] = useState(false);
  const [killResult, setKillResult] = useState(null);
  // Stage 6, behind a flag: parallel attempts + leaderboard view. Off by
  // default so the core single-pipeline demo (attempts=1, sequential) is
  // never affected.
  const [attempts, setAttempts] = useState(1);
  const [parallel, setParallel] = useState(false);
  const [showLeaderboard, setShowLeaderboard] = useState(false);
  // Skips Testbencher/Style (fewer sequential Devin calls) for a faster
  // demo. Vector verification is exhaustive at every setting, always --
  // this only reduces which agents run, never how thoroughly the RTL is
  // checked.
  const [fastDemo, setFastDemo] = useState(false);

  useEffect(() => {
    fetchChips()
      .then((d) => {
        setChips(d.chips);
        if (d.chips.length) setChip(d.chips[0]);
      })
      .catch(() => {});
  }, []);

  const branch = events.length ? events[events.length - 1].branch : null;
  const eventCountAtLaunch = useRef(0);
  const launchTimeoutRef = useRef(null);

  // The POST resolves as soon as the server spawns the subprocess -- well
  // before that subprocess has done its git setup and actually created a
  // Devin session. Without this, the button (and the pipeline graph) show
  // nothing for a few seconds after clicking, looking like it did nothing.
  // Keep "launching" true until the first real event actually streams in.
  useEffect(() => {
    if (launching && events.length > eventCountAtLaunch.current) {
      setLaunching(false);
      clearTimeout(launchTimeoutRef.current);
    }
  }, [events, launching]);

  async function handleLaunch() {
    // A single attempt is the normal, everyday action this whole UI exists
    // for -- warning on every click of it is just friction. Only the
    // elevated case (attempts > 1, especially with --parallel) is what
    // actually caused an unintended ~12-session spend, so only that case
    // gets a confirm gate.
    if (attempts > 1) {
      const estimatedSessions = attempts * 3;
      const confirmed = window.confirm(
        `This launches ${attempts} attempts on ${chip}` +
          (parallel ? " in PARALLEL" : "") +
          `, creating up to ~${estimatedSessions} real Devin sessions (billed). Continue?`
      );
      if (!confirmed) return;
    }

    eventCountAtLaunch.current = events.length;
    setLaunching(true);
    setLaunchError(null);
    try {
      await startRun({ chip, attempts, parallel: parallel && attempts > 1, fastDemo });
      // Safety net: if no event shows up (e.g. the subprocess died before
      // emitting anything), don't leave the button stuck disabled forever.
      launchTimeoutRef.current = setTimeout(() => setLaunching(false), 20000);
    } catch (e) {
      setLaunchError(String(e));
      setLaunching(false);
    }
  }

  async function handleKillAll() {
    const confirmed = window.confirm(
      "This forcibly stops every orchestrator process running locally, so no " +
        "NEW Devin sessions get created. It does NOT cancel a Devin session " +
        "already running in the cloud -- there's no known API to do that. Continue?"
    );
    if (!confirmed) return;

    setKilling(true);
    setKillResult(null);
    try {
      const result = await killAll();
      setKillResult(`Killed ${result.killed_pids.length} process(es).`);
    } catch (e) {
      setLaunchError(String(e));
    } finally {
      setKilling(false);
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
        <label className="app-fastdemo-label" title="Skips Testbencher/Style. Vector verification stays exhaustive always.">
          <input
            type="checkbox"
            checked={fastDemo}
            onChange={(e) => setFastDemo(e.target.checked)}
          />
          Fast Demo Mode
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
        <button className="app-kill-btn" onClick={handleKillAll} disabled={killing}>
          {killing ? "Killing…" : "⏻ Kill All Orchestrators"}
        </button>
        {launchError && <span className="app-launch-error">{launchError}</span>}
        {killResult && <span className="app-kill-result">{killResult}</span>}
      </div>

      <main className="app-main">
        <section className="app-graph-section">
          <PipelineGraph events={events} starting={launching} />
          <ActivityFeed events={events} />
          <AgentStatus events={events} />
        </section>
        <section className="app-proof-section">
          {showLeaderboard ? <Leaderboard chip={chip} /> : <ProofPanel events={events} />}
        </section>
      </main>
    </div>
  );
}
