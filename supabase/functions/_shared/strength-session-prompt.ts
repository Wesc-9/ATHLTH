export type StrengthCandidate = {
  exerciseID: string;
  name: string;
  bodyPart?: string | null;
  primaryMuscles?: string[];
  secondaryMuscles?: string[];
  equipment?: string[];
  category?: string | null;
  difficulty?: string | null;
};

/** Short provider IDs avoid sending the original UUIDs twice (input/schema).
 * The mapping stays on the server; clients still receive real library IDs. */
export function compactStrengthCandidates(candidates: StrengthCandidate[]) {
  const references = new Map<string, string>();
  const compact: Record<string, unknown>[] = [];
  for (const candidate of candidates.slice(0, 40)) {
    const reference = `e${compact.length + 1}`;
    const item = {
      exerciseID: reference,
      name: candidate.name.slice(0, 80),
      bodyPart: candidate.bodyPart?.slice(0, 30) ?? null,
      primaryMuscles: candidate.primaryMuscles?.slice(0, 3).map(v => v.slice(0, 24)) ?? [],
      equipment: candidate.equipment?.slice(0, 2).map(v => v.slice(0, 30)) ?? [],
    };
    if (JSON.stringify([...compact, item]).length > 6000) break;
    compact.push(item);
    references.set(reference, candidate.exerciseID);
  }
  return { candidates: compact, references };
}
