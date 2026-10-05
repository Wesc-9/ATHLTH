-- posts -> requests -> posts caused recursive RLS expansion. Keep the request
-- lookup private and caller-bound; never accept another user's ID as input.
create or replace function private.has_train_together_request(p_post_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.train_together_requests r
    where r.post_id = p_post_id and r.requester_id = auth.uid()
  );
$$;

revoke all on function private.has_train_together_request(uuid) from public, anon;
grant execute on function private.has_train_together_request(uuid) to authenticated;

drop policy if exists train_together_posts_read on public.train_together_posts;
create policy train_together_posts_read
on public.train_together_posts for select to authenticated
using (
  creator_id = (select auth.uid())
  or (
    status in ('open','full')
    and scheduled_start > now() - interval '2 hours'
    and not private.is_blocked(creator_id)
  )
  or private.has_train_together_request(train_together_posts.id)
);

-- Request/meetup policies and all write policies retain their existing rules.
