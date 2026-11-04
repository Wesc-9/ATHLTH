import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { compactStrengthCandidates } from './strength-session-prompt.ts';
let handler: (req: Request) => Promise<Response>;
let providerCalls = 0;
const admin = {
  auth: { getUser: async () => ({ data: { user: { id: 'test-user' } }, error: null }) },
  from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({
    data: { status: 'active', current_period_ends_at: null }, error: null,
  }) }) }) }),
  rpc: async () => ({ data: [{ allowed: true }], error: null }),
};
const source = readFileSync(new URL('../generate-strength-session/index.ts', import.meta.url), 'utf8')
  .replace(/^import .*;\n/gm, '');
const execute = new Function('Deno', 'fetch', 'createClient', 'enforceAIRequestBudget', 'compactStrengthCandidates', stripTypeScriptTypes(source));
execute({ env: { get: () => 'test-only-value' }, serve: (callback: typeof handler) => { handler = callback; } },
  async (_url: string, options: { body: string }) => {
    providerCalls++;
    const request = JSON.parse(options.body);
    assert.equal(request.max_output_tokens, 1600);
    const context = JSON.parse(request.input);
    assert.equal(context.focusBodyPart, 'Biceps');
    assert.ok(JSON.stringify(context.candidates).length <= 6000);
    assert.ok(context.candidates.length >= 1);
    assert.ok(request.input.length < 10000);
    return Response.json({ output_text: JSON.stringify({ title: 'Arm session', summary: 'Test', estimatedMinutes: 45,
      exercises: context.candidates.slice(0, context.exerciseCount).map((c: { exerciseID: string }) => ({
        exerciseID: c.exerciseID, sets: 3, reps: 10, restSeconds: 60, targetRPE: 7, reason: 'Test',
      })),
    }) });
  }, () => admin, async () => null, compactStrengthCandidates);
const candidates = Array.from({ length: 80 }, (_, i) => ({
  exerciseID: `exercise-original-${i}`, name: `Biceps curl ${i}`, bodyPart: 'Biceps',
  primaryMuscles: ['biceps'], equipment: ['dumbbell'],
}));
const response = await handler!(new Request('https://test.example', { method: 'POST',
  headers: { Authorization: 'Bearer test-only-user-token' },
  body: JSON.stringify({ candidates, durationMinutes: 45, exerciseCount: 5, focusBodyPart: 'Biceps', language: 'nb',
    existingExerciseIDs: [candidates[0].exerciseID], personalize: true }),
}));
assert.equal(response.status, 200);
const result = await response.json();
assert.equal(providerCalls, 1);
assert.equal(result.exercises.length, 5);
assert.equal(result.exercises[0].exerciseID, candidates[1].exerciseID);
assert.ok(result.exercises.every((e: { exerciseID: string }) => candidates.some(c => c.exerciseID === e.exerciseID)));
assert.ok(!result.exercises.some((e: { exerciseID: string }) => e.exerciseID === candidates[0].exerciseID));
console.log('PASS: authenticated strength request preserves focus, existing-exercise exclusion and original IDs');

const single = await handler!(new Request('https://test.example', { method: 'POST',
  headers: { Authorization: 'Bearer test-only-user-token' },
  body: JSON.stringify({
    candidates, durationMinutes: 20, exerciseCount: 1,
    focusBodyPart: 'Biceps', language: 'nb',
    existingExerciseIDs: candidates.slice(0, 2).map(c => c.exerciseID),
    personalize: true,
  }),
}));
assert.equal(single.status, 200);
const singleResult = await single.json();
assert.equal(singleResult.exercises.length, 1);
assert.equal(singleResult.exercises[0].exerciseID, candidates[2].exerciseID);
assert.equal(providerCalls, 2);
console.log('PASS: AI can recommend exactly one compatible exercise');
