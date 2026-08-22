import { useEffect, useRef, useState } from "react";
import { apiUrl } from "./api";

const HISTORY_LIMIT = 500;

// Subscribes to the harness/orchestrator's structured event stream over SSE.
// UI state is derived ONLY from these JSON events -- never from parsing any
// Devin session's natural-language chatter.
export function useEvents() {
  const [events, setEvents] = useState([]);
  const [connected, setConnected] = useState(false);
  const sourceRef = useRef(null);

  useEffect(() => {
    const source = new EventSource(apiUrl("/api/events"));
    sourceRef.current = source;

    source.onopen = () => setConnected(true);
    source.onerror = () => setConnected(false);
    source.onmessage = (msg) => {
      try {
        const event = JSON.parse(msg.data);
        setEvents((prev) => {
          const next = [...prev, event];
          return next.length > HISTORY_LIMIT ? next.slice(next.length - HISTORY_LIMIT) : next;
        });
      } catch {
        // ignore malformed lines rather than crash the UI
      }
    };

    return () => source.close();
  }, []);

  const clearEvents = () => setEvents([]);

  return { events, connected, clearEvents };
}
