-- YKS Planlayıcı — student_state.state sütununu jsonb'den json'a çevir
-- jsonb, iç içe nesnelerdeki alan sırasını garanti etmiyor; bu uygulama
-- (konu listesi gibi) nesne anahtar sırasına güveniyor. json ise orijinal
-- metni olduğu gibi saklıyor, sıra bozulmuyor. Zaten oluşturulmuş
-- student_state tablosu için tek seferlik dönüşüm:

alter table public.student_state
  alter column state type json using state::json;

alter table public.student_state
  alter column state set default '{}'::json;
