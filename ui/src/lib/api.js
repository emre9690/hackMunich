export const API_BASE = import.meta.env.VITE_API_BASE || "http://localhost:8000";

export function apiUrl(path) {
  return `${API_BASE}${path}`;
}

export async function startRun({ chip, attempts = 1, parallel = false }) {
  const res = await fetch(apiUrl("/api/runs"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chip, attempts, parallel }),
  });
  if (!res.ok) throw new Error(`start run failed: ${res.status}`);
  return res.json();
}

export async function killAll() {
  const res = await fetch(apiUrl("/api/kill-all"), { method: "POST" });
  if (!res.ok) throw new Error(`kill-all failed: ${res.status}`);
  return res.json();
}

export async function resetRuns() {
  const res = await fetch(apiUrl("/api/reset"), { method: "POST" });
  if (!res.ok) throw new Error(`reset failed: ${res.status}`);
  return res.json();
}

export async function fetchBranchFile(branch, path) {
  const res = await fetch(
    apiUrl(`/api/branch-file?branch=${encodeURIComponent(branch)}&path=${encodeURIComponent(path)}`)
  );
  if (!res.ok) throw new Error(`fetch branch file failed: ${res.status}`);
  return res.text();
}

export async function fetchChips() {
  const res = await fetch(apiUrl("/api/chips"));
  if (!res.ok) throw new Error(`fetch chips failed: ${res.status}`);
  return res.json();
}
