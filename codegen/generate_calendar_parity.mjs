#!/usr/bin/env node
// The calendar's parity vectors: what the npm SDK's own code answers, written to tests/data/calendar_parity.json, the
// file tests/test_calendar_labels.gd replays against OWCalendar.
//
//     node codegen/generate_calendar_parity.mjs --sdk <npm sdk checkout>           write the vectors
//     node codegen/generate_calendar_parity.mjs --sdk <npm sdk checkout> --check   exit 1 if the file is not what
//                                                                                  that checkout answers
//
// The checkout is github.com/OnlyWorlds/sdk (the npm package @onlyworlds/sdk), built (`npm run build`): this imports
// its dist/index.js, the code the package ships, and refuses a build older than the last commit that touched the
// calendar's sources. The file names the commit and the package version it was made at.
//
// What it holds, for every calendar the pinned profile fixture reads as one (codegen/schema-dist/profiles/
// calendar.fixture.json, named by case) and for a few written here (inline, each saying what it is for):
// formatYearLabel and formatMidLabel over a spread of steps (both sides of 0, every era's edges, year starts, leap
// years, intercalary days), monthStartSteps over a spread of years, approxYearLength, formatDuration over whole and
// fractional spans, absYearForEraYear for every era, and parseDate over strings made from formatStep's,
// formatYearLabel's and formatMidLabel's own output and over hand-made edge strings, with and without a now. Then
// validateCalendarConfig over every fixture value and over hand-made ones, and resolveCalendar over element lists.
// Where npm throws, the vector says `throws` with its message: Godot has no exceptions, and its own answer there is
// in the test file. Every number in the file is a safe integer or a plain double. Written LF-only, UTF-8.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURE = path.join(ROOT, 'codegen', 'schema-dist', 'profiles', 'calendar.fixture.json');
const MANIFEST = path.join(ROOT, 'codegen', 'schema-dist', 'MANIFEST.json');
const OUT = path.join(ROOT, 'tests', 'data', 'calendar_parity.json');
const SOURCES = ['src/calendar', 'src/options.ts', 'src/room.ts'];

function die(msg) {
  console.error(`calendar parity: ${msg}`);
  process.exit(1);
}

function args() {
  const a = process.argv.slice(2);
  let sdk = process.env.OW_NPM_SDK ?? null;
  let check = false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] === '--check') check = true;
    else if (a[i] === '--sdk') sdk = a[++i];
    else die(`unknown argument ${a[i]}; the arguments are --sdk <path> and --check`);
  }
  if (!sdk) die('give the npm sdk checkout: --sdk <path> (or OW_NPM_SDK)');
  return { sdk: path.resolve(sdk), check };
}

function git(sdk, ...rest) {
  return execFileSync('git', ['-C', sdk, ...rest], { encoding: 'utf8' }).trim();
}

// ---- the spread ---------------------------------------------------------------------------------------------------

const YEARS = [-401, -400, -101, -100, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 100, 101, 400, 1372, 2000];
const SPANS = [0, 1, -1, 2, 7, 10, 99, 100, 0.5, -2.5, 1.004, 1.005, 2.675, 0.125, 1e-7, 123456];
const YEAR_SPANS = [1, 1.04, 1.05, 1.25, 1.5, 2, 9.94, 9.95, 9.96, 10, 10.4, 10.5, 12.5, -3, 1000];

function sorted(set) {
  return [...set].filter((n) => Number.isSafeInteger(n)).sort((a, b) => a - b);
}

/** The steps a calendar's labels are read at: the fixture's, around 0, year starts (and the days beside them), every
 *  era edge, every month start of a few years, every intercalary day of those years. */
function stepsFor(ow, cfg, fixtureSteps) {
  const s = new Set(fixtureSteps);
  for (let n = -3; n <= 3; n++) s.add(n);
  for (const y of YEARS) {
    const start = ow.yearStartStep(cfg, y);
    s.add(start - 1); s.add(start); s.add(start + 1);
  }
  for (const e of cfg.eras ?? []) {
    for (const edge of [e.start, e.end]) {
      if (edge == null) continue;
      s.add(edge - 1); s.add(edge); s.add(edge + 1);
    }
  }
  for (const y of [-4, -1, 0, 1, 4, 100, 400]) {
    for (const m of ow.monthStartSteps(cfg, y)) { s.add(m.step); s.add(m.step - 1); }
    const start = ow.yearStartStep(cfg, y);
    const len = ow.yearLength(cfg, y);
    for (let k = 0; k < len && k < 4000; k++) {
      if (ow.breakdownStep(cfg, start + k).intercalary != null) s.add(start + k);
    }
  }
  return sorted(s);
}

/** Every k-th of a list, the first and last kept: parse is read at fewer steps than the labels. */
function thin(list, max) {
  if (list.length <= max) return list;
  const out = [];
  for (let i = 0; i < max; i++) out.push(list[Math.round((i * (list.length - 1)) / (max - 1))]);
  return [...new Set(out)];
}

/** A double's exact bits, big-endian hex: a JSON reader need not round a long decimal correctly. */
function bits(n) {
  const b = Buffer.alloc(8);
  b.writeDoubleBE(n);
  return b.toString('hex');
}

function call(fn) {
  try {
    return fn();
  } catch (e) {
    return { throws: `${e.constructor.name}: ${e.message}` };
  }
}

function parsed(r) {
  if (r && r.throws) return r;
  return 'error' in r ? { error: r.error } : { step: r.step };
}

/** The hand-made strings: the shapes parseDate's comment names, and the traps a port can fall into. */
function handInputs(cfg) {
  const months = cfg.bundles?.months?.names ?? [];
  const inter = (cfg.intercalary ?? []).map((i) => i.name);
  const eras = cfg.eras ?? [];
  const out = new Set([
    '', '   ', '　', '﻿', '454', '-454', ' -454 ', '\t12 ', '-0', '007', '+5', '5.0', '1e3', '٣',
    '-', '--5', '9007199254740991', 'year', 'Year 5', 'YEAR 5', 'year year 5', 'zzz', 'zzz 5', '5 zzz', '5, 6',
  ]);
  for (const m of months.slice(0, 3)) {
    out.add(m); out.add(`${m} 3`); out.add(`3 ${m}`); out.add(`${m} 3 7`); out.add(`3 ${m} 7`); out.add(`${m} 99 7`);
    out.add(`${m} 1 2 3`); out.add(`${m.toUpperCase()} 2`); out.add(`  ${m.toLowerCase()}   2 ,  5 `);
    out.add(`${m} 400`); out.add(`${m}, 12, 5`); out.add(`Year ${m} 5`);
  }
  for (const i of inter.slice(0, 3)) {
    out.add(i); out.add(`${i} 4`); out.add(`${i} 1`); out.add(`${i} 4 5`); out.add(`${i.toUpperCase()} 8`);
  }
  for (const e of eras.slice(0, 4)) {
    for (const w of [e.name, typeof e.abbrev === 'string' ? e.abbrev : null]) {
      if (!w) continue;
      out.add(`5 ${w}`); out.add(`Year 2 ${w}`); out.add(`${w} 1`); out.add(w); out.add(`-3 ${w}`);
      out.add(`${w.toLowerCase()} 0`); out.add(`1 ${w.toUpperCase()}`);
      if (months[0]) { out.add(`1 ${months[0]} 1 ${w}`); out.add(`${months[0]} 2 ${w}`); }
    }
  }
  if (eras.length >= 2) out.add(`5 ${eras[0].name} ${eras[1].name}`);
  return [...out];
}

// ---- calendars written here -----------------------------------------------------------------------------------------

const TWO = { names: ['Frost', 'Thaw'], lengths: [10, 10] };

const HAND_CALENDARS = [
  { name: 'era-words-and-closed-eras', why: 'abbrevs with dots, closed eras skipped by the default era, a literal word in the template',
    value: { version: 1, grain: 'day', bundles: { months: { names: ['Thistlewane', 'Greening', 'Highsun'], lengths: [30, 30, 30] } },
      eras: [{ name: 'Kingdom Reckoning', abbrev: 'K.R.', start: -3600, closed: true },
        { name: 'Old Count', abbrev: 'OC', start: -900, end: 0, closed: 1 },
        { name: 'Free Tide', abbrev: 'F.T.', start: 0 }],
      format: '{day} {month}, Year {year} {era}' } },
  { name: 'era-label-falsy-abbrev', why: 'an abbrev of "" or 0 prints no era word in the year label; 0 is no parse candidate',
    value: { version: 1, grain: 'year', eras: [{ name: 'Dawn', abbrev: '', start: -10, end: 0 }, { name: 'Zed', abbrev: 0, start: 0 }] } },
  { name: 'era-label-array-abbrev', why: 'an abbrev that is a list prints as String() does, an empty list as nothing after a space',
    value: { version: 1, grain: 'year', eras: [{ name: 'Lists', abbrev: [], start: 0, end: 5 }, { name: 'More', abbrev: ['a', 'b'], start: 5 }] } },
  { name: 'era-label-number-abbrev', why: 'an abbrev that is a number: the label prints it; npm\'s parseDate throws on it',
    value: { version: 1, grain: 'year', eras: [{ name: 'Fifth', abbrev: 5, start: 0 }] } },
  { name: 'step-name', why: 'the step word for durations', value: { version: 1, grain: 'day', step_name: 'Sol',
    bundles: { months: TWO } } },
  { name: 'step-name-empty', why: '"" trims to nothing and reads "step", never the grain', value: { version: 1, grain: 'day', step_name: '' } },
  { name: 'step-name-js-white-space', why: 'JavaScript\'s trim takes U+FEFF and U+00A0; the White_Space trim keeps U+FEFF',
    value: { version: 1, grain: 'day', step_name: '﻿ Sol　' } },
  { name: 'step-name-blank', why: 'a step word of white space alone is "step"', value: { version: 1, grain: 'day', step_name: '   ' } },
  { name: 'grain-year-word', why: 'a grain that lowercases to "year" makes each step a year: no year count, the word kept as written',
    value: { version: 1, grain: ' Year ', eras: [{ name: 'Before', abbrev: 'BT', start: 250, direction: 'down' },
      { name: 'Since', abbrev: 'YSL', start: 250, year_base: 0 }] } },
  { name: 'coarse-year-steps', why: 'bundles.year.steps: a year count with no months', value: { version: 1, grain: 'season', bundles: { year: { steps: 4 } },
    eras: [{ name: 'Age', start: 0 }] } },
  { name: 'names-nested-and-digits', why: 'months match in list order, not longest first; an intercalary name holds a digit; the longer era name wins',
    value: { version: 1, grain: 'day', bundles: { months: { names: ['Wane', 'Frost Wane', 'Sun'], lengths: [5, 5, 5] } },
      intercalary: [{ name: '2 Yule', after_month: 3 }, { name: 'Yule', after_month: 0 }],
      eras: [{ name: 'Empire', abbrev: 'E', start: -100, end: 0 }, { name: 'After Empire', abbrev: 'AE', start: 0 }] } },
  { name: 'unicode-words', why: 'JavaScript lowercases U+0130 to two code units; candidates sort by UTF-16 length (an astral name counts two)',
    value: { version: 1, grain: 'day', bundles: { months: { names: ['Ærwinter', 'İlkyaz'], lengths: [6, 6] } },
      eras: [{ name: 'abc', start: -50, end: 0 }, { name: '\u{1D504}\u{1D504}', start: 0 }] },
    inputs: ['ilkyaz 1', 'İLKYAZ 1', 'i̇lkyaz 2 3', 'abc \u{1D504}\u{1D504} 5', '\u{1D504}\u{1D504} abc 5', '5 \u{1D504}\u{1D504}',
      'ÆRWINTER 3 1'] },
  { name: 'default-era-ties', why: 'two open eras of one start: the default era is the first listed (a stable sort)',
    value: { version: 1, grain: 'year', eras: [{ name: 'Early', start: -100 }, { name: 'First', start: 100 }, { name: 'Second', abbrev: 'S', start: 100 },
      { name: 'Shut', start: 200, closed: true }] } },
  { name: 'all-closed', why: 'every era closed: the default era is the latest start of them all',
    value: { version: 1, grain: 'year', eras: [{ name: 'One', start: 0, closed: true }, { name: 'Two', start: 10, closed: 'yes' }] } },
  { name: 'down-mid-year-pivot', why: 'a down era pivoting mid-year beside an up era: "not a date in" refusals',
    value: { version: 1, grain: 'day', bundles: { months: TWO }, eras: [{ name: 'Before Gate', abbrev: 'BG', start: 5, direction: 'down' },
      { name: 'After Gate', abbrev: 'AG', start: 5 }] },
    inputs: ['10 Thaw, 1 BG', '3 Frost, 0 BG', '3 Frost, 1 BG', '10 Thaw, 1 AG', '1 Frost 1 BG', 'Thaw 2 AG', 'Frost 1 bg'] },
  { name: 'leap-v2-weeks', why: 'a version-2 leap rule with an offset, an intercalary day out of the week, a long year',
    value: { version: 2, grain: 'day', bundles: { months: { names: ['Hammer', 'Alturiak', 'Ches'], lengths: [30, 30, 30] }, week: { length: 10, names: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'] } },
      intercalary: [{ name: 'Midwinter', after_month: 1 }, { name: 'Shieldmeet', after_month: 2, every_years: 4, except: [100, 400], offset: 1, in_week: false }],
      eras: [{ name: 'Dale Reckoning', abbrev: 'DR', start: 0, year_base: 0 }] } },
];

// ---- validate's hand values -----------------------------------------------------------------------------------------

const M = { months: TWO };
const VALIDATE_HAND = [
  ['version-missing', { grain: 'day' }],
  ['version-null', { version: null, grain: 'day' }],
  ['version-string', { version: '1', grain: 'day' }],
  ['version-fraction', { version: 1.5, grain: 'day' }],
  ['version-true', { version: true, grain: 'day' }],
  ['version-list', { version: [2], grain: 'day' }],
  ['version-object', { version: {}, grain: 'day' }],
  ['version-huge', { version: 1e21, grain: 'day' }],
  ['grain-js-only-white-space', { version: 1, grain: '﻿' }],
  ['grain-white-space', { version: 1, grain: '  　' }],
  ['months-and-year', { version: 1, grain: 'day', bundles: { months: TWO, year: { steps: 0 } } }],
  ['months-not-object', { version: 1, grain: 'day', bundles: { months: 'Frost' } }],
  ['months-true', { version: 1, grain: 'day', bundles: { months: true } }],
  ['months-empty-object', { version: 1, grain: 'day', bundles: { months: {} } }],
  ['months-falsy-with-year', { version: 1, grain: 'day', bundles: { months: 0, year: { steps: 3 } } }],
  ['months-length-string', { version: 1, grain: 'day', bundles: { months: { names: ['A'], lengths: ['3'] } } }],
  ['bundles-a-string', { version: 1, grain: 'day', bundles: 'months' }],
  ['bundles-a-list', { version: 1, grain: 'day', bundles: [TWO] }],
  ['year-steps-fraction', { version: 1, grain: 'day', bundles: { year: { steps: 2.5 } } }],
  ['year-steps-missing', { version: 1, grain: 'day', bundles: { year: {} } }],
  ['year-a-number', { version: 1, grain: 'day', bundles: { year: 5 } }],
  ['week-a-string', { version: 1, grain: 'day', bundles: { months: TWO, week: 'abcdefg' } }],
  ['week-a-list', { version: 1, grain: 'day', bundles: { months: TWO, week: ['Mo', 'Tu'] } }],
  ['week-astral-string', { version: 1, grain: 'day', bundles: { week: '\u{1D504}' } }],
  ['week-names-long', { version: 1, grain: 'day', bundles: { week: { length: 2, names: ['a', 'b', 'c'] } } }],
  ['week-length-fraction', { version: 1, grain: 'day', bundles: { week: { length: 1.5, names: ['a'] } } }],
  ['week-names-string', { version: 1, grain: 'day', bundles: { week: { length: 2, names: 'ab' } } }],
  ['festival-no-months', { version: 1, grain: 'day', intercalary: [{ name: 'Gap', after_month: 0 }] }],
  ['festival-a-string', { version: 1, grain: 'day', bundles: M, intercalary: 'ab' }],
  ['festival-a-string-no-months', { version: 1, grain: 'day', intercalary: 'x' }],
  ['festival-entry-number', { version: 1, grain: 'day', bundles: M, intercalary: [5] }],
  ['festival-after-month-string', { version: 1, grain: 'day', bundles: M, intercalary: [{ name: 'Gap', after_month: '1' }] }],
  ['festival-after-month-fraction', { version: 1, grain: 'day', bundles: M, intercalary: [{ name: 'Gap', after_month: 0.5 }] }],
  ['festival-every-string', { version: 2, grain: 'day', bundles: M, intercalary: [{ name: 'Leap', after_month: 1, every_years: '4', except: [8] }] }],
  ['festival-every-zero-except', { version: 2, grain: 'day', bundles: M, intercalary: [{ name: 'Leap', after_month: 1, every_years: 0, except: [8] }] }],
  ['festival-every-negative-except', { version: 2, grain: 'day', bundles: M, intercalary: [{ name: 'Leap', after_month: 1, every_years: -4, except: [8] }] }],
  ['festival-every-fraction-except', { version: 2, grain: 'day', bundles: M, intercalary: [{ name: 'Leap', after_month: 1, every_years: 2.5, except: [5] }] }],
  ['festival-every-null-offset', { version: 2, grain: 'day', bundles: M, intercalary: [{ name: 'Leap', after_month: 1, every_years: null, offset: 1 }] }],
  ['festival-except-null', { version: 2, grain: 'day', bundles: M, intercalary: [{ name: 'Leap', after_month: 1, every_years: 4, except: null, offset: null }] }],
  ['festival-v1-null-keys', { version: 1, grain: 'day', bundles: M, intercalary: [{ name: 'Leap', after_month: 1, every_years: 4, except: null }] }],
  ['festival-v1-every-missing', { version: 1, grain: 'day', bundles: M, intercalary: [{ name: 'Leap', after_month: 1, offset: 2 }] }],
  ['festival-offset-huge', { version: 2, grain: 'day', bundles: M, intercalary: [{ name: 'Leap', after_month: 1, every_years: 4, offset: 2 ** 53 }] }],
  ['festival-name-object', { version: 1, grain: 'day', bundles: M, intercalary: [{ name: { a: 1 }, after_month: 9 }] }],
  ['festival-name-list', { version: 1, grain: 'day', bundles: M, intercalary: [{ name: ['x', null, 'y'], after_month: 9 }] }],
  ['era-name-empty', { version: 1, grain: 'year', eras: [{ name: '', start: 0 }] }],
  ['era-name-zero', { version: 1, grain: 'year', eras: [{ name: 0, start: 0 }] }],
  ['era-start-string', { version: 1, grain: 'year', eras: [{ name: 'A', start: '50', end: 10 }] }],
  ['era-start-and-end-strings', { version: 1, grain: 'year', eras: [{ name: 'A', start: '9', end: '10' }] }],
  ['era-start-null', { version: 1, grain: 'year', eras: [{ name: 'A', start: null, end: 5 }] }],
  ['era-start-true', { version: 1, grain: 'year', eras: [{ name: 'A', start: true, end: 1 }] }],
  ['era-start-list', { version: 1, grain: 'year', eras: [{ name: 'A', start: [3], end: 2 }] }],
  ['era-end-before-start', { version: 1, grain: 'year', eras: [{ name: 'A', start: 10, end: 10 }] }],
  ['era-down-end-above', { version: 1, grain: 'year', eras: [{ name: 'B', start: 0, end: 5, direction: 'down' }] }],
  ['era-direction-other', { version: 1, grain: 'year', eras: [{ name: 'S', start: 10, end: 5, direction: 'Up' }] }],
  ['era-direction-null', { version: 1, grain: 'year', eras: [{ name: 'N', start: 10, end: 5, direction: null }] }],
  ['era-fraction-start', { version: 1, grain: 'year', eras: [{ name: 'H', start: 0.5 }, { name: 'I', start: 0.25 }] }],
  ['eras-a-string', { version: 1, grain: 'year', eras: 'ab' }],
  ['eras-empty-string', { version: 1, grain: 'year', eras: '' }],
  ['eras-entry-number', { version: 1, grain: 'year', eras: [7] }],
  ['eras-overlap-three', { version: 1, grain: 'year', eras: [{ name: 'A', start: 0, end: 100 }, { name: 'B', start: 50, end: 150 },
    { name: 'C', start: 60, end: 70 }, { name: 'D', start: -10, direction: 'down' }] }],
  ['eras-overlap-string-start', { version: 1, grain: 'year', eras: [{ name: 'A', start: 0, end: 100 }, { name: 'B', start: '50' },
    { name: 'C', start: 20 }] }],
  ['eras-overlap-null-start', { version: 1, grain: 'year', eras: [{ name: 'A', start: 30 }, { name: 'B', start: null }, { name: 'C', start: 10 }] }],
  ['eras-descending-run', { version: 1, grain: 'year', eras: [{ name: 'C', start: 30 }, { name: 'B', start: 20 }, { name: 'A', start: 10, end: 25 }] }],
  ['eras-down-overlap-down', { version: 1, grain: 'year', eras: [{ name: 'X', start: 0, direction: 'down' }, { name: 'Y', start: -5, direction: 'down' }] }],
  ['eras-infinite-ends', { version: 1, grain: 'year', eras: [{ name: 'A', start: 0, end: 1e308 }, { name: 'B', start: 1e300 }] }],
  ['everything-wrong', { version: 0, grain: '', bundles: { months: { names: [], lengths: [] }, year: { steps: -1 }, week: { length: 0 } },
    intercalary: [{ name: 'Q', after_month: -1, every_years: 0, except: 'x' }], eras: [{ start: 'x' }, { name: 'Z', start: 5, end: 1 }] }],
];
// What npm throws on (Godot answers instead; the test holds its answer).
const VALIDATE_THROWS = [
  ['null', null],
  ['eras-an-object', { version: 1, grain: 'year', eras: { name: 'A', start: 0 } }],
  ['eras-a-number', { version: 1, grain: 'year', eras: 3 }],
  ['eras-true', { version: 1, grain: 'year', eras: true }],
  ['eras-entry-null', { version: 1, grain: 'year', eras: [null] }],
  ['festival-an-object', { version: 1, grain: 'day', bundles: M, intercalary: { name: 'Gap' } }],
  ['festival-entry-null', { version: 1, grain: 'day', bundles: M, intercalary: [null] }],
  ['festival-a-number', { version: 1, grain: 'day', bundles: M, intercalary: 2 }],
];

// ---- resolve's element lists ----------------------------------------------------------------------------------------

const CAL = { version: 1, grain: 'day', bundles: { months: TWO } };
const ELEMENT_SETS = {
  one: [{ id: 'c1', name: 'Imperial', atlas_calendar: CAL }, { id: 'x', name: 'Plain' }],
  two: [{ id: 'c1', name: 'Imperial', atlas_calendar: CAL }, { id: 'c2', name: 'Lunar', atlas_calendar: JSON.stringify(CAL) }],
  one_valid_one_broken: [{ id: 'bad', name: 'Broken', atlas_calendar: { version: 3, grain: 'day' } }, { id: 'c1', name: 'Imperial', atlas_calendar: CAL }],
  unnamed: [{ id: 'u1', name: '', atlas_calendar: CAL }, { id: 'u2', atlas_calendar: CAL }, { id: 'u3', name: null, atlas_calendar: CAL },
    { id: 'u4', name: 0, atlas_calendar: CAL }, { id: 'u5', name: 'Named', atlas_calendar: CAL }],
  duplicate_ids: [{ id: 'd', name: 'First', atlas_calendar: CAL }, { id: 'd', name: 'Second', atlas_calendar: CAL }],
  numeric_id: [{ id: 5, name: 'Five', atlas_calendar: CAL }],
  none: [{ id: 'x', name: 'Plain' }, { id: 'y', name: 'Null', atlas_calendar: null }],
};
const ACTIVES = [undefined, null, '', 'c1', 'c2', 'bad', 'gone', 'u1', 'u2', 'u4', 'd', 5, '5', 0];
const RESOLVE_OPTIONS = [undefined, {}, { fallbackToOnly: true }, { fallbackToOnly: false }, { fallbackToOnly: 1 }, { fallbackToOnly: null },
  { fallbackToOnly: true, Now: 1 }, { fallback_to_only: true }];

// ---- the document ---------------------------------------------------------------------------------------------------

function calendarVectors(ow, entry, fixtureSteps) {
  const cfg = ow.readCalendarValue(entry.value);
  if (cfg == null) die(`${entry.name}: not a calendar`);
  const steps = stepsFor(ow, cfg, fixtureSteps);
  const labels = steps.map((s) => [s, ow.formatYearLabel(cfg, s), ow.formatMidLabel(cfg, s)]);
  const monthStarts = YEARS.map((y) => [y, ow.monthStartSteps(cfg, y).map((m) => [m.month, m.name, m.step])]);
  const yl = ow.approxYearLength(cfg);
  const spans = new Set(SPANS);
  if (yl != null) for (const k of YEAR_SPANS) { spans.add(k * yl); spans.add(k * yl - 1); spans.add(Math.round(k * yl) + 1); }
  const durations = [...spans].map((n) => {
    const row = [n, call(() => ow.formatDuration(cfg, n))];
    if (!Number.isInteger(n)) row.push(bits(n));
    return row;
  });
  const eraYears = [];
  (cfg.eras ?? []).forEach((era, i) => {
    for (const y of [-1, 0, 1, 2, 10]) eraYears.push([i, y, ow.absYearForEraYear(cfg, era, y)]);
  });
  const nows = [null, 0, steps[Math.floor(steps.length * 0.75)]];
  const texts = new Set();
  for (const s of thin(steps, 24)) {
    texts.add(ow.formatStep(cfg, s)); texts.add(ow.formatYearLabel(cfg, s)); texts.add(ow.formatMidLabel(cfg, s));
  }
  for (const h of handInputs(cfg)) texts.add(h);
  for (const h of entry.inputs ?? []) texts.add(h);
  const parse = [];
  for (const text of texts) {
    for (const now of nows) {
      const opts = now == null ? undefined : { now };
      parse.push([text, now, parsed(call(() => ow.parseDate(cfg, text, opts)))]);
    }
  }
  return { labels, month_starts: monthStarts, approx_year_length: yl, durations, era_years: eraYears, parse };
}

function build(ow, meta) {
  const fixture = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));
  const calendars = [];
  for (const c of fixture.cases) {
    if (!c.valid) continue;
    calendars.push({ case: c.name, ...calendarVectors(ow, c, c.steps.map((s) => s.step)) });
  }
  for (const h of HAND_CALENDARS) calendars.push({ name: h.name, why: h.why, value: h.value, ...calendarVectors(ow, h, []) });

  const validate = [];
  for (const c of fixture.cases) {
    let v = c.value;
    if (typeof v === 'string') {
      try { v = JSON.parse(v); } catch { continue; }   // text JSON cannot read is no config to validate
    }
    validate.push({ case: c.name, answer: call(() => ow.validateCalendarConfig(v)) });
  }
  for (const [name, value] of [...VALIDATE_HAND, ...VALIDATE_THROWS]) {
    validate.push({ name, value, answer: call(() => ow.validateCalendarConfig(value)) });
  }
  for (const [name] of VALIDATE_HAND) {
    const a = validate.find((x) => x.name === name).answer;
    if (a.throws) die(`validate ${name} throws (${a.throws}): move it to VALIDATE_THROWS`);
  }
  for (const [name] of VALIDATE_THROWS) {
    if (!validate.find((x) => x.name === name).answer.throws) die(`validate ${name} does not throw: move it to VALIDATE_HAND`);
  }

  const resolve = [];
  for (const [set, elements] of Object.entries(ELEMENT_SETS)) {
    for (const active of ACTIVES) {
      for (const opts of RESOLVE_OPTIONS) {
        const r = call(() => ow.resolveCalendar(elements, active, opts));
        const row = { set };
        if (active !== undefined) row.active = active;
        if (opts !== undefined) row.options = opts;
        row.answer = r == null ? null : r.throws ? r : { id: r.id, name: r.name };
        resolve.push(row);
      }
    }
  }
  return {
    about: 'The npm SDK\'s calendar answers, for OWCalendar to match: made by codegen/generate_calendar_parity.mjs from the '
      + 'package\'s built dist/index.js. "case" names a calendar of the pinned profile fixture; "value" is a calendar '
      + 'written here. A "throws" answer is what npm throws; Godot\'s answer there is in tests/test_calendar_labels.gd.',
    npm: meta,
    fixture_sha256: JSON.parse(fs.readFileSync(MANIFEST, 'utf8')).files['profiles/calendar.fixture.json'],
    keys: {
      labels: '[step, formatYearLabel, formatMidLabel]',
      month_starts: '[year, [[month, name, step], ...]]',
      durations: '[steps, formatDuration, the steps\' IEEE 754 bits, big-endian hex, for a fraction: Godot\'s JSON reads '
        + '3631.7499999999995 as a neighbouring double]',
      era_years: '[era index, era year, absYearForEraYear]',
      parse: '[input, now (null: no options), {step} | {error} | {throws}]',
    },
    calendars,
    validate,
    element_sets: ELEMENT_SETS,
    resolve,
  };
}

// One line per record inside each list of records, so a diff names the record that moved.
function write(doc) {
  const line = (v) => JSON.stringify(v);
  const out = ['{'];
  const top = Object.entries(doc);
  top.forEach(([k, v], i) => {
    const comma = i < top.length - 1 ? ',' : '';
    if (k === 'calendars') {
      out.push(` "calendars": [`);
      v.forEach((cal, j) => {
        out.push('  {');
        const keys = Object.entries(cal);
        keys.forEach(([ck, cv], n) => {
          const c2 = n < keys.length - 1 ? ',' : '';
          if (Array.isArray(cv) && ck !== 'value') {
            out.push(`   ${line(ck)}: [`);
            cv.forEach((r, m) => out.push(`    ${line(r)}${m < cv.length - 1 ? ',' : ''}`));
            out.push(`   ]${c2}`);
          } else {
            out.push(`   ${line(ck)}: ${line(cv)}${c2}`);
          }
        });
        out.push(`  }${j < v.length - 1 ? ',' : ''}`);
      });
      out.push(` ]${comma}`);
    } else if (Array.isArray(v)) {
      out.push(` ${line(k)}: [`);
      v.forEach((r, m) => out.push(`  ${line(r)}${m < v.length - 1 ? ',' : ''}`));
      out.push(` ]${comma}`);
    } else if (k === 'element_sets' || k === 'keys' || k === 'npm') {
      out.push(` ${line(k)}: {`);
      const e = Object.entries(v);
      e.forEach(([ek, ev], m) => out.push(`  ${line(ek)}: ${line(ev)}${m < e.length - 1 ? ',' : ''}`));
      out.push(` }${comma}`);
    } else {
      out.push(` ${line(k)}: ${line(v)}${comma}`);
    }
  });
  out.push('}');
  return out.join('\n') + '\n';
}

async function main() {
  const { sdk, check } = args();
  const dist = path.join(sdk, 'dist', 'index.js');
  if (!fs.existsSync(dist)) die(`no ${dist}: build the package first (npm run build)`);
  const commit = git(sdk, 'rev-parse', 'HEAD');
  const dirty = git(sdk, 'status', '--porcelain', '--', ...SOURCES);
  if (dirty) die(`the calendar's sources have uncommitted changes in ${sdk}:\n${dirty}`);
  const touched = Number(git(sdk, 'log', '-1', '--format=%ct', '--', ...SOURCES));
  if (fs.statSync(dist).mtimeMs / 1000 < touched) die('dist/index.js is older than the last commit to the calendar\'s sources: rebuild it');
  const version = JSON.parse(fs.readFileSync(path.join(sdk, 'package.json'), 'utf8')).version;
  const ow = await import(pathToFileURL(dist).href);
  const text = write(build(ow, { package: '@onlyworlds/sdk', version, commit: commit.slice(0, 7) }));
  if (check) {
    const have = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
    if (have === text) {
      console.log(`calendar parity: ${path.relative(ROOT, OUT)} is npm's answer at ${commit.slice(0, 7)}`);
      return;
    }
    const strip = (t) => t.replace(/^ "npm": \{[\s\S]*?\n \},\n/m, '');
    die(strip(have) === strip(text)
      ? `only the npm commit or version moved (the vectors are the same): regenerate to record ${version} at ${commit.slice(0, 7)}`
      : `${path.relative(ROOT, OUT)} is stale: npm at ${commit.slice(0, 7)} answers differently; regenerate and read the diff`);
  }
  fs.writeFileSync(OUT, text, 'utf8');
  console.log(`calendar parity: wrote ${path.relative(ROOT, OUT)} (${(text.length / 1024).toFixed(0)} KB) from npm ${version} at ${commit.slice(0, 7)}`);
}

main();
