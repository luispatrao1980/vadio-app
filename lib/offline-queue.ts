"use client";

import { openDB } from "idb";
import { createClient } from "@/lib/supabase/client";

export type QueueJob =
  | { id?: number; type: "rpc"; fn: string; args: Record<string, unknown>; createdAt: string }
  | { id?: number; type: "insert"; table: string; payload: Record<string, unknown>; createdAt: string };

const DB_NAME = "vadio-offline";
const STORE = "jobs";

async function db() {
  return openDB(DB_NAME, 1, {
    upgrade(dbInstance) {
      if (!dbInstance.objectStoreNames.contains(STORE)) {
        dbInstance.createObjectStore(STORE, { keyPath: "id", autoIncrement: true });
      }
    }
  });
}

export async function enqueue(job: Omit<QueueJob, "id" | "createdAt">) {
  const database = await db();
  await database.add(STORE, { ...job, createdAt: new Date().toISOString() });
}

export async function pendingCount() {
  const database = await db();
  return database.count(STORE);
}

export async function syncQueue(): Promise<{ ok: boolean; processed: number; error?: string }> {
  if (!navigator.onLine) return { ok: false, processed: 0, error: "offline" };

  const database = await db();
  const tx = database.transaction(STORE, "readwrite");
  const store = tx.objectStore(STORE);
  const jobs = await store.getAll();
  const supabase = createClient();

  let processed = 0;
  for (const job of jobs as QueueJob[]) {
    try {
      if (job.type === "rpc") {
        const { error } = await supabase.rpc(job.fn, job.args);
        if (error) throw error;
      }
      if (job.type === "insert") {
        const { error } = await supabase.from(job.table).insert(job.payload);
        if (error) throw error;
      }
      await store.delete(job.id as number);
      processed += 1;
    } catch (err) {
      await tx.done;
      return { ok: false, processed, error: err instanceof Error ? err.message : "sync_failed" };
    }
  }

  await tx.done;
  return { ok: true, processed };
}
