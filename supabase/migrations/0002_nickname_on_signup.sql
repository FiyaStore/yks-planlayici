-- YKS Planlayıcı — kayıt olurken opsiyonel takma ad (full_name) alma
-- Bu dosyayı Supabase Studio → SQL Editor'e yapıştırıp çalıştır.

-- redeem_invite_code()'un imzası değişiyor (p_full_name eklendi). Eski
-- tek-parametreli sürümü önce kaldırmazsak Postgres onu SİLMEZ, yanına
-- ikinci bir "overload" olarak ekler — bu da PostgREST'in hangi fonksiyonu
-- çağıracağını seçemeyip hata vermesine yol açar. Önce eskisini kaldırıyoruz.
drop function if exists public.redeem_invite_code(text);

create or replace function public.redeem_invite_code(p_code text, p_full_name text default null)
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

  select * into v_invite
  from public.invite_codes
  where code = p_code
  for update;

  if v_invite is null
     or v_invite.revoked
     or (v_invite.expires_at is not null and v_invite.expires_at < now())
     or (v_invite.max_uses is not null and v_invite.uses_count >= v_invite.max_uses)
  then
    raise exception 'invalid_code';
  end if;

  insert into public.profiles (id, role, coach_id, full_name)
  values (v_uid, 'student', v_invite.coach_id, nullif(trim(p_full_name), ''));

  update public.invite_codes
  set uses_count = uses_count + 1
  where id = v_invite.id;

  insert into public.invite_code_redemptions (invite_code_id, student_id)
  values (v_invite.id, v_uid);
end;
$$;

revoke all on function public.redeem_invite_code(text, text) from public;
grant execute on function public.redeem_invite_code(text, text) to authenticated;

-- Not: full_name kasıtlı olarak sadece kayıt anında (bu fonksiyon içinde)
-- yazılıyor. profiles tablosunda hâlâ hiçbir client-side UPDATE policy'si
-- yok, yani kayıttan sonra kimse (öğrenci dahil) bu alanı ya da başka bir
-- alanı client'tan değiştiremez — bilerek böyle, güvenlik tasarımını bozmaz.
