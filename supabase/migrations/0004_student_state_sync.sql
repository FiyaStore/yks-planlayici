-- YKS Planlayıcı — Faz 2: Cihazlar arası state senkronizasyonu
-- Bu dosyayı Supabase Studio → SQL Editor'e yapıştırıp çalıştır.

create table public.student_state (
  id uuid primary key references public.profiles(id) on delete cascade,
  state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.student_state enable row level security;

-- profiles'ın aksine burada kilitli bir RPC'ye gerek yok — korunacak bir
-- rol/koç alanı yok, sadece öğrencinin kendi JSON verisi. "Kendi satırına
-- CRUD" (RPC'siz, doğrudan client'tan) burada güvenli ve yeterli.
create policy "student_state_select_own"
  on public.student_state for select
  using (auth.uid() = id);

create policy "student_state_insert_own"
  on public.student_state for insert
  with check (auth.uid() = id);

create policy "student_state_update_own"
  on public.student_state for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Bilerek DELETE policy yok — client kendi ilerlemesini yanlışlıkla silemesin.

revoke all on public.student_state from anon;
grant select, insert, update on public.student_state to authenticated;

-- updated_at'i client'ın (yanlış ayarlanmış olabilecek) saatine güvenmeden
-- sunucu tarafında tut.
create or replace function public.set_student_state_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger student_state_touch_updated_at
  before insert or update on public.student_state
  for each row execute function public.set_student_state_updated_at();
