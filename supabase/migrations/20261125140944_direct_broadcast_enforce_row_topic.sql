alter policy athlth_direct_broadcast_receive_own on realtime.messages
using (
  extension = 'broadcast'
  and (select auth.uid()) is not null
  and topic = (select realtime.topic())
  and topic like 'athlth-direct:' || (select auth.uid())::text || ':%'
);
