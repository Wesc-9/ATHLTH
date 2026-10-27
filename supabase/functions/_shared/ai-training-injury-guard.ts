/**
 * Secondary guard for ATHLTH Coach plans. A generative model's instruction
 * following is not a safety guarantee. Explicit no-go exercises must be
 * rejected (not silently substituted) before they reach a client.
 *
 * This is a conservative lexical guard, not clinical clearance.
 */
const synonyms: string[][] = [
  ["knebøy", "squat", "squats"],
  ["utfall", "lunge", "lunges"],
  ["markløft", "deadlift", "deadlifts"],
  ["beinpress", "benpress", "leg press"],
  ["løping", "løp", "running", "run", "jogging"],
  ["gange", "gåtur", "gåing", "walking", "walk"],
  ["hopping", "hopp", "jump", "jumping", "jumps"],
  ["sykling", "sykkel", "cycling", "bike", "biking"],
  ["tåhev", "calf raise", "calf raises"],
  ["step up", "step-ups", "step ups"],
  ["burpee", "burpees"]
];

function normalize(input: unknown): string {
  return String(input ?? "")
    .toLocaleLowerCase("nb-NO")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9æøå]+/g, " ")
    .trim();
}

function prohibited(label: unknown, forbidden: string): boolean {
  const title = " " + normalize(label) + " ";
  const needle = normalize(forbidden);
  if (needle.length < 2) return false;
  const aliasGroup = synonyms.find((group) => group.some(
    (entry) => normalize(entry) === needle
  ));
  return (aliasGroup ?? [needle]).some((alias) =>
    title.includes(" " + normalize(alias) + " ")
  );
}

export function conflictsWithInjuryRestrictions(
  program: unknown,
  excludedMovements: string[],
  injurySafetyNotes: string | null | undefined
): boolean {
  const noLowerBody = Boolean(
    injurySafetyNotes &&
    /no lower.body training|avoid lower.body|do not load.*lower.body|ikke belast.*underkropp/i.test(
      injurySafetyNotes
    )
  );
  const blocked = [
    ...excludedMovements.filter((name) => typeof name === "string"),
    ...(noLowerBody ? [
      "knebøy", "utfall", "markløft", "beinpress",
      "løping", "gange", "hopping", "sykling", "tåhev",
      "step up", "burpee"
    ] : [])
  ];
  if (blocked.length === 0) return false;
  const weeks = (program as { weeks?: unknown[] } | null)?.weeks;
  for (const week of Array.isArray(weeks) ? weeks : []) {
    const days = (week as { days?: unknown[] })?.days;
    for (const day of Array.isArray(days) ? days : []) {
      const sessions = (day as { sessions?: unknown[] })?.sessions;
      for (const raw of Array.isArray(sessions) ? sessions : []) {
        const session = raw as {
          title?: string; kind?: string;
          exercises?: { name?: string }[];
          blocks?: { title?: string }[];
        };
        const labels = [
          session.title,
          session.kind,
          ...(session.exercises ?? []).map((exercise) => exercise.name),
          ...(session.blocks ?? []).map((block) => block.title)
        ];
        if (labels.some((label) =>
          blocked.some((name) => prohibited(label, name))
        )) return true;
      }
    }
  }
  return false;
}
