import Link from "next/link";
import { redirect } from "next/navigation";
import { AppHeader } from "@/components/app-header";
import { createClient } from "@/lib/supabase/server";

type DashboardTank = {
  tank_id: string;
  tank_code: string;
  tank_type: string;
  capacity_l: number;
  lot_code: string | null;
  phase: string | null;
  volume_l: number | null;
  fill_pct: number | null;
  alert: string;
  sort_prefix: string;
  sort_number: number;
};

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/login");

  const { data, error } = await supabase
    .from("v_dashboard_tanks")
    .select("*")
    .order("sort_prefix", { ascending: true })
    .order("sort_number", { ascending: true });

  if (error) {
    return (
      <main className="container">
        <AppHeader />
        <div className="card">Erro a carregar dashboard: {error.message}</div>
      </main>
    );
  }

  return (
    <main className="container">
      <AppHeader />
      <div className="card">
        <h2>Depositos</h2>
        {(data as DashboardTank[]).map((tank) => (
          <Link key={tank.tank_id} href={`/tanks/${tank.tank_id}`}>
            <div className="card" style={{ marginBottom: 8 }}>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <strong>
                  {tank.tank_code} ({tank.tank_type})
                </strong>
                <span className="pill">{tank.alert}</span>
              </div>
              <p style={{ margin: "6px 0" }}>
                Lote: {tank.lot_code ?? "-"} | Fase: {tank.phase ?? "-"}
              </p>
              <p style={{ margin: 0 }}>
                Volume: {tank.volume_l ?? 0}L / {tank.capacity_l}L ({tank.fill_pct ?? 0}%)
              </p>
            </div>
          </Link>
        ))}
      </div>
    </main>
  );
}
