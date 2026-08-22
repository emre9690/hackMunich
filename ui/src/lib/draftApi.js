import { apiUrl } from "./api";

export async function uploadDraft(chipId, file) {
  const form = new FormData();
  form.append("chip_id", chipId);
  form.append("file", file);
  const res = await fetch(apiUrl("/api/drafts"), { method: "POST", body: form });
  if (!res.ok) throw new Error((await res.text()) || `upload failed: ${res.status}`);
  return res.json();
}

export async function fetchDraft(chipId) {
  const res = await fetch(apiUrl(`/api/drafts/${encodeURIComponent(chipId)}`));
  if (!res.ok) throw new Error((await res.text()) || `fetch draft failed: ${res.status}`);
  return res.json();
}

export async function approveDraft(chipId) {
  const res = await fetch(apiUrl(`/api/drafts/${encodeURIComponent(chipId)}/approve`), { method: "POST" });
  if (!res.ok) throw new Error((await res.text()) || `approve failed: ${res.status}`);
  return res.json();
}

export async function rejectDraft(chipId) {
  const res = await fetch(apiUrl(`/api/drafts/${encodeURIComponent(chipId)}/reject`), { method: "POST" });
  if (!res.ok) throw new Error((await res.text()) || `reject failed: ${res.status}`);
  return res.json();
}
