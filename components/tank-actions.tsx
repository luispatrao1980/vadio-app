"use client";

import { FormEvent, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { enqueue } from "@/lib/offline-queue";
import { useSyncStatus } from "@/hooks/use-sync-status";

type Props = {
  tankId: string;
  batchId: string | null;
};

async function runRpcOrQueue(fn: string, args: Record<string, unknown>) {
  const supabase = createClient();
  if (!navigator.onLine) {
await enqueue({
  type: "rpc",
  fn,
  args: args as Record<string, unknown>,
} as any);
    return { queued: true };
  }
  const { error } = await supabase.rpc(fn, args);
  if (error) {
    if (error.message.toLowerCase().includes("network")) {
await enqueue({
  type: "rpc",
  fn,
  args: args as Record<string, unknown>
} as any);
      return { queued: true };
    }
    throw error;
  }
  return { queued: false };
}

export function TankActions({ tankId, batchId }: Props) {
  const { refreshPending } = useSyncStatus();
  const [msg, setMsg] = useState<string | null>(null);
  const [analysisValue, setAnalysisValue] = useState("1.000");
  const [toTankId, setToTankId] = useState("");
  const [newVolume, setNewVolume] = useState("0");
  const [additionLotId, setAdditionLotId] = useState("");
  const [additionQty, setAdditionQty] = useState("0");
  const [haccpMethod, setHaccpMethod] = useState("CIP");

  async function addAnalysis(e: FormEvent) {
    e.preventDefault();
    if (!batchId) return setMsg("Sem lote ativo.");

    const supabase = createClient();
    const { data: density } = await supabase.from("analysis_parameter").select("id").eq("code", "density").single();
    if (!density?.id) return setMsg("Parametro density nao encontrado.");

    if (!navigator.onLine) {
      await enqueue({
        type: "insert",
        table: "analysis_reading",
        payload: {
          batch_id: batchId,
          tank_id: tankId,
          parameter_id: density.id,
          value_num: Number(analysisValue)
        }
      });
      await refreshPending();
      return setMsg("Analise guardada offline.");
    }

    const { error } = await supabase.from("analysis_reading").insert({
      batch_id: batchId,
      tank_id: tankId,
      parameter_id: density.id,
      value_num: Number(analysisValue)
    });
    if (error) return setMsg(error.message);
    setMsg("Analise registada.");
  }

  async function transfer(e: FormEvent) {
    e.preventDefault();
    if (!batchId) return setMsg("Sem lote ativo.");
    try {
      const res = await runRpcOrQueue("rpc_transfer_batch", {
        p_batch_id: batchId,
        p_to_tank_id: toTankId,
        p_new_volume_l: Number(newVolume),
        p_loss_l: 0
      });
      await refreshPending();
      setMsg(res.queued ? "Trasfega em fila offline." : "Trasfega registada.");
    } catch (err) {
      setMsg(err instanceof Error ? err.message : "Erro");
    }
  }

  async function addition(e: FormEvent) {
    e.preventDefault();
    if (!batchId) return setMsg("Sem lote ativo.");
    try {
      const res = await runRpcOrQueue("rpc_addition", {
        p_batch_id: batchId,
        p_tank_id: tankId,
        p_product_lot_id: additionLotId,
        p_qty: Number(additionQty),
        p_uom: "kg"
      });
      await refreshPending();
      setMsg(res.queued ? "Adicao em fila offline." : "Adicao registada.");
    } catch (err) {
      setMsg(err instanceof Error ? err.message : "Erro");
    }
  }

  async function haccp(e: FormEvent) {
    e.preventDefault();
    const payload = {
      tank_id: tankId,
      method: haccpMethod,
      chemical: "Peracetic",
      concentration: "0.2%",
      contact_time_min: 20,
      responsible_name: "Operator"
    };
    const supabase = createClient();

    if (!navigator.onLine) {
      await enqueue({ type: "insert", table: "haccp_cleaning", payload });
      await refreshPending();
      return setMsg("HACCP guardado offline.");
    }

    const { error } = await supabase.from("haccp_cleaning").insert(payload);
    if (error) return setMsg(error.message);
    setMsg("HACCP registado.");
  }

  return (
    <div>
      <div className="card">
        <h3>+ Analise (densidade)</h3>
        <form onSubmit={addAnalysis} className="row">
          <input value={analysisValue} onChange={(e) => setAnalysisValue(e.target.value)} />
          <button type="submit">Registar</button>
        </form>
      </div>

      <div className="card">
        <h3>Trasfega</h3>
        <form onSubmit={transfer}>
          <input
            placeholder="ID do deposito destino"
            value={toTankId}
            onChange={(e) => setToTankId(e.target.value)}
            style={{ marginBottom: 8 }}
          />
          <input
            placeholder="Volume novo (L)"
            value={newVolume}
            onChange={(e) => setNewVolume(e.target.value)}
            style={{ marginBottom: 8 }}
          />
          <button type="submit">Executar</button>
        </form>
      </div>

      <div className="card">
        <h3>Adicao</h3>
        <form onSubmit={addition}>
          <input
            placeholder="ID do lote enologico"
            value={additionLotId}
            onChange={(e) => setAdditionLotId(e.target.value)}
            style={{ marginBottom: 8 }}
          />
          <input
            placeholder="Quantidade"
            value={additionQty}
            onChange={(e) => setAdditionQty(e.target.value)}
            style={{ marginBottom: 8 }}
          />
          <button type="submit">Registar adicao</button>
        </form>
      </div>

      <div className="card">
        <h3>HACCP</h3>
        <form onSubmit={haccp} className="row">
          <select value={haccpMethod} onChange={(e) => setHaccpMethod(e.target.value)}>
            <option value="CIP">CIP</option>
            <option value="Manual">Manual</option>
          </select>
          <button type="submit">Registar limpeza</button>
        </form>
      </div>
      {msg ? <p>{msg}</p> : null}
    </div>
  );
}
