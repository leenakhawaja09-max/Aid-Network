# Supabase setup — Live Mission & PostGIS (CAN / Rapid Aid)

Follow these steps in the [Supabase Dashboard](https://supabase.com/dashboard) for project `bturoqldvwpdmxxmxgdu` (or your project).

## 1. Enable PostGIS

1. **Database** → **Extensions**
2. Search **postgis** → **Enable**
3. Confirm schema is `extensions` (default on Supabase)

Spatial functions use **longitude first** in `ST_MakePoint(lng, lat)`.

## 2. Run SQL migrations (order)

In **SQL Editor**, run in order:

1. Base tables (`profiles`, `requests`) if not already created
2. `supabase_pitches.sql`
3. `supabase_schema_updates.sql`
4. `supabase_mutual_agreement.sql`
5. **`supabase_live_mission.sql`** ← PostGIS column, RPC, `mission_events`, `active_trips`, RLS
6. **`supabase_connection_fix.sql`** ← RLS for helpers + `security definer` discovery (fixes “connection failed”)

## 3. Verify RPC

```sql
select * from public.get_requests_in_radius(24.8607, 67.0011, 16093.4);
-- ~10 miles in meters
```

## 4. Realtime replication

**Database** → **Replication** (or run SQL in `supabase_live_mission.sql`):

| Table | Purpose |
|--------|---------|
| `requests` | Discovery feed |
| `pitches` | Incoming pitches |
| `profiles` | Helper profile updates |
| `active_trips` | Live helper GPS for requester map |
| `mission_events` | Timeline stepper |

Ensure each table appears under **supabase_realtime** publication.

## 5. Authentication URL (mobile)

**Authentication** → **URL Configuration**

- Site URL: `io.supabase.rapidaid://login-callback`
- Redirect URLs: same

**Confirm signup** template: include `{{ .Token }}` for in-app OTP.

## 6. Row Level Security checklist

After migrations, confirm RLS is **enabled** on:

- `pitches`, `requests`, `profiles`, `mission_events`, `active_trips`

Policies in `supabase_live_mission.sql`:

- **mission_events**: requester or assigned helper can read; actors can insert their own events
- **active_trips**: requester + helper can read; only helper can upsert coordinates

Tighten dev-wide `using (true)` policies on `pitches` before production.

## 7. Storage (avatars)

**Storage** → bucket `avatars` (public or signed URLs per your profile screen).

## 8. Email rate limits

Free tier: ~4 auth emails/hour. Use OTP in app; delete test users under **Authentication → Users** when re-testing signup.

## 9. Vercel web deploy

See **`VERCEL_DEPLOY.md`**. Root directory must be **`rapid_aid`**, output **`build/web`**. Add your Vercel URL to Supabase Auth URL settings.

## 10. Maps / APIs (Flutter)

- **Maps tiles**: OpenStreetMap (no Google Maps SDK billing)
- **Optional**: Google Directions API key via `--dart-define=GOOGLE_MAPS_API_KEY=...` for driving ETA only
- **Android emulator**: device `localhost` for a machine-hosted API → `10.0.2.2` (see `lib/config/emulator_hosts.dart`)

## 10. Mission status values (requests.status)

| Status | Meaning |
|--------|---------|
| `created` | Request posted |
| `pending` | Awaiting helpers |
| `pitched` | At least one pitch |
| `helper_selected` | Requester chose helper (awaiting ack) |
| `accepted` | Helper confirmed |
| `in_progress` | Helper en route |
| `arriving` | Helper at location |
| `completed` | Mission done |

Legacy values (`open`, `urgent`, `in-progress`) are still mapped in the Flutter app.
