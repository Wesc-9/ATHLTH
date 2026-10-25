import { readFileSync } from 'node:fs';

// Contrast is a measurable part of the visual contract, independent of Xcode.
// This does not replace rendered Dynamic Type / VoiceOver / device review.
const source = readFileSync(new URL('../ATHLTH/DesignSystem/ATHLTHTrainDesign.swift', import.meta.url), 'utf8');
function color(name) {
  const match = source.match(new RegExp(`static let ${name} = Color\\(red: ([\\d.]+), green: ([\\d.]+), blue: ([\\d.]+)\\)`));
  if (!match) throw new Error(`Missing explicit Train color: ${name}`);
  return match.slice(1).map(Number);
}
function luminance(rgb) {
  const linear = rgb.map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}
function contrast(first, second) {
  const values = [luminance(first), luminance(second)].sort((a, b) => b - a);
  return (values[0] + 0.05) / (values[1] + 0.05);
}
let failed = false;
for (const foreground of ['ink', 'secondary', 'bronze']) {
  for (const background of ['paper', 'canvas', 'paleGold']) {
    const ratio = contrast(color(foreground), color(background));
    console.log(`${foreground} on ${background}: ${ratio.toFixed(2)}:1`);
    if (ratio < 4.5) failed = true;
  }
}
const selectedContrast = contrast([1, 1, 1], color('ink'));
console.log(`White on selected navigation / primary action: ${selectedContrast.toFixed(2)}:1`);
if (selectedContrast < 4.5) failed = true;
for (const background of ['ink', 'inkLift']) {
  for (const foreground of [[1, 1, 1], color('paleGold')]) {
    const ratio = contrast(foreground, color(background));
    console.log(`Light text on ${background}: ${ratio.toFixed(2)}:1`);
    if (ratio < 4.5) failed = true;
  }
}
if (failed) throw new Error('Train text contrast falls below WCAG AA 4.5:1');
console.log('Train text color pairs meet WCAG AA. Rendered review remains required.');
