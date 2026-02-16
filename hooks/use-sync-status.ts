"use client";

import { useCallback, useEffect, useState } from "react";
import { pendingCount, syncQueue } from "@/lib/offline-queue";

export function useSyncStatus() {
  const [isOnline, setIsOnline] = useState(true);
  const [pending, setPending] = useState(0);
  const [lastError, setLastError] = useState<string | null>(null);

  const refreshPending = useCallback(async () => {
    setPending(await pendingCount());
  }, []);

  const runSync = useCallback(async () => {
    const result = await syncQueue();
    if (!result.ok && result.error !== "offline") setLastError(result.error ?? "sync_failed");
    await refreshPending();
  }, [refreshPending]);

  useEffect(() => {
    const update = () => setIsOnline(navigator.onLine);
    update();
    refreshPending();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, [refreshPending]);

  useEffect(() => {
    if (isOnline) runSync();
  }, [isOnline, runSync]);

  return { isOnline, pending, lastError, runSync, refreshPending };
}
