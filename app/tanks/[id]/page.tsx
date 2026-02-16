import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { AppHeader } from "@/components/app-header";
import { TankActions } from "@/components/tank-actions";
import { createClient } from "@/lib/supabase/server";

export default async function TankDetailPage({ params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/login");

  const { data, error } = await supabase
    .from("v_dashboard_tanks")
    .select("*")
    .eq("tank_id", params.id)
    .single();

  if (error || !data) return notFound();

  return (
    <main className="container">
      <AppHeader />
      <div className="card">
        <Link href="/dashboard">Voltar</Link>
        <h2>{data.tank_code}</h2>
        <p>
          Tipo: {data.tank_type} | Capacidade: {data.capacity_l}L
        </p>
        <p>
          Lote: {data.lot_code ?? "-"} | Fase: {data.phase ?? "-"}
        </p>
        <p>
          Volume: {data.volume_l ?? 0}L | Fill: {data.fill_pct ?? 0}% | Alerta: {data.alert}
        </p>
      </div>
      <TankActions tankId={data.tank_id} batchId={data.batch_id} />
    </main>
  );
}
