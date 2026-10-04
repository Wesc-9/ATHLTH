create or replace function public.submit_app_store_transaction(
  p_transaction_id text,
  p_original_transaction_id text,
  p_product_id text,
  p_app_account_token uuid,
  p_signed_transaction_info text
)
returns void
language sql
set search_path = ''
as $$
  insert into public.app_store_transaction_submissions (
    user_id,
    transaction_id,
    original_transaction_id,
    product_id,
    app_account_token,
    signed_transaction_info
  )
  values (
    (select auth.uid()),
    p_transaction_id,
    p_original_transaction_id,
    p_product_id,
    p_app_account_token,
    p_signed_transaction_info
  )
  on conflict (user_id, transaction_id) do nothing;
$$;

revoke execute on function public.submit_app_store_transaction(text, text, text, uuid, text) from public;
revoke execute on function public.submit_app_store_transaction(text, text, text, uuid, text) from anon;
grant execute on function public.submit_app_store_transaction(text, text, text, uuid, text) to authenticated;
