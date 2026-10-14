import assert from 'node:assert/strict';
import { compactStrengthCandidates } from './strength-session-prompt.ts';
const candidates = Array.from({ length: 80 }, (_, i) => ({
  exerciseID: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
  name: `Øvelse ${i} ${'x'.repeat(120)}`,
  bodyPart: 'Biceps',
  primaryMuscles: Array(8).fill('biceps brachii and secondary muscle'),
  secondaryMuscles: Array(8).fill('extra secondary context'),
  equipment: Array(8).fill('machine with very long description'),
}));
const compact = compactStrengthCandidates(candidates);
assert.ok(compact.candidates.length >= 8);
assert.ok(compact.candidates.length <= 40);
assert.ok(JSON.stringify(compact.candidates).length <= 6000);
assert.equal(compact.references.get('e1'), candidates[0].exerciseID);
assert.equal(compact.references.get('invented'), undefined);
assert.equal(compact.references.size, compact.candidates.length);
assert.ok(!JSON.stringify(compact.candidates).includes(candidates[0].exerciseID));
assert.equal(compactStrengthCandidates(candidates.slice(0, 3)).candidates.length, 3);
assert.equal(compactStrengthCandidates([]).references.size, 0);
console.log('PASS: strength candidate bounds and lossless server-only ID mapping');
