import { createClient } from "npm:@supabase/supabase-js@2.57.4";

declare const EdgeRuntime: {
  waitUntil(promise: Promise<unknown>): void;
};

type DiscoverRequest = {
  latitude?: number;
  longitude?: number;
  radiusKilometers?: number;
  forceRefresh?: boolean;
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

type OSMWay = {
  type?: string;
  id?: number;
  tags?: Record<string, string>;
  geometry?: OSMPoint[];
};

type OSMTrailElement =
  | OSMRelation
  | OSMWay;

type Bounds = {
  south: number;
  west: number;
  north: number;
  east: number;
};

const MIN_DISCOVERY_KM = 0.5;
const MIN_LEADERBOARD_KM = 1.0;
const MAX_ROUTE_KM = 80;
const CACHE_HOURS = 12;
const EMPTY_CACHE_RETRY_SECONDS = 5 * 60;
const REFRESH_LOCK_SECONDS = 90;
const MAX_RESULT_ROUTES = 48;
const MAX_POINTS_PER_ROUTE = 300;

const json = (
  body: Record<string, unknown>,
  status = 200,
) =>
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
  if (
    typeof value !== "number" ||
    !Number.isFinite(value)
  ) {
    return null;
  }

  return Math.max(
    min,
    Math.min(max, value),
  );
}

function haversineMeters(
  a: OSMPoint,
  b: OSMPoint,
): number {
  const earthRadius = 6_371_000;
  const toRad = (degrees: number) =>
    degrees * Math.PI / 180;
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const deltaLat = toRad(b.lat - a.lat);
  const deltaLon = toRad(b.lon - a.lon);

  const h =
    Math.sin(deltaLat / 2) ** 2 +
    Math.cos(lat1) *
      Math.cos(lat2) *
      Math.sin(deltaLon / 2) ** 2;

  return 2 *
    earthRadius *
    Math.asin(
      Math.min(
        1,
        Math.sqrt(h),
      ),
    );
}

function polylineLengthMeters(
  points: OSMPoint[],
): number {
  let total = 0;

  for (
    let index = 1;
    index < points.length;
    index += 1
  ) {
    total += haversineMeters(
      points[index - 1],
      points[index],
    );
  }

  return total;
}

function continuousGeometry(
  relation: OSMRelation,
): OSMPoint[] {
  const acceptedRoles =
    new Set([
      "",
      "main",
      "forward",
      "backward",
    ]);

  const candidates =
    (relation.members ?? [])
      .filter(
        (member) =>
          member.type === "way" &&
          acceptedRoles.has(
            member.role ?? "",
          ) &&
          Array.isArray(
            member.geometry,
          ) &&
          (member.geometry?.length ?? 0) >= 2,
      )
      .map(
        (member) =>
          member.geometry!,
      );

  if (candidates.length === 0) {
    return [];
  }

  const chains: OSMPoint[][] = [];
  let current: OSMPoint[] = [];

  for (const raw of candidates) {
    let segment = raw.slice();

    if (current.length === 0) {
      current = segment;
      continue;
    }

    const tail =
      current[
        current.length - 1
      ];
    const firstGap =
      haversineMeters(
        tail,
        segment[0],
      );
    const lastGap =
      haversineMeters(
        tail,
        segment[
          segment.length - 1
        ],
      );

    if (lastGap < firstGap) {
      segment = segment.reverse();
    }

    const gap =
      haversineMeters(
        current[
          current.length - 1
        ],
        segment[0],
      );

    if (gap > 900) {
      chains.push(current);
      current = segment;
      continue;
    }

    const first = segment[0];
    const last =
      current[
        current.length - 1
      ];

    if (
      haversineMeters(
        last,
        first,
      ) < 8
    ) {
      current.push(
        ...segment.slice(1),
      );
    } else {
      current.push(...segment);
    }
  }

  if (current.length > 0) {
    chains.push(current);
  }

  return chains
    .filter(
      (chain) =>
        chain.length >= 2,
    )
    .sort(
      (lhs, rhs) =>
        polylineLengthMeters(rhs) -
        polylineLengthMeters(lhs),
    )[0] ?? [];
}

function simplify(
  points: OSMPoint[],
): OSMPoint[] {
  if (
    points.length <=
    MAX_POINTS_PER_ROUTE
  ) {
    return points;
  }

  const stride =
    Math.ceil(
      points.length /
        MAX_POINTS_PER_ROUTE,
    );

  const result =
    points.filter(
      (_, index) =>
        index === 0 ||
        index ===
          points.length - 1 ||
        index % stride === 0,
    );

  const last =
    points[
      points.length - 1
    ];

  if (
    result[
      result.length - 1
    ] !== last
  ) {
    result.push(last);
  }

  return result;
}

function center(
  points: OSMPoint[],
) {
  const latitude =
    points.reduce(
      (sum, point) =>
        sum + point.lat,
      0,
    ) / points.length;

  const longitude =
    points.reduce(
      (sum, point) =>
        sum + point.lon,
      0,
    ) / points.length;

  return {
    latitude,
    longitude,
  };
}

function inferRouteShape(
  points: OSMPoint[],
  distanceKilometers: number,
  roundtripTag: string | undefined,
): string {
  if (roundtripTag === "yes") {
    return "Loop";
  }

  if (points.length < 2) {
    return "Route";
  }

  const endpointDistance =
    haversineMeters(
      points[0],
      points[points.length - 1],
    );
  const threshold =
    Math.max(
      250,
      Math.min(
        700,
        distanceKilometers *
          1000 *
          0.06,
      ),
    );

  return endpointDistance <= threshold
    ? "Loop"
    : "Point to point";
}

function difficultyFromTags(
  tags: Record<string, string>,
): string | null {
  const sac =
    String(tags.sac_scale ?? "")
      .toLowerCase();

  if (!sac) {
    return null;
  }

  if (
    sac === "hiking" ||
    sac === "mountain_hiking"
  ) {
    return sac === "hiking"
      ? "Easy"
      : "Moderate";
  }

  return "Hard";
}

function cellKey(
  latitude: number,
  longitude: number,
  radiusKilometers: number,
): string {
  const step = 0.05;
  const lat =
    Math.round(
      latitude / step,
    ) * step;
  const lon =
    Math.round(
      longitude / step,
    ) * step;
  const radiusBucket =
    radiusKilometers <= 3
      ? 3
      : radiusKilometers <= 6
        ? 6
        : radiusKilometers <= 12
          ? 12
          : 20;

  // Radius is part of the cache key so a previous small-area search
  // cannot incorrectly satisfy a later, larger viewport search.
  return `v3:${lat.toFixed(2)}:${lon.toFixed(2)}:r${radiusBucket}`;
}

function boundingBox(
  latitude: number,
  longitude: number,
  radiusKilometers: number,
): Bounds {
  const latDelta =
    radiusKilometers / 111;
  const lonScale =
    Math.max(
      0.2,
      Math.cos(
        latitude *
          Math.PI / 180,
      ),
    );
  const lonDelta =
    radiusKilometers /
    (111 * lonScale);

  return {
    south:
      latitude -
      latDelta,
    west:
      longitude -
      lonDelta,
    north:
      latitude +
      latDelta,
    east:
      longitude +
      lonDelta,
  };
}


type TrailWrite = Record<
  string,
  unknown
>;

type KartverketRouteGroup = {
  routeNumber: string;
  names: string[];
  operators: string[];
  grades: string[];
  markings: string[];
  surfaces: string[];
  segments: OSMPoint[][];
};

function shouldUseKartverket(
  bounds: Bounds,
): boolean {
  // Turrutebasen is a Norway-only source. A deliberately generous
  // bounding box keeps the check cheap while the WFS itself provides
  // the authoritative national coverage.
  return (
    bounds.north >= 57 &&
    bounds.south <= 72.5 &&
    bounds.east >= 4 &&
    bounds.west <= 32
  );
}

function decodeXMLText(
  value: string,
): string {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/<[^>]+>/g, "")
    .trim();
}

function xmlValues(
  block: string,
  tag: string,
): string[] {
  const expression =
    new RegExp(
      "<app:" +
        tag +
        "\\b[^>]*>([\\s\\S]*?)<\\/app:" +
        tag +
        ">",
      "gi",
    );
  const values: string[] = [];

  for (
    const match
    of block.matchAll(expression)
  ) {
    const value =
      decodeXMLText(
        String(match[1] ?? ""),
      );

    if (value) {
      values.push(value);
    }
  }

  return values;
}

function firstUsefulValue(
  values: string[],
): string | null {
  return (
    values.find(
      (value) => {
        const normalized =
          value
            .trim()
            .toLowerCase();

        return (
          normalized.length > 0 &&
          normalized !== "ukjent" &&
          normalized !== "unknown"
        );
      },
    ) ?? null
  );
}

function parsePosList(
  value: string,
): OSMPoint[] {
  const numbers =
    value
      .trim()
      .split(/\s+/)
      .map(Number)
      .filter(Number.isFinite);

  const points: OSMPoint[] = [];

  // Turrutebasen WFS uses EPSG:4326 with axis order latitude,
  // longitude (south, west, north, east).
  for (
    let index = 0;
    index + 1 < numbers.length;
    index += 2
  ) {
    const lat = numbers[index];
    const lon = numbers[index + 1];

    if (
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180
    ) {
      points.push({
        lat,
        lon,
      });
    }
  }

  return points;
}

function geometryPartsFromGML(
  block: string,
): OSMPoint[][] {
  const expression =
    /<gml:posList\b[^>]*>([\s\S]*?)<\/gml:posList>/gi;
  const result: OSMPoint[][] = [];

  for (
    const match
    of block.matchAll(expression)
  ) {
    const points =
      parsePosList(
        String(match[1] ?? ""),
      );

    if (points.length >= 2) {
      result.push(points);
    }
  }

  return result;
}

function stitchSegments(
  rawSegments: OSMPoint[][],
): OSMPoint[] {
  const pending =
    rawSegments
      .filter(
        (segment) =>
          segment.length >= 2,
      )
      .map(
        (segment) =>
          segment.slice(),
      );

  const chains: OSMPoint[][] = [];
  const maxJoinMeters = 160;

  while (pending.length > 0) {
    let current =
      pending.shift()!;
    let extended = true;

    while (
      extended &&
      pending.length > 0
    ) {
      extended = false;

      const head =
        current[0];
      const tail =
        current[
          current.length - 1
        ];

      let bestIndex = -1;
      let bestGap =
        Number.POSITIVE_INFINITY;
      let bestMode = 0;

      for (
        let index = 0;
        index < pending.length;
        index += 1
      ) {
        const candidate =
          pending[index];
        const first =
          candidate[0];
        const last =
          candidate[
            candidate.length - 1
          ];
        const options = [
          haversineMeters(
            tail,
            first,
          ),
          haversineMeters(
            tail,
            last,
          ),
          haversineMeters(
            head,
            last,
          ),
          haversineMeters(
            head,
            first,
          ),
        ];

        for (
          let mode = 0;
          mode < options.length;
          mode += 1
        ) {
          if (
            options[mode] <
            bestGap
          ) {
            bestGap =
              options[mode];
            bestIndex = index;
            bestMode = mode;
          }
        }
      }

      if (
        bestIndex < 0 ||
        bestGap >
          maxJoinMeters
      ) {
        break;
      }

      let candidate =
        pending.splice(
          bestIndex,
          1,
        )[0];

      switch (bestMode) {
      case 0:
        if (
          haversineMeters(
            current[
              current.length - 1
            ],
            candidate[0],
          ) < 8
        ) {
          candidate =
            candidate.slice(1);
        }
        current.push(
          ...candidate,
        );
        break;

      case 1:
        candidate =
          candidate.reverse();
        if (
          haversineMeters(
            current[
              current.length - 1
            ],
            candidate[0],
          ) < 8
        ) {
          candidate =
            candidate.slice(1);
        }
        current.push(
          ...candidate,
        );
        break;

      case 2:
        if (
          haversineMeters(
            candidate[
              candidate.length - 1
            ],
            current[0],
          ) < 8
        ) {
          candidate =
            candidate.slice(
              0,
              -1,
            );
        }
        current = [
          ...candidate,
          ...current,
        ];
        break;

      case 3:
        candidate =
          candidate.reverse();
        if (
          haversineMeters(
            candidate[
              candidate.length - 1
            ],
            current[0],
          ) < 8
        ) {
          candidate =
            candidate.slice(
              0,
              -1,
            );
        }
        current = [
          ...candidate,
          ...current,
        ];
        break;
      }

      extended = true;
    }

    chains.push(current);
  }

  return (
    chains
      .filter(
        (chain) =>
          chain.length >= 2,
      )
      .sort(
        (lhs, rhs) =>
          polylineLengthMeters(
            rhs,
          ) -
          polylineLengthMeters(
            lhs,
          ),
      )[0] ?? []
  );
}

function kartverketDifficulty(
  value: string | null,
): string | null {
  switch (
    value
      ?.trim()
      .toUpperCase()
  ) {
  case "G":
    return "Easy";
  case "B":
    return "Moderate";
  case "R":
    return "Hard";
  case "S":
    return "Expert";
  default:
    return null;
  }
}

function stableHash32(
  value: string,
): number {
  let hash =
    0x811c9dc5;

  for (
    let index = 0;
    index < value.length;
    index += 1
  ) {
    hash ^=
      value.charCodeAt(index);
    hash =
      Math.imul(
        hash,
        0x01000193,
      );
  }

  return hash >>> 0;
}

function kartverketSourceID(
  routeNumber: string,
): number {
  // Reserve a bigint-safe namespace far away from real OSM relation/way IDs.
  return (
    -8_000_000_000_000_000 -
    stableHash32(
      routeNumber,
    )
  );
}

function normalizedTrailName(
  value: unknown,
): string {
  return String(
    value ?? "",
  )
    .trim()
    .toLowerCase()
    .normalize("NFKD")
    .replace(
      /[\u0300-\u036f]/g,
      "",
    )
    .replace(
      /[^a-z0-9]+/g,
      " ",
    )
    .trim();
}

function mergeSecondaryTrails(
  primary: TrailWrite[],
  secondary: TrailWrite[],
): TrailWrite[] {
  const result =
    primary.slice();

  for (
    const candidate
    of secondary
  ) {
    const candidateName =
      normalizedTrailName(
        candidate.name,
      );
    const candidateLat =
      Number(
        candidate.center_latitude,
      );
    const candidateLon =
      Number(
        candidate.center_longitude,
      );

    const duplicate =
      result.some(
        (existing) => {
          if (
            normalizedTrailName(
              existing.name,
            ) !==
            candidateName
          ) {
            return false;
          }

          const existingLat =
            Number(
              existing
                .center_latitude,
            );
          const existingLon =
            Number(
              existing
                .center_longitude,
            );

          if (
            !Number.isFinite(
              candidateLat,
            ) ||
            !Number.isFinite(
              candidateLon,
            ) ||
            !Number.isFinite(
              existingLat,
            ) ||
            !Number.isFinite(
              existingLon,
            )
          ) {
            return true;
          }

          return (
            haversineMeters(
              {
                lat:
                  candidateLat,
                lon:
                  candidateLon,
              },
              {
                lat:
                  existingLat,
                lon:
                  existingLon,
              },
            ) < 1_000
          );
        },
      );

    if (!duplicate) {
      result.push(
        candidate,
      );
    }
  }

  return result;
}

async function fetchKartverketTrails(
  bounds: Bounds,
): Promise<TrailWrite[]> {
  if (
    !shouldUseKartverket(
      bounds,
    )
  ) {
    return [];
  }

  const params =
    new URLSearchParams({
      service: "WFS",
      version: "2.0.0",
      request: "GetFeature",
      typeNames:
        "app:Fotrute",
      bbox:
        [
          bounds.south,
          bounds.west,
          bounds.north,
          bounds.east,
        ].join(",") +
        ",urn:ogc:def:crs:EPSG::4326",
      count: "1200",
    });
  const url =
    "https://wfs.geonorge.no/skwms1/wfs.turogfriluftsruter?" +
    params.toString();

  try {
    const response =
      await fetch(
        url,
        {
          method: "GET",
          signal:
            AbortSignal.timeout(
              7_000,
            ),
          headers: {
            "Accept":
              "application/gml+xml, text/xml, application/xml",
            "User-Agent":
              "ATHLTH/1.5 trail-discovery (Kartverket Turrutebasen)",
          },
        },
      );

    if (!response.ok) {
      console.warn(
        "Kartverket Turrutebasen request failed",
        {
          status:
            response.status,
        },
      );
      return [];
    }

    const xml =
      await response.text();
    const featureBlocks =
      xml.match(
        /<app:Fotrute\b[\s\S]*?<\/app:Fotrute>/gi,
      ) ?? [];
    const groups =
      new Map<
        string,
        KartverketRouteGroup
      >();

    for (
      const feature
      of featureBlocks
    ) {
      const geometryParts =
        geometryPartsFromGML(
          feature,
        );

      if (
        geometryParts.length ===
        0
      ) {
        continue;
      }

      const infoBlocks =
        feature.match(
          /<app:FotruteInfo\b[\s\S]*?<\/app:FotruteInfo>/gi,
        ) ?? [feature];
      const featureSurfaces =
        xmlValues(
          feature,
          "underlagstype",
        );
      const featureMarkings =
        xmlValues(
          feature,
          "merking",
        );

      for (
        const info
        of infoBlocks
      ) {
        const routeNumber =
          firstUsefulValue(
            xmlValues(
              info,
              "rutenummer",
            ),
          ) ??
          firstUsefulValue(
            xmlValues(
              feature,
              "rutenummer",
            ),
          );

        if (!routeNumber) {
          continue;
        }

        const existing =
          groups.get(
            routeNumber,
          ) ?? {
            routeNumber,
            names: [],
            operators: [],
            grades: [],
            markings: [],
            surfaces: [],
            segments: [],
          };

        existing.names.push(
          ...xmlValues(
            info,
            "rutenavn",
          ),
        );
        existing.operators.push(
          ...xmlValues(
            info,
            "vedlikeholdsansvarlig",
          ),
        );
        existing.grades.push(
          ...xmlValues(
            info,
            "gradering",
          ),
        );
        existing.markings.push(
          ...featureMarkings,
        );
        existing.surfaces.push(
          ...featureSurfaces,
        );
        existing.segments.push(
          ...geometryParts,
        );

        groups.set(
          routeNumber,
          existing,
        );
      }
    }

    const now =
      new Date()
        .toISOString();
    const writes:
      TrailWrite[] = [];

    for (
      const group
      of groups.values()
    ) {
      const name =
        firstUsefulValue(
          group.names,
        );

      // Avoid turning technical route IDs into user-facing trail names.
      // Turrutebasen remains a high-quality secondary source for named routes.
      if (!name) {
        continue;
      }

      const fullGeometry =
        stitchSegments(
          group.segments,
        );

      if (
        fullGeometry.length < 2
      ) {
        continue;
      }

      const distanceKilometers =
        polylineLengthMeters(
          fullGeometry,
        ) / 1000;

      if (
        distanceKilometers <
          MIN_DISCOVERY_KM ||
        distanceKilometers >
          MAX_ROUTE_KM
      ) {
        continue;
      }

      const geometry =
        simplify(
          fullGeometry,
        );
      const midpoint =
        center(
          geometry,
        );
      const marking =
        firstUsefulValue(
          group.markings,
        );
      const operatorName =
        firstUsefulValue(
          group.operators,
        );
      const surface =
        firstUsefulValue(
          group.surfaces,
        );
      const grade =
        firstUsefulValue(
          group.grades,
        );

      writes.push({
        osm_relation_id:
          kartverketSourceID(
            group.routeNumber,
          ),
        name:
          name.slice(
            0,
            180,
          ),
        route_kind:
          "foot",
        network:
          "no:turrutebasen",
        reference:
          group.routeNumber
            .slice(
              0,
              80,
            ),
        operator_name:
          operatorName
            ?.slice(
              0,
              160,
            ) ?? null,
        symbol:
          marking
            ?.slice(
              0,
              160,
            ) ?? null,
        route_shape:
          inferRouteShape(
            geometry,
            distanceKilometers,
            undefined,
          ),
        surface_summary:
          surface
            ?.slice(
              0,
              80,
            ) ?? null,
        difficulty:
          kartverketDifficulty(
            grade,
          ),
        osm_description:
          null,
        website:
          null,
        estimated_run_seconds:
          distanceKilometers *
          360,
        estimated_walk_seconds:
          distanceKilometers *
          720,
        coordinates:
          geometry.map(
            (
              point,
              index,
            ) => ({
              latitude:
                point.lat,
              longitude:
                point.lon,
              altitude: null,
              sequence:
                index,
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
        source:
          "kartverket_turrutebasen",
        source_updated_at:
          now,
        last_fetched_at:
          now,
        updated_at:
          now,
      });
    }

    return writes;
  } catch (error) {
    console.warn(
      "Kartverket Turrutebasen unavailable",
      {
        message:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );

    // This is deliberately a soft failure. OpenStreetMap remains the
    // primary source and Explore must continue to work if WFS is slow/down.
    return [];
  }
}

async function loadCachedTrails(
  admin: ReturnType<
    typeof createClient
  >,
  bounds: Bounds,
) {
  const {
    data,
    error,
  } =
    await admin
      .from("public_trails")
      .select(
        "id,osm_relation_id,name,route_kind,network,reference,operator_name,symbol,coordinates,distance_kilometers,center_latitude,center_longitude,leaderboard_enabled,athlth_verified,source,route_shape,surface_summary,difficulty,osm_description,website,estimated_run_seconds,estimated_walk_seconds,elevation_gain_meters,elevation_loss_meters,min_elevation_meters,max_elevation_meters,average_grade_percent,max_grade_percent,elevation_profile,updated_at",
      )
      // Return routes whose geometry bounds intersect the searched
      // viewport. Center-only filtering misses long routes that pass through
      // the visible map while their midpoint sits outside it.
      .lte(
        "min_latitude",
        bounds.north,
      )
      .gte(
        "max_latitude",
        bounds.south,
      )
      .lte(
        "min_longitude",
        bounds.east,
      )
      .gte(
        "max_longitude",
        bounds.west,
      )
      .gte(
        "distance_kilometers",
        MIN_DISCOVERY_KM,
      )
      .order(
        "athlth_verified",
        {
          ascending: false,
        },
      )
      .order(
        "distance_kilometers",
        {
          ascending: true,
        },
      )
      .limit(
        MAX_RESULT_ROUTES,
      );

  if (error) {
    throw error;
  }

  return data ?? [];
}

async function refreshCell(
  admin: ReturnType<
    typeof createClient
  >,
  key: string,
  latitude: number,
  longitude: number,
  radiusKilometers: number,
  bounds: Bounds,
  refreshKartverket: boolean,
) {
  const query = `
[out:json][timeout:15];
(
  relation
    ["type"="route"]
    ["route"~"^(hiking|foot)$"]
    ["name"]
    (${bounds.south},${bounds.west},${bounds.north},${bounds.east});
  relation
    ["type"="route"]
    ["route"~"^(hiking|foot)$"]
    ["ref"]
    (${bounds.south},${bounds.west},${bounds.north},${bounds.east});
  way
    ["highway"~"^(path|footway|track|bridleway)$"]
    ["name"]
    (${bounds.south},${bounds.west},${bounds.north},${bounds.east});
  way
    ["highway"~"^(path|footway|track|bridleway)$"]
    ["ref"]
    (${bounds.south},${bounds.west},${bounds.north},${bounds.east});
);
out body geom qt 160;
`.trim();

  // Start the Norway-only secondary source in parallel with Overpass.
  // Its 7 s timeout cannot block or replace the primary OSM result.
  const kartverketPromise =
    refreshKartverket &&
    shouldUseKartverket(
      bounds,
    )
      ? fetchKartverketTrails(
          bounds,
        )
      : Promise.resolve(
          [] as TrailWrite[],
        );

  const configuredOverpassURL =
    Deno.env.get(
      "OVERPASS_API_URL",
    );

  const fallbackOverpassURLs = [
    "https://overpass.private.coffee/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
  ];

  const overpassURLs =
    Array.from(
      new Set(
        [
          configuredOverpassURL,
          ...fallbackOverpassURLs,
        ].filter(
          (value):
            value is string =>
              Boolean(value),
        ),
      ),
    );

  try {
    let payload: any = null;
    let lastFailure =
      "No Overpass endpoint succeeded.";

    for (
      const overpassURL
      of overpassURLs
    ) {
      try {
        const response =
          await fetch(
            overpassURL,
            {
              method: "POST",
              signal:
                AbortSignal.timeout(
                  9_000,
                ),
              headers: {
                "User-Agent":
                  "ATHLTH/1.5 public-trail-cache",
                "Accept":
                  "application/json",
                "Content-Type":
                  "application/x-www-form-urlencoded; charset=UTF-8",
              },
              body:
                "data=" +
                encodeURIComponent(
                  query,
                ),
            },
          );

        if (!response.ok) {
          lastFailure =
            `${overpassURL} returned ${response.status}`;
          continue;
        }

        payload =
          await response.json();
        break;
      } catch (error) {
        lastFailure =
          error instanceof Error
            ? error.message
            : String(error);
      }
    }

    if (!payload) {
      console.warn(
        "OpenStreetMap trail discovery unavailable; trying secondary source",
        {
          message:
            lastFailure,
        },
      );
    }

    const elements:
      OSMTrailElement[] =
        Array.isArray(
          payload?.elements,
        )
          ? payload.elements
              .filter(
                (
                  element:
                    OSMTrailElement,
                ) =>
                  element?.type ===
                    "relation" ||
                  element?.type ===
                    "way",
              )
          : [];

    const now =
      new Date()
        .toISOString();

    const writes:
      Record<
        string,
        unknown
      >[] = [];

    for (
      const element
      of elements
    ) {
      const rawID =
        element.id;
      const tags =
        element.tags ?? {};
      const name =
        String(
          tags.name ??
          tags.ref ??
          "",
        ).trim();

      const routeKind =
        element.type ===
          "relation"
          ? String(
              tags.route ?? "",
            )
          : "foot";

      const access =
        String(
          tags.access ?? "",
        ).toLowerCase();
      const footAccess =
        String(
          tags.foot ?? "",
        ).toLowerCase();

      if (
        !rawID ||
        !name ||
        ![
          "hiking",
          "foot",
        ].includes(
          routeKind,
        ) ||
        (
          [
            "no",
            "private",
          ].includes(access) &&
          ![
            "yes",
            "designated",
            "permissive",
          ].includes(footAccess)
        )
      ) {
        continue;
      }

      // Keep relation IDs positive and encode OSM way IDs as negative values.
      // This preserves the existing unique bigint key without a schema change.
      const sourceID =
        element.type ===
          "way"
          ? -Math.abs(rawID)
          : rawID;

      const fullGeometry =
        element.type ===
          "relation"
          ? continuousGeometry(
              element as
                OSMRelation,
            )
          : (
              (element as OSMWay)
                .geometry ??
              []
            );

      if (
        fullGeometry.length < 2
      ) {
        continue;
      }

      const distanceKilometers =
        polylineLengthMeters(
          fullGeometry,
        ) / 1000;

      if (
        distanceKilometers <
          MIN_DISCOVERY_KM ||
        distanceKilometers >
          MAX_ROUTE_KM
      ) {
        continue;
      }

      const geometry =
        simplify(
          fullGeometry,
        );
      const midpoint =
        center(
          geometry,
        );

      writes.push({
        osm_relation_id:
          sourceID,
        name:
          name.slice(
            0,
            180,
          ),
        route_kind:
          routeKind,
        network:
          String(
            tags.network ?? "",
          ).slice(
            0,
            32,
          ) || null,
        reference:
          String(
            tags.ref ?? "",
          ).slice(
            0,
            80,
          ) || null,
        operator_name:
          String(
            tags.operator ?? "",
          ).slice(
            0,
            160,
          ) || null,
        symbol:
          String(
            tags[
              "osmc:symbol"
            ] ??
            tags.symbol ??
            "",
          ).slice(
            0,
            160,
          ) || null,
        route_shape:
          inferRouteShape(
            geometry,
            distanceKilometers,
            tags.roundtrip,
          ),
        surface_summary:
          String(
            tags.surface ?? "",
          ).slice(
            0,
            80,
          ) || null,
        difficulty:
          difficultyFromTags(tags),
        osm_description:
          String(
            tags.description ?? "",
          ).slice(
            0,
            500,
          ) || null,
        website:
          String(
            tags.website ??
            tags.url ??
            "",
          ).slice(
            0,
            500,
          ) || null,
        estimated_run_seconds:
          distanceKilometers * 360,
        estimated_walk_seconds:
          distanceKilometers * 720,
        coordinates:
          geometry.map(
            (
              point,
              index,
            ) => ({
              latitude:
                point.lat,
              longitude:
                point.lon,
              altitude: null,
              sequence:
                index,
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
        source:
          "openstreetmap",
        source_updated_at:
          now,
        last_fetched_at:
          now,
        updated_at:
          now,
      });
    }

    const kartverketWrites =
      await kartverketPromise;
    const combinedWrites =
      mergeSecondaryTrails(
        writes,
        kartverketWrites,
      );

    if (
      !payload &&
      combinedWrites.length === 0
    ) {
      throw new Error(
        lastFailure,
      );
    }

    if (
      combinedWrites.length > 0
    ) {
      const {
        error:
          upsertError,
      } =
        await admin
          .from(
            "public_trails",
          )
          .upsert(
            combinedWrites,
            {
              onConflict:
                "osm_relation_id",
            },
          );

      if (
        upsertError
      ) {
        throw upsertError;
      }
    }

    const {
      error:
        cellError,
    } =
      await admin
        .from(
          "public_trail_fetch_cells",
        )
        .upsert(
          {
            cell_key:
              key,
            center_latitude:
              latitude,
            center_longitude:
              longitude,
            radius_kilometers:
              radiusKilometers,
            fetched_at:
              now,
            refresh_started_at:
              null,
            last_error:
              null,
            last_success_count:
              combinedWrites.length,
          },
          {
            onConflict:
              "cell_key",
          },
        );

    if (cellError) {
      throw cellError;
    }
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    console.error(
      "Public trail background refresh failed",
      {
        cellKey: key,
        message,
      },
    );

    await admin
      .from(
        "public_trail_fetch_cells",
      )
      .update({
        refresh_started_at:
          null,
        last_error:
          message.slice(
            0,
            1000,
          ),
      })
      .eq(
        "cell_key",
        key,
      );
  }
}

Deno.serve(
  async (
    req: Request,
  ) => {
    if (
      req.method !== "POST"
    ) {
      return json(
        {
          error:
            "Method not allowed.",
        },
        405,
      );
    }

    const authorization =
      req.headers.get(
        "Authorization",
      );

    if (
      !authorization
        ?.startsWith(
          "Bearer ",
        )
    ) {
      return json(
        {
          error:
            "Missing authenticated user.",
        },
        401,
      );
    }

    const supabaseURL =
      Deno.env.get(
        "SUPABASE_URL",
      );
    const serviceRoleKey =
      Deno.env.get(
        "SUPABASE_SERVICE_ROLE_KEY",
      );

    if (
      !supabaseURL ||
      !serviceRoleKey
    ) {
      return json(
        {
          error:
            "ATHLTH backend is unavailable.",
        },
        503,
      );
    }

    const token =
      authorization
        .slice(7)
        .trim();

    const admin =
      createClient(
        supabaseURL,
        serviceRoleKey,
        {
          auth: {
            autoRefreshToken:
              false,
            persistSession:
              false,
          },
        },
      );

    const {
      data: {
        user,
      },
      error:
        userError,
    } =
      await admin
        .auth
        .getUser(
          token,
        );

    if (
      userError ||
      !user
    ) {
      return json(
        {
          error:
            "Your sign-in session is no longer valid.",
        },
        401,
      );
    }

    let body:
      DiscoverRequest;

    try {
      body =
        await req.json();
    } catch {
      return json(
        {
          error:
            "Invalid request body.",
        },
        400,
      );
    }

    const latitude =
      finiteNumber(
        body.latitude,
        -85,
        85,
      );
    const longitude =
      finiteNumber(
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
    const forceRefresh =
      body.forceRefresh === true;

    if (
      latitude == null ||
      longitude == null
    ) {
      return json(
        {
          error:
            "Valid map center is required.",
        },
        400,
      );
    }

    const bounds =
      boundingBox(
        latitude,
        longitude,
        radiusKilometers,
      );

    const key =
      cellKey(
        latitude,
        longitude,
        radiusKilometers,
      );

    const [
      cellResult,
      initialCachedTrails,
    ] =
      await Promise.all([
        admin
          .from(
            "public_trail_fetch_cells",
          )
          .select(
            "fetched_at,refresh_started_at,last_success_count,last_error",
          )
          .eq(
            "cell_key",
            key,
          )
          .maybeSingle(),
        loadCachedTrails(
          admin,
          bounds,
        ),
      ]);

    const cell =
      cellResult.data;

    const cacheAgeMilliseconds =
      cell?.fetched_at
        ? Date.now() -
          new Date(
            cell.fetched_at,
          ).getTime()
        : null;

    const lastSuccessCount =
      Number(
        cell?.last_success_count ??
        0,
      );
    const allowedCacheAge =
      lastSuccessCount > 0
        ? CACHE_HOURS *
          60 *
          60 *
          1000
        : EMPTY_CACHE_RETRY_SECONDS *
          1000;

    const sourceCacheFresh =
      cacheAgeMilliseconds != null &&
      cacheAgeMilliseconds >= 0 &&
      cacheAgeMilliseconds <
        allowedCacheAge;

    const cacheFresh =
      !forceRefresh &&
      sourceCacheFresh;

    const refreshAgeMilliseconds =
      cell?.refresh_started_at
        ? Date.now() -
          new Date(
            cell.refresh_started_at,
          ).getTime()
        : null;

    let isRefreshing =
      refreshAgeMilliseconds != null &&
      refreshAgeMilliseconds >= 0 &&
      refreshAgeMilliseconds <
        REFRESH_LOCK_SECONDS *
        1000;

    let refreshScheduled =
      false;
    let synchronousRefreshAttempted =
      false;

    if (
      !cacheFresh &&
      !isRefreshing
    ) {
      const now =
        new Date()
          .toISOString();

      const {
        error:
          claimError,
      } =
        await admin
          .from(
            "public_trail_fetch_cells",
          )
          .upsert(
            {
              cell_key:
                key,
              center_latitude:
                latitude,
              center_longitude:
                longitude,
              radius_kilometers:
                radiusKilometers,
              refresh_started_at:
                now,
              last_error:
                null,
            },
            {
              onConflict:
                "cell_key",
            },
          );

      if (
        !claimError
      ) {
        isRefreshing =
          true;
        refreshScheduled =
          true;

        if (
          forceRefresh ||
          initialCachedTrails.length === 0
        ) {
          // A user-requested area search should return the refreshed result,
          // and a cold cache needs one synchronous population pass.
          synchronousRefreshAttempted =
            true;

          await refreshCell(
            admin,
            key,
            latitude,
            longitude,
            radiusKilometers,
            bounds,
            !sourceCacheFresh,
          );

          isRefreshing =
            false;
          refreshScheduled =
            false;
        } else {
          EdgeRuntime
            .waitUntil(
              refreshCell(
                admin,
                key,
                latitude,
                longitude,
                radiusKilometers,
                bounds,
                !sourceCacheFresh,
              ),
            );
        }
      } else {
        console.error(
          "Unable to claim trail refresh",
          {
            cellKey:
              key,
            message:
              claimError.message,
          },
        );
      }
    }

    const cachedTrails =
      synchronousRefreshAttempted
        ? await loadCachedTrails(
            admin,
            bounds,
          )
        : initialCachedTrails;

    const source =
      synchronousRefreshAttempted &&
      cachedTrails.length > 0
        ? "fresh"
        : cacheFresh
          ? "cache"
          : cachedTrails.length > 0
            ? "stale_cache"
            : isRefreshing
              ? "warming"
              : "empty_cache";

    return json({
      trails:
        cachedTrails,
      source,
      isRefreshing,
      refreshScheduled,
      cacheAgeSeconds:
        cacheAgeMilliseconds == null
          ? null
          : Math.max(
              0,
              Math.round(
                cacheAgeMilliseconds /
                  1000,
              ),
            ),
      minimumDiscoveryKilometers:
        MIN_DISCOVERY_KM,
      minimumLeaderboardKilometers:
        MIN_LEADERBOARD_KM,
      attribution:
        cachedTrails.some(
          (trail: { source?: string }) =>
            trail.source ===
            "kartverket_turrutebasen",
        )
          ? "© OpenStreetMap contributors · © Kartverket"
          : "© OpenStreetMap contributors",
    });
  },
);
