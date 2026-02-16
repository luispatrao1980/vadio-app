"use client";

import Link from "next/link";
import { useSyncStatus } from "@/hooks/use-sync-status";

export function AppHeader() {
  const { isOnline, pending, runSync, lastError } = useSyncStatus();

  return (
    <div className="card">
      <div className="row" style={{ justifyContent: "space-between" }}>
        <Link href="/dashboard">
          <strong>Vadio Cellar</strong>
        </Link>
        <div className="row">
          <span className="pill">{isOnline ? "Online" : "Offline"}</span>
          <span className="pill">Pendentes: {pending}</span>
          <button onClick={runSync}>Sync</button>
        </div>
      </div>
      {lastError ? <p style={{ color: "#b02a2a", marginBottom: 0 }}>Sync error: {lastError}</p> : null}
    </div>
  );
}
