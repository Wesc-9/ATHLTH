-- Same-account iPad access requests may notify only registered iPhones.
-- Device family has no effect on existing push registrations.
alter table public.notification_devices
    add column if not exists device_family text;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'notification_devices_family_check'
          and conrelid = 'public.notification_devices'::regclass
    ) then
        alter table public.notification_devices
            add constraint notification_devices_family_check
            check (device_family is null or device_family in ('iphone', 'ipad'));
    end if;
end
$$;

-- The server updates this timestamp to avoid sending multiple notifications
-- for the same short-lived workout-access request.
alter table public.private_live_view_requests
    add column if not exists push_notified_at timestamptz;

comment on column public.notification_devices.device_family is
    'iOS phone versus tablet, used solely for routing personal live-workout approval alerts';
comment on column public.private_live_view_requests.push_notified_at is
    'Last server-side APNs attempt for this users own pending live-view request';
