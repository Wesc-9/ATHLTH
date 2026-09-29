
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type DiscoverRequest = {
  latitude?: number;
  longitude?: number;
  radiusKilometers?: number;
};

type OSMPoint = {
  lat: number;
  lon: number;
};

type OSMMember = {
  type?: string;
  role?: string;
  geometry?: OSMPoint[];
};

type OSMRelation = {
  type?: string;
  id?: number;
  tags?: Record<string, string>;
  members?: OSMMember[];
};

const MIN_DISCOVERY_KM = 0.5;
const MIN_LEADERBOARD_KM = 1.0;
const MAX_ROUTE_KM = 80;
const CACHE_HOURS = 12;
const MAX_RESULT_ROUTES = 40;
const MAX_POINTS_PER_ROUTE = 650;

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

function finiteNumber(
  value: unknown,
  min: number,
  max: number,
): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  return Math.max(min, Math.min(max, value));
}

function haversineMeters(a: OSMPoint, b: OSMPoint): number {
  const earthRadius = 6_371_000;
  const toRad = (degrees: number) => degrees * Math.PI / 180;
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const deltaLat = toRad(b.lat - a.lat);
  const deltaLon = toRad(b.lon - a.lon);

  const h =
    Math.sin(deltaLat / 2) ** 2 +
    Math.cos(lat1) *
      Math.cos(lat2) *
      Math.sin(deltaLon / 2) ** 2;

  return 2 * earthRadius * Math.asin(Math.min(1, Math.sqrt(h)));
}

function polylineLengthMeters(points: OSMPoint[]): number {
  let total = 0;
  for (let index = 1; index < points.length; index += 1) {
    total += haversineMeters(points[index - 1], points[index]);
  }
  return total;
}

function continuousGeometry(
  relation: OSMRelation,
): OSMPoint[] {
  const acceptedRoles = new Set([
    "",
    "main",
    "forward",
    "backward",
  ]);

  const candidates = (relation.members ?? [])
    .filter((member) =>
      member.type === "way" &&
      acceptedRoles.has(member.role ?? "") &&
      Array.isArray(member.geometry) &&
      (member.geometry?.length ?? 0) >= 2
    )
    .map((member) => member.geometry!);

  if (candidates.length === 0) return [];

  const chains: OSMPoint[][] = [];
  let current: OSMPoint[] = [];

  for (const raw of candidates) {
    let segment = raw.slice();

    if (current.length === 0) {
      current = segment;
      continue;
    }

    const tail = current[current.length - 1];
    const firstGap = haversineMeters(tail, segment[0]);
    const lastGap = haversineMeters(
      tail,
      segment[segment.length - 1],
    );

    if (lastGap < firstGap) {
      segment = segment.reverse();
    }

    const gap = haversineMeters(
      current[current.length - 1],
      segment[0],
    );

    if (gap > 900) {
      chains.push(current);
      current = segment;
      continue;
    }

    const first = segment[0];
    const last = current[current.length - 1];
    if (haversineMeters(last, first) < 8) {
      current.push(...segment.slice(1));
    } else {
      current.push(...segment);
    }
  }

  if (current.length > 0) {
    chains.push(current);
  }

  return chains
    .filter((chain) => chain.length >= 2)
    .sort(
      (lhs, rhs) =>
        polylineLengthMeters(rhs) -
        polylineLengthMeters(lhs),
    )[0] ?? [];
}

function simplify(points: OSMPoint[]): OSMPoint[] {
  if (points.length <= MAX_POINTS_PER_ROUTE) {
    return points;
  }

  const stride = Math.ceil(
    points.length / MAX_POINTS_PER_ROUTE,
  );
  const result = points.filter(
    (_, index) =>
      index === 0 ||
      index === points.length - 1 ||
      index % stride === 0,
  );

  if (
    result[result.length - 1] !==
    points[points.length - 1]
  ) {
    result.push(points[points.length - 1]);
  }

  return result;
}

function center(points: OSMPoint[]) {
  const latitude =
    points.reduce((sum, point) => sum + point.lat, 0) /
    points.length;
  const longitude =
    points.reduce((sum, point) => sum + point.lon, 0) /
    points.length;

  return { latitude, longitude };
}

function cellKey(
  latitude: number,
  longitude: number,
): string {
  const step = 0.05;
  const lat = Math.round(latitude / step) * step;
  const lon = Math.round(longitude / step) * step;
  return `v1:${lat.toFixed(2)}:${lon.toFixed(2)}`;
}

function boundingBox(
  latitude: number,
  longitude: number,
  radiusKilometers: number,
) {
  const latDelta = radiusKilometers / 111;
  const lonScale =
    Math.max(
      0.2,
      Math.cos(latitude * Math.PI / 180),
    );
  const lonDelta =
    radiusKilometers / (111 * lonScale);

  return {
    south: latitude - latDelta,
    west: longitude - lonDelta,
    north: latitude + latDelta,
    east: longitude + lonDelta,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Missing authenticated user." }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    return json(
      { error: "ATHLTH backend is unavailable." },
      503,
    );
  }

  const token = authorization.slice(7).trim();
  const admin = createClient(
    supabaseURL,
    serviceRoleKey,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );

  const {
    data: { user },
    error: userError,
  } = await admin.auth.getUser(token);

  if (userError || !user) {
    return json(
      { error: "Your sign-in session is no longer valid." },
      401,
    );
  }

  let body: DiscoverRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const latitude = finiteNumber(
    body.latitude,
    -85,
    85,
  );
  const longitude = finiteNumber(
    body.longitude,
    -180,
    180,
  );
  const radiusKilometers =
    finiteNumber(
      body.radiusKilometers,
      3,
      20,
    ) ?? 12;

  if (latitude == null || longitude == null) {
    return json(
      { error: "Valid map center is required." },
      400,
    );
  }

  const bounds = boundingBox(
    latitude,
    longitude,
    radiusKilometers,
  );
  const key = cellKey(latitude, longitude);

  const { data: cell } = await admin
    .from("public_trail_fetch_cells")
    .select("fetched_at")
    .eq("cell_key", key)
    .maybeSingle();

  const cacheFresh =
    cell?.fetched_at &&
    Date.now() -
      new Date(cell.fetched_at).getTime() <
      CACHE_HOURS * 60 * 60 * 1000;

  let source = "cache";

  if (!cacheFresh) {
    const query = `
[out:json][timeout:22];
relation
  ["type"="route"]
  ["route"~"^(hiking|foot)$"]
  ["name"]
  (${bounds.south},${bounds.west},${bounds.north},${bounds.east});
out body geom qt;
`.trim();

    const configuredOverpassURL =
      Deno.env.get("OVERPASS_API_URL");
    const overpassURLs =
      configuredOverpassURL
        ? [configuredOverpassURL]
        : [
            "https://overpass.private.coffee/api/interpreter",
            "https://overpass-api.de/api/interpreter",
          ];

    try {
      let payload: any = null;
      let lastFailure = "No Overpass endpoint succeeded.";

      for (const overpassURL of overpassURLs) {
        try {
          const response = await fetch(overpassURL, {
            method: "POST",
            headers: {
              "Content-Type":
                "application/x-www-form-urlencoded",
              "Accept": "application/json",
              "User-Agent":
                "ATHLTH/1.4.5 public-trail-discovery",
            },
            body:
              "data=" +
              encodeURIComponent(query),
          });

          if (!response.ok) {
            lastFailure =
              `${overpassURL} returned ${response.status}`;
            continue;
          }

          payload = await response.json();
          break;
        } catch (error) {
          lastFailure =
            error instanceof Error
              ? error.message
              : String(error);
        }
      }

      if (!payload) {
        throw new Error(lastFailure);
      }
      const relations: OSMRelation[] =
        Array.isArray(payload?.elements)
          ? payload.elements.filter(
              (element: OSMRelation) =>
                element?.type === "relation",
            )
          : [];

      const now = new Date().toISOString();
      const writes: Record<string, unknown>[] = [];

      for (const relation of relations) {
        const relationID = relation.id;
        const tags = relation.tags ?? {};
        const name = String(tags.name ?? "").trim();
        const routeKind = String(tags.route ?? "");

        if (
          !relationID ||
          !name ||
          !["hiking", "foot"].includes(routeKind)
        ) {
          continue;
        }

        const fullGeometry =
          continuousGeometry(relation);

        if (fullGeometry.length < 2) {
          continue;
        }

        const distanceKilometers =
          polylineLengthMeters(fullGeometry) / 1000;

        if (
          distanceKilometers < MIN_DISCOVERY_KM ||
          distanceKilometers > MAX_ROUTE_KM
        ) {
          continue;
        }

        const geometry =
          simplify(fullGeometry);
        const midpoint = center(geometry);

        writes.push({
          osm_relation_id: relationID,
          name: name.slice(0, 180),
          route_kind: routeKind,
          network:
            String(tags.network ?? "").slice(0, 32) ||
            null,
          reference:
            String(tags.ref ?? "").slice(0, 80) ||
            null,
          operator_name:
            String(tags.operator ?? "").slice(0, 160) ||
            null,
          symbol:
            String(
              tags["osmc:symbol"] ??
              tags.symbol ??
              "",
            ).slice(0, 160) || null,
          coordinates: geometry.map(
            (point, index) => ({
              latitude: point.lat,
              longitude: point.lon,
              altitude: null,
              sequence: index,
            }),
          ),
          distance_kilometers:
            distanceKilometers,
          center_latitude:
            midpoint.latitude,
          center_longitude:
            midpoint.longitude,
          leaderboard_enabled:
            distanceKilometers >=
            MIN_LEADERBOARD_KM,
          source: "openstreetmap",
          source_updated_at: now,
          last_fetched_at: now,
          updated_at: now,
        });
      }

      if (writes.length > 0) {
        const { error: upsertError } =
          await admin
            .from("public_trails")
            .upsert(
              writes,
              {
                onConflict:
                  "osm_relation_id",
              },
            );

        if (upsertError) {
          throw upsertError;
        }
      }

      await admin
        .from("public_trail_fetch_cells")
        .upsert(
          {
            cell_key: key,
            center_latitude: latitude,
            center_longitude: longitude,
            radius_kilometers:
              radiusKilometers,
            fetched_at: now,
          },
          { onConflict: "cell_key" },
        );

      source = "openstreetmap";
    } catch (error) {
      console.error(
        "Public trail refresh failed; using cache",
        {
          cellKey: key,
          message:
            error instanceof Error
              ? error.message
              : String(error),
        },
      );
      source = "stale_cache";
    }
  }

  const { data: trails, error: trailsError } =
    await admin
      .from("public_trails")
      .select(
        "id,osm_relation_id,name,route_kind,network,reference,operator_name,symbol,coordinates,distance_kilometers,center_latitude,center_longitude,leaderboard_enabled,athlth_verified,source,updated_at",
      )
      .gte(
        "center_latitude",
        bounds.south,
      )
      .lte(
        "center_latitude",
        bounds.north,
      )
      .gte(
        "center_longitude",
        bounds.west,
      )
      .lte(
        "center_longitude",
        bounds.east,
      )
      .gte(
        "distance_kilometers",
        MIN_DISCOVERY_KM,
      )
      .order(
        "athlth_verified",
        { ascending: false },
      )
      .order(
        "distance_kilometers",
        { ascending: true },
      )
      .limit(MAX_RESULT_ROUTES);

  if (trailsError) {
    console.error(
      "Unable to load cached public trails",
      { message: trailsError.message },
    );
    return json(
      { error: "Unable to load trails." },
      500,
    );
  }

  return json({
    trails: trails ?? [],
    source,
    minimumDiscoveryKilometers:
      MIN_DISCOVERY_KM,
    minimumLeaderboardKilometers:
      MIN_LEADERBOARD_KM,
    attribution:
      "© OpenStreetMap contributors",
  });
});
