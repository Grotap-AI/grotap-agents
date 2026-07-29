// Claude Code statusline: model + context usage with a nudge to /compact or /clear.
let raw = '';
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  let j = {};
  try { j = JSON.parse(raw.replace(/^﻿/, '')); } catch (_) {}
  const cw = j.context_window || {};
  const pct = Math.round(cw.used_percentage ?? 0);
  const size = cw.context_window_size || 200000;
  const usedK = Math.round(((cw.total_input_tokens || 0) + (cw.total_output_tokens || 0)) / 1000);
  const bar = '#'.repeat(Math.min(10, Math.round(pct / 10))).padEnd(10, '.');
  const model = (j.model && j.model.display_name) || '';
  let warn = '';
  if (pct >= 75) warn = '  << OVER BUDGET: /clear or /compact NOW';
  else if (pct >= 55) warn = '  << context getting long: /compact soon';
  console.log(`${model} | ctx ${pct}% [${bar}] ~${usedK}k/${Math.round(size / 1000)}k${warn}`);
});
