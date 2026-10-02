create policy "service role only"
on public.apple_sign_in_tokens
for all
to service_role
using (true)
with check (true);
