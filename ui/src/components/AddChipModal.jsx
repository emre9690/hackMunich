import { useEffect, useMemo, useState } from "react";
import { uploadDraft, fetchDraft, approveDraft, rejectDraft } from "../lib/draftApi";

const CHIP_ID_RE = /^[a-z][a-z0-9_]{0,63}$/;

// Upload a datasheet -> a one-off Devin session drafts a candidate golden
// model into /drafts/ (never /spec/) -> the actual truth table is shown
// here for a human to check against the datasheet -> only an explicit
// Approve click moves it into /spec/ and registers the chip. Devin never
// decides this is correct; a human looking at the table does.
export default function AddChipModal({ events, onClose, onApproved }) {
  const [chipId, setChipId] = useState("");
  const [file, setFile] = useState(null);
  const [phase, setPhase] = useState("form"); // form | drafting | review | error
  const [error, setError] = useState(null);
  const [draft, setDraft] = useState(null);
  const [busy, setBusy] = useState(false);

  const draftEvents = useMemo(
    () => events.filter((e) => e.agent === "drafter" && e.chip === chipId),
    [events, chipId]
  );
  const lastDraftEvent = draftEvents[draftEvents.length - 1];

  useEffect(() => {
    if (phase !== "drafting" || !lastDraftEvent) return;
    if (lastDraftEvent.status === "pass") {
      fetchDraft(chipId)
        .then((d) => {
          setDraft(d);
          setPhase("review");
        })
        .catch((e) => {
          setError(String(e));
          setPhase("error");
        });
    } else if (["error", "stalled", "fail"].includes(lastDraftEvent.status)) {
      setError(lastDraftEvent.detail);
      setPhase("error");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lastDraftEvent, phase]);

  async function handleSubmit() {
    if (!CHIP_ID_RE.test(chipId)) {
      setError("chip id must be lowercase letters/digits/underscore, starting with a letter");
      return;
    }
    if (!file) {
      setError("choose a datasheet file (PDF or text) first");
      return;
    }
    const confirmed = window.confirm(
      `This creates one real Devin session to draft a candidate spec for "${chipId}" from ` +
        `"${file.name}" (billed). Nothing is trusted until you review and approve it. Continue?`
    );
    if (!confirmed) return;

    setError(null);
    setBusy(true);
    try {
      await uploadDraft(chipId, file);
      setPhase("drafting");
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function handleApprove() {
    setBusy(true);
    try {
      await approveDraft(chipId);
      onApproved(chipId);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function handleReject() {
    setBusy(true);
    try {
      await rejectDraft(chipId);
      onClose();
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h3>Add Custom Chip</h3>
          <button className="modal-close" onClick={onClose}>
            ✕
          </button>
        </div>

        {phase === "form" && (
          <div className="modal-body">
            <label className="modal-field">
              Chip ID
              <input
                type="text"
                placeholder="e.g. my_chip_74"
                value={chipId}
                onChange={(e) => setChipId(e.target.value.toLowerCase())}
              />
            </label>
            <label className="modal-field">
              Datasheet (PDF or text)
              <input type="file" accept=".pdf,.txt" onChange={(e) => setFile(e.target.files[0])} />
            </label>
            <p className="modal-note">
              A one-off Devin session reads the datasheet and drafts a candidate golden model to a
              staging area — it never touches /spec/. You review the real truth table before
              anything is trusted.
            </p>
            {error && <p className="modal-error">{error}</p>}
            <button className="modal-primary" onClick={handleSubmit} disabled={busy}>
              {busy ? "Starting…" : "Draft Spec"}
            </button>
          </div>
        )}

        {phase === "drafting" && (
          <div className="modal-body">
            <p>Drafting candidate spec for "{chipId}"…</p>
            <div className="activity-feed-scroll" style={{ maxHeight: 220 }}>
              {draftEvents.length === 0 && <div className="agent-status-empty">Starting…</div>}
              {draftEvents.map((e, i) => (
                <div className="activity-line" key={i}>
                  <span className="activity-text">{e.detail}</span>
                </div>
              ))}
            </div>
            {lastDraftEvent?.session_url && (
              <a href={lastDraftEvent.session_url} target="_blank" rel="noreferrer" className="agent-status-link">
                view Devin session ↗
              </a>
            )}
          </div>
        )}

        {phase === "error" && (
          <div className="modal-body">
            <p className="modal-note">
              Devin declined to draft this rather than invent a golden model it couldn't verify
              against the datasheet. Its full reasoning:
            </p>
            <div className="draft-blocked-reason">{error}</div>
            <button className="modal-primary" onClick={() => setPhase("form")}>
              Back
            </button>
          </div>
        )}

        {phase === "review" && draft && (
          <div className="modal-body">
            <p className="modal-note">
              Review this against the actual datasheet before approving. Nothing is trusted until
              you click Approve.
            </p>
            <div className="draft-table-wrap">
              <table className="draft-table">
                <thead>
                  <tr>
                    {draft.preview.columns.map((c) => (
                      <th key={c}>{c}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {draft.preview.rows.map((row, i) => (
                    <tr key={i}>
                      {draft.preview.columns.map((c) => (
                        <td key={c}>{row[c]}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {draft.preview.truncated && (
              <p className="modal-note">
                showing {draft.preview.rows.length} of {draft.preview.total_vectors} vectors —
                review the logic below for the rest
              </p>
            )}
            <details>
              <summary>Drafted code</summary>
              <pre className="draft-code">{draft.source}</pre>
            </details>
            {error && <p className="modal-error">{error}</p>}
            <div className="modal-actions">
              <button className="modal-reject" onClick={handleReject} disabled={busy}>
                Reject
              </button>
              <button className="modal-approve" onClick={handleApprove} disabled={busy}>
                {busy ? "Approving…" : "Approve & Register"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
