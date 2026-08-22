import { useEffect, useState } from "react";
import { apiUrl } from "../lib/api";

const POLL_MS = 3000;

export default function Leaderboard({ chip }) {
  const [entries, setEntries] = useState([]);

  useEffect(() => {
    let cancelled = false;
    const poll = () => {
      fetch(apiUrl(`/api/leaderboard?chip=${encodeURIComponent(chip)}`))
        .then((r) => (r.ok ? r.json() : { entries: [] }))
        .then((d) => {
          if (!cancelled) setEntries(d.entries || []);
        })
        .catch(() => {});
    };
    poll();
    const id = setInterval(poll, POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [chip]);

  const maxLut = Math.max(1, ...entries.map((e) => e.lut_count));

  return (
    <div className="leaderboard">
      <h3>Leaderboard — {chip}</h3>
      {entries.length === 0 && (
        <div className="proof-empty">
          No fully-verified &amp; synthesized attempts yet for this chip
        </div>
      )}
      {entries.map((e) => (
        <div className={`leaderboard-row ${e.best ? "leaderboard-best" : ""}`} key={e.branch}>
          <div className="leaderboard-row-top">
            <span className="leaderboard-branch">{e.branch}</span>
            {e.best && <span className="leaderboard-badge">BEST</span>}
          </div>
          <div className="leaderboard-bar-wrap">
            <div
              className="leaderboard-bar"
              style={{ width: `${(e.lut_count / maxLut) * 100}%` }}
            />
            <span className="leaderboard-lut">{e.lut_count} LUT4</span>
          </div>
          <div className="leaderboard-vectors">
            {e.passed}/{e.total} vectors verified
          </div>
        </div>
      ))}
    </div>
  );
}
