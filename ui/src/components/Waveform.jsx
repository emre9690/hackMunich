import { useEffect, useState } from "react";
import { parseVcd } from "../lib/vcd";
import { apiUrl } from "../lib/api";

const MAX_SAMPLES = 40;

export default function Waveform({ artifactPath }) {
  const [parsed, setParsed] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!artifactPath) return;
    setParsed(null);
    setError(null);
    fetch(apiUrl(`/api/artifact?path=${encodeURIComponent(artifactPath)}`))
      .then((r) => {
        if (!r.ok) throw new Error(`${r.status}`);
        return r.text();
      })
      .then((text) => setParsed(parseVcd(text)))
      .catch((e) => setError(String(e)));
  }, [artifactPath]);

  if (!artifactPath) return <div className="waveform-empty">No waveform yet</div>;
  if (error) return <div className="waveform-empty">Could not load waveform ({error})</div>;
  if (!parsed) return <div className="waveform-empty">Loading waveform…</div>;

  // vec is the sweep counter, not a real port -- everything else is a 1-bit signal
  const names = parsed.signals.filter((n) => n !== "vec");
  const samples = parsed.samples.slice(0, MAX_SAMPLES);

  return (
    <div className="waveform">
      <div className="waveform-rows">
        {names.map((name) => (
          <div className="waveform-row" key={name}>
            <span className="waveform-label">{name}</span>
            <div className="waveform-cells">
              {samples.map((s, i) => {
                const v = s.values[name];
                const on = v === "1";
                return (
                  <div
                    key={i}
                    className={`waveform-cell ${on ? "on" : "off"}`}
                    title={`t=${s.time} ${name}=${v ?? "?"}`}
                  />
                );
              })}
            </div>
          </div>
        ))}
      </div>
      {parsed.samples.length > MAX_SAMPLES && (
        <div className="waveform-note">
          showing first {MAX_SAMPLES} of {parsed.samples.length} vectors
        </div>
      )}
    </div>
  );
}
