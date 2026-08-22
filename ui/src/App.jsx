import { useEffect, useRef, useState } from "react";
import { useEvents } from "./lib/useEvents";
import { startRun, fetchChips, resetRuns, killAll } from "./lib/api";
import PipelineGraph from "./components/PipelineGraph";
import ActivityFeed from "./components/ActivityFeed";
import AgentStatus from "./components/AgentStatus";
import ProofPanel from "./components/ProofPanel";
import SchematicPanel from "./components/SchematicPanel";
import AddChipModal from "./components/AddChipModal";

export default function App() {
  const { events, connected, clearEvents } = useEvents();
  const [chips, setChips] = useState([]);
  const [chip, setChip] = useState(null);
  const [launching, setLaunching] = useState(false);
  const [launchError, setLaunchError] = useState(null);
  const [resetting, setResetting] = useState(false);
  const [killing, setKilling] = useState(false);
  const [killResult, setKillResult] = useState(null);
  const [showAddChip, setShowAddChip] = useState(false);

  function refreshChips(preferred) {
    fetchChips()
      .then((d) => {
        setChips(d.chips);
        setChip((prev) => {
          if (preferred && d.chips.includes(preferred)) return preferred;
          if (prev && d.chips.includes(prev)) return prev;
          return d.chips[0] ?? null;
        });
      })
      .catch(() => {});
  }

  useEffect(() => {
    refreshChips();
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
    if (!chip) return;
    eventCountAtLaunch.current = events.length;
    setLaunching(true);
    setLaunchError(null);
    try {
      await startRun({ chip });
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
      setChip(null);
      refreshChips();
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
          <span className="app-title-mark">◆</span>reFORGE
        </div>
        <div className="app-header-right">
          {branch && <span className="app-branch">{branch}</span>}
          <span className={`conn-dot ${connected ? "conn-on" : "conn-off"}`} />
          <span className="conn-label">{connected ? "LIVE" : "DISCONNECTED"}</span>
        </div>
      </header>

      <div className="app-controls">
        <button className="app-addchip-btn" onClick={() => setShowAddChip(true)}>
          + Add Chip
        </button>
        <select value={chip ?? ""} onChange={(e) => setChip(e.target.value)} disabled={!chips.length}>
          {!chips.length && <option value="">No chips yet — Add Chip</option>}
          {chips.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
        <button onClick={handleLaunch} disabled={launching || !chip}>
          {launching ? "Launching…" : "Launch Attempt"}
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
          <SchematicPanel events={events} />
          <ActivityFeed events={events} />
          <AgentStatus events={events} />
        </section>
        <section className="app-proof-section">
          <ProofPanel events={events} />
        </section>
      </main>

      {showAddChip && (
        <AddChipModal
          events={events}
          onClose={() => setShowAddChip(false)}
          onApproved={(newChipId) => {
            setShowAddChip(false);
            refreshChips(newChipId);
          }}
        />
      )}
    </div>
  );
}
