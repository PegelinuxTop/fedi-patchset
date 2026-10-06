#!/usr/bin/env node
//
// Ruby syntax check without a Ruby toolchain: parses the given files with Prism
// (the parser used by Ruby itself) compiled to WebAssembly.
//
//   npm install --no-save @ruby/prism     # once, in this repository
//   node scripts/check-ruby-syntax.mjs $(git diff --name-only <base> HEAD | grep -E '\.(rb|rake)$')
//
// The parser is self-tested before use: if it does not flag a deliberately
// broken snippet, or does flag a valid one, the script exits with an error
// instead of reporting a bogus pass.
//
import { readFileSync } from "node:fs";

const CANDIDATES = [
  process.env.PRISM_PATH,
  "@ruby/prism",
  "../node_modules/@ruby/prism/src/index.js",
];

let loadPrism;
const tried = [];
for (const candidate of CANDIDATES) {
  if (!candidate) continue;
  try {
    const specifier = candidate.startsWith(".") || candidate.startsWith("/")
      ? new URL(candidate, import.meta.url).href
      : candidate;
    ({ loadPrism } = await import(specifier));
    break;
  } catch (error) {
    tried.push(`${candidate}: ${String(error.message).split("\n")[0]}`);
  }
}
if (!loadPrism) {
  console.error("check-ruby-syntax: could not load @ruby/prism.");
  console.error("  tried: " + tried.join("; "));
  console.error("  install it with: npm install --no-save @ruby/prism");
  process.exit(2);
}

const parse = await loadPrism();

const errorsOf = (source) => parse(source).errors ?? [];

// Self-test: a valid snippet must parse and a broken one must not.
const brokenErrors = errorsOf("def broken(\n  1 +\nend\n");
const validErrors = errorsOf("1 + 1\n");
if (brokenErrors.length === 0 || validErrors.length > 0) {
  console.error("check-ruby-syntax: the Prism build in this environment misbehaves");
  console.error(`  broken snippet reported ${brokenErrors.length} error(s), valid snippet ${validErrors.length}`);
  console.error("  refusing to report a result that cannot be trusted");
  process.exit(2);
}

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error("check-ruby-syntax: no files given (pass .rb/.rake paths)");
  process.exit(2);
}

let bad = 0;
for (const file of files) {
  let source;
  try {
    source = readFileSync(file, "utf8");
  } catch (error) {
    bad++;
    console.log(`FAIL  ${file}: ${String(error.message).split("\n")[0]}`);
    continue;
  }
  const errors = errorsOf(source);
  if (errors.length > 0) {
    bad++;
    console.log(`FAIL  ${file}`);
    for (const error of errors) {
      console.log(`        ${error.message}`);
    }
  }
}
console.log(`checked ${files.length} Ruby file(s): ${bad} with syntax errors`);
process.exit(bad > 0 ? 1 : 0);
