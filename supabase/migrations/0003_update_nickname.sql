-- YKS Planlayıcı — takma adı sonradan değiştirebilme
-- Bu dosyayı Supabase Studio → SQL Editor'e yapıştırıp çalıştır.

-- profiles tablosunda hâlâ hiçbir genel UPDATE policy YOK (bilerek —
-- yoksa bir öğrenci role/coach_id'sini de değiştirebilirdi). Bunun yerine
-- SADECE full_name'i, SADECE kendi satırında değiştirebilen dar bir
-- fonksiyon ekliyoruz.
create or replace function public.update_my_nickname(p_full_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  update public.profiles
  set full_name = nullif(trim(p_full_name), '')
  where id = v_uid;
end;
$$;

revoke all on function public.update_my_nickname(text) from public;
grant execute on function public.update_my_nickname(text) to authenticated;
