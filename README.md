# Vadio Cellar PWA

App mobile-first (PWA) para registo e rastreio de operacoes de adega com suporte offline.

## O que ja esta entregue

- `supabase/master_migration.sql`: schema completo (tabelas, tipos, RPCs, views, RLS, seed base).
- `supabase/tests.sql`: 5 testes SQL rapidos.
- Esqueleto Next.js PWA com:
  - login Supabase
  - dashboard de depositos (`v_dashboard_tanks`)
  - detalhe do deposito com atalhos para Analise, Trasfega, Adicao e HACCP
  - offline queue em IndexedDB com sync em ordem e stop no primeiro erro

## Estrutura

- `supabase/master_migration.sql`
- `supabase/tests.sql`
- `app/`
- `components/`
- `hooks/`
- `lib/`
- `public/`

## 1) Criar projeto Supabase

1. Ir a https://supabase.com e criar um novo projeto.
2. Abrir `SQL Editor`.
3. Executar `supabase/master_migration.sql`.
4. Executar `supabase/tests.sql` para validacao.

## 2) Criar utilizador admin

1. Em `Authentication > Users`, criar o utilizador (email + password).
2. Copiar o `UUID` do user criado.
3. No `SQL Editor`, correr:

```sql
insert into public.profile (id, full_name, role)
values ('UUID_DO_USER', 'Admin Vadio', 'admin')
on conflict (id) do update set role = excluded.role, full_name = excluded.full_name;
```

## 3) Inserir depositos iniciais

Opcao A (SQL rapido):

```sql
insert into public.tank (tank_code, tank_type, capacity_l) values
('A01','A',5000),
('A02','A',5000),
('F01','F',3000),
('F02','F',3000),
('BARR001','BARR',225),
('T01','T',1500),
('B01','B',10000);
```

Opcao B (CSV import):

1. Criar um CSV com colunas: `tank_code,tank_type,capacity_l,is_active,notes`.
2. Em `Table Editor > tank > Insert > Import data`, importar CSV.

## 4) Setup local da app

1. Instalar Node.js 20+.
2. No terminal:

```bash
npm install
```

3. Criar `.env.local` com:

```bash
NEXT_PUBLIC_SUPABASE_URL=https://<PROJECT_REF>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<ANON_KEY>
```

4. Correr local:

```bash
npm run dev
```

5. Abrir `http://localhost:3000`.

## 5) Deploy na Vercel

1. Subir o repositorio para GitHub.
2. Em https://vercel.com, importar o repo.
3. Definir env vars:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
4. Deploy.

## 6) Instalar como PWA no telemovel

Android (Chrome):
1. Abrir URL de producao.
2. Menu > `Add to Home screen` / `Install app`.

iOS (Safari):
1. Abrir URL de producao.
2. Share > `Add to Home Screen`.

## Fluxo offline implementado

- Cada acao pode virar job local (`rpc` ou `insert`) em IndexedDB.
- Quando a rede volta, `Sync` reexecuta por ordem de criacao.
- Se houver erro, para no primeiro erro e preserva os restantes jobs.
- UI mostra `Online/Offline` e `Pendentes`.

## RPCs principais entregues

- `rpc_create_intake`
- `rpc_press_to_must` (herda automaticamente composicao de origem)
- `rpc_transfer_batch`
- `rpc_blend_batches` (agrega origem por talhao/casta)
- `rpc_bottle_batch` (lote manual unico no engarrafamento)
- `rpc_addition` (evento + detail + stock move OUT)

## Queries/views de dashboard e fermentacao

- `v_dashboard_tanks`
- `v_fermentation_active`
- `v_fermentation_finished_recent`
- `v_fermentation_missing_readings`

## Nota TOConline

A integracao TOConline foi mantida em standby, conforme pedido.
