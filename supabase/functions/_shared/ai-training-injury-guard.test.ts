import { conflictsWithInjuryRestrictions } from "./ai-training-injury-guard.ts";

const session = (name: string, kind: string, exercise: string) => ({
  weeks: [{ days: [{ sessions: [{
    title: name, kind,
    exercises: [{ name: exercise }],
    blocks: [{ title: exercise }]
  }] }] }]
});

Deno.test("explicitly forbidden Norwegian knebøy rejects English squats", () => {
  if (!conflictsWithInjuryRestrictions(
    session("Strength", "strength", "Barbell squats"),
    ["Knebøy"], null
  )) throw new Error("Forbidden squat was not rejected");
});

Deno.test("consented lower-body ban blocks running independently of workout title", () => {
  if (!conflictsWithInjuryRestrictions(
    session("4x4 intervals", "running", "Intervals"),
    [], "Mandatory restriction: No lower-body training."
  )) throw new Error("Running was not blocked");
});

Deno.test("no unrelated workouts are rejected by knee exclusion", () => {
  if (conflictsWithInjuryRestrictions(
    session("Upper body", "strength", "Seated shoulder press"),
    ["Knebøy"], "Mandatory restriction: Avoid affected area."
  )) throw new Error("Safe-looking upper-body description was rejected");
});

Deno.test("missing consented restriction does not trigger hidden constraints", () => {
  if (conflictsWithInjuryRestrictions(
    session("Intervals", "running", "Running"),
    [], null
  )) throw new Error("Invented a restriction when none was sent");
});

Deno.test("forbidden lower-body exercise in individual timeline block is rejected", () => {
  if (!conflictsWithInjuryRestrictions(
    { weeks: [{ days: [{ sessions: [{
      kind: "strength", title: "Workout", exercises: [],
      blocks: [{ title: "Jumping lunges" }]
    }] }] }] },
    ["Utfall"], null
  )) throw new Error("Did not scan individual timeline blocks");
});
