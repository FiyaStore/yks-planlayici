-- YKS Planlayıcı — Faz 1: Öğrenci erişim kontrolü (davet kodu + Supabase Auth)
-- Bu dosyayı Supabase Studio → SQL Editor'e yapıştırıp çalıştır (tek seferlik kurulum).
-- Idempotent değildir — yeni bir projede bir kez çalıştırılmak üzere yazıldı.

-- ============================================================
-- 1) TABLOLAR
-- ============================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('coach','student')),
  coach_id uuid references public.profiles(id),
  full_name text,
  created_at timestamptz not null default now(),
  constraint role_coach_id_consistency check (
    (role = 'coach' and coach_id is null) or
    (role = 'student' and coach_id is not null)
  )
);
create index profiles_coach_id_idx on public.profiles(coach_id);

create table public.invite_codes (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  coach_id uuid not null references public.profiles(id),
  max_uses int,               -- null = sınırsız kullanım
  uses_count int not null default 0,
  expires_at timestamptz,     -- null = süresiz
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);
create index invite_codes_coach_id_idx on public.invite_codes(coach_id);

create table public.invite_code_redemptions (
  id uuid primary key default gen_random_uuid(),
  invite_code_id uuid not null references public.invite_codes(id),
  student_id uuid not null references public.profiles(id),
  redeemed_at timestamptz not null default now()
);

-- ============================================================
-- 2) ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles enable row level security;
alter table public.invite_codes enable row level security;
alter table public.invite_code_redemptions enable row level security;

-- profiles: herkes SADECE kendi satırını okuyabilir.
-- INSERT/UPDATE/DELETE için bilerek HİÇBİR policy yok — satır oluşturma
-- yalnızca aşağıdaki redeem_invite_code() fonksiyonu (SECURITY DEFINER,
-- RLS'i atlar) üzerinden olur. Buraya "auth.uid() = id" ile bir INSERT
-- policy eklersen kullanıcı kendini role='coach' yaparak davet sistemini
-- tamamen atlayabilir — EKLEME.
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

-- invite_codes: client'tan hiçbir şekilde erişilemez (SELECT dahil).
-- Bilerek policy eklenmedi; RLS açık + policy yok = tüm erişim reddedilir.
-- "kod var mı diye bakayım" diye SELECT policy eklemek, anon anahtarla
-- herkesin tüm kodları ve coach id'lerini dökebilmesi demektir.

-- invite_code_redemptions: aynı şekilde client'tan erişilemez, sadece
-- redeem_invite_code() içeriden yazar. İleride koç paneli eklenince
-- "coach_id = auth.uid() olan öğrencilerin redemption kayıtları" için
-- ayrı bir SELECT policy eklenecek — şimdilik yok.

-- ============================================================
-- 3) DAVET KODU KULLANMA FONKSİYONU
-- ============================================================

create or replace function public.redeem_invite_code(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invite record;
  v_already_exists boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select exists(select 1 from public.profiles where id = v_uid) into v_already_exists;
  if v_already_exists then
    raise exception 'already_registered';
  end if;

  -- Satır kilidi: iki öğrenci aynı max_uses'lı kodu aynı anda kullanmaya
  -- çalışırsa (race condition) uses_count'un yarışta aşılmasını önler.
  select * into v_invite
  from public.invite_codes
  where code = p_code
  for update;

  if v_invite is null
     or v_invite.revoked
     or (v_invite.expires_at is not null and v_invite.expires_at < now())
     or (v_invite.max_uses is not null and v_invite.uses_count >= v_invite.max_uses)
  then
    -- Bilerek tek, genel bir hata: "bulunamadı" / "süresi geçmiş" /
    -- "dolmuş" ayrımı yapılmıyor — bu bilgi, kod tahmin etmeye çalışan
    -- birine ipucu vermemek için gizleniyor.
    raise exception 'invalid_code';
  end if;

  insert into public.profiles (id, role, coach_id)
  values (v_uid, 'student', v_invite.coach_id);

  update public.invite_codes
  set uses_count = uses_count + 1
  where id = v_invite.id;

  insert into public.invite_code_redemptions (invite_code_id, student_id)
  values (v_invite.id, v_uid);
end;
$$;

-- Sadece giriş yapmış kullanıcılar çağırabilir; anonim/misafir çağıramaz.
revoke all on function public.redeem_invite_code(text) from public;
grant execute on function public.redeem_invite_code(text) to authenticated;

-- ============================================================
-- 4) İLK KOÇ HESABI — MANUEL, TEK SEFERLİK KURULUM NOTU
-- ============================================================
-- Davet sistemi bir "ilk koçu" davet edemez. Aşağıdaki adımları elle yap:
--   1. Supabase Studio → Authentication → Add user (e-posta+şifre ile)
--      oluşturduğun kullanıcının UUID'ini kopyala.
--   2. Aşağıdaki satırı UUID'i kendi değerinle değiştirip çalıştır:
--
--   insert into public.profiles (id, role, coach_id)
--   values ('BURAYA-KOÇ-UUID-YAPIŞTIR', 'coach', null);
--
--   3. Bu koça ait ilk davet kodunu oluşturmak için:
--
--   insert into public.invite_codes (code, coach_id, max_uses)
--   values ('rastgele-uzun-bir-kod', 'BURAYA-KOÇ-UUID-YAPIŞTIR', 1);
