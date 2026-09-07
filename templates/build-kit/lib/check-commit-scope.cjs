#!/usr/bin/env node
//
// Does this commit stay inside one slice?
//
// The loop builds one slice per iteration and commits on its own. Two ways
// that goes wrong, and neither fails a test:
//
//   * it touches a second slice — code from another iteration, dragged along
//   * it changes the framework while building a slice — a shared contract
//     altered as a side effect of one slice's work
//
// Both are cheap to catch here and expensive to find later, so this runs
// before the commit rather than in review.
//
// It stays quiet unless a slice is involved: a docs commit, a web commit, a
// framework refactor on its own — all fine, nothing to say.

'use strict';
const { execSync } = require('child_process');
const { existsSync, readFileSync } = require('fs');

const staged = execSync('git diff --cached --name-only', { encoding: 'utf8' })
  .split('\n')
  .filter(Boolean);

if (staged.length === 0) process.exit(0);

// The app name from mix.exs, so this works after the namespace rename.
let app = null;
if (existsSync('mix.exs')) {
  const m = readFileSync('mix.exs', 'utf8').match(/app:\s*:([a-z_0-9]+)/);
  if (m) app = m[1];
}
if (!app) process.exit(0);

const sliceRe = new RegExp(`^(?:lib|test)/${app}/slices/([^/]+)/`);
const frameworkRe = new RegExp(`^lib/${app}/[^/]+\\.ex$`);

const slices = new Set();
const framework = [];

for (const f of staged) {
  const m = f.match(sliceRe);
  if (m) slices.add(m[1]);
  else if (frameworkRe.test(f)) framework.push(f);
}

// No slice in the commit: not this hook's business.
if (slices.size === 0) process.exit(0);

const fail = (title, lines) => {
  console.error(`\n✗ ${title}\n`);
  for (const l of lines) console.error(`    ${l}`);
  console.error('\n  Split the commit, or `git commit --no-verify` if you mean it.\n');
  process.exit(1);
};

if (slices.size > 1) {
  fail('This commit touches more than one slice.', [...slices].sort());
}

if (framework.length > 0) {
  fail(
    `Slice work and a framework change in the same commit (slice: ${[...slices][0]}).`,
    [
      ...framework,
      '',
      'A change to the framework changes every slice, so it belongs in its own',
      'commit with its own reason. Bundled into slice work it goes unreviewed.',
    ],
  );
}

process.exit(0);
