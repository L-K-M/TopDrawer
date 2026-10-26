#!/usr/bin/env node
// Write Third-Party-Notices.txt for a JavaScript bundle from the bundler's
// own module graph, so it lists only packages whose code or assets ship.
// Each entry: name, version, SPDX license, source URL, then the package's
// LICENSE/COPYING/NOTICE files verbatim. Fails, and writes nothing, when a
// bundled component has no license text and no explicit override.
//
// Node >= 20, no dependencies. Run `node third-party-notices.mjs --help`.

import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';

const USAGE = `Usage: node third-party-notices.mjs --out FILE [options] [inputs]

Inputs (repeatable; combine as needed):
  --modules DIR|FILE      JSON from bundled-modules.mjs (Vite, Rollup, Rolldown)
  --esbuild-meta FILE     esbuild metafile; also Angular's stats.json
  --webpack-stats FILE    webpack stats JSON; also ncc --stats-out
  --sourcemaps DIR        fallback: "sources" of every *.map below DIR
  --package NAME          an installed package whose data ships (no bundler)

Options:
  --root DIR              project dir: relative inputs and node_modules lookup (default: cwd)
  --repo DIR              repository root; files inside it outside node_modules
                          are own code (default: nearest parent with .git or a
                          pnpm/npm workspace definition, else --root)
  --config FILE           overrides (JSON, whole-line // comments allowed); its
                          paths and globs are relative to its own directory
  --title TEXT            name of the artifact in the header (default: package.json name)
  --outputs REGEX         only esbuild/Angular outputs matching REGEX (e.g. "^(?!server/)")
  --include-ssr           also count SSR/server bundles from --modules
  --include FILE          append another generated notices file verbatim (e.g. Rust crates)
  --check-assets DIR      bundler output: fail unless every font file below DIR
                          has a font license entry, and on fonts inlined as data:
                          URIs in its CSS/JS/HTML (unless listed in "inlineFonts")
  --check-vendored DIR    unbundled sites: fail unless every script, style, font,
                          WebAssembly and image file below DIR matches a
                          component's "assets" or an "own" glob
  --list                  print the component list to stdout
`;

const LICENSE_FILE = /^(?:licen[cs]e|copying|notice|unlicense|copyright|ofl|patents)(?:[-_. ].*)?$|^[\w.-]+[-_.](?:licen[cs]e|copying)(?:[-_. ].*)?$/i;
// Code, data and SPDX/metadata documents are not license texts.
const NOT_TEXT = /\.(?:[cm]?[jt]sx?|json|map|css|html?|wasm|node|png|svg|gif|jpe?g|spdx|ya?ml|xml|toml|rdf)$/i;
const FONT = /\.(?:woff2?|ttf|otf|eot)$/i;
// Served files that may be third-party: code, styles, fonts, WebAssembly, images.
const SHIPPED_FILE = /\.(?:[cm]?js|css|woff2?|ttf|otf|eot|wasm|svg|png|gif|jpe?g|webp|avif|ico)$/i;
// Fonts inlined as data: URIs: font MIME types, or base64 starting with a
// WOFF2, WOFF, OpenType CFF or TrueType signature.
const INLINE_FONT = /data:(?:font\/|application\/(?:x-)?font-|application\/vnd\.ms-fontobject)[\w.+=;-]*base64,[A-Za-z0-9+/]{16}|data:[\w.+-]+\/[\w.+=;-]+;base64,(?:d09GMg|d09GRg|T1RUTw|AAEAAA)/;
const TEXT_OUTPUT = /\.(?:[cm]?js|css|html?)$/i;
// Licenses whose source-availability terms need a pointer to the exact source.
const COPYLEFT = /\b(?:MPL|LGPL|GPL|AGPL|EPL|CDDL|EUPL|OSL|CPL|MS-RL|CECILL)/i;
// GPL-family terms need the complete corresponding source (GPL, AGPL) or the
// library source plus relinking materials (LGPL); a pointer is not enough.
const GPL_FAMILY = /\b[AL]?GPL/i;
// CC BY terms need the creator, copyright notice and a modification note,
// which a generic legal code file does not carry.
const CC_BY = /\bCC-BY\b/i;
const FONT_LICENSE = /\b(?:OFL|UFL|GUST|Bitstream|Arphic)/i;
const FONT_PACKAGE = /^@fontsource(?:-variable)?\//;
// Tool LICENSE.md files that append the licenses of the tool's own bundled
// dependencies; only the part above this heading covers emitted helper code.
const BUNDLED_DEPS_HEADING = /^#+\s*Licenses of bundled dependencies.*$/im;

// Virtual module ids emitted by bundlers for their runtime helpers, mapped to
// the package (or config component) whose code they are. Unknown virtual ids
// fail the run; extend with "virtualModules" in the config.
const VIRTUAL_DEFAULTS = [
  ['vite/', ['vite']],
  ['virtual:__sveltekit/', ['@sveltejs/kit']],
  ['__vite-browser-external', ['vite']],
  ['commonjsHelpers.js', ['@rollup/plugin-commonjs', 'vite']],
  ['rolldown/', ['rolldown']],
  ['plugin-vue:', ['@vitejs/plugin-vue']],
  ['<runtime>', ['esbuild']],
  ['angular:', ['@angular/build', '@angular-devkit/build-angular']],
  ['webpack/runtime/', ['webpack']],
];

function fail(message) {
  console.error(`third-party-notices: ${message}`);
  process.exit(2);
}

const slash = (p) => p.replaceAll('\\', '/');
const readText = (file) => fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n').trimEnd();
const isInside = (child, parent) => {
  const rel = path.relative(parent, child);
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
};
const inNodeModules = (p) => slash(p).includes('/node_modules/');
// True when every alternative of a top-level OR matches re: a disjunction
// with another alternative is distributed under that alternative.
const onlyUnder = (license, re) => re.test(license ?? '')
  && license.replace(/^\((.*)\)$/, '$1').split(/\s+OR\s+/i).every((alt) => re.test(alt));

// Numeric-aware, locale-independent ordering for deterministic output.
function compare(a, b) {
  const pa = a.split(/(\d+)/);
  const pb = b.split(/(\d+)/);
  for (let i = 0; i < Math.min(pa.length, pb.length); i++) {
    if (pa[i] === pb[i]) continue;
    if (i % 2) return Number(pa[i]) - Number(pb[i]) || (pa[i] < pb[i] ? -1 : 1);
    return pa[i] < pb[i] ? -1 : 1;
  }
  return pa.length - pb.length;
}

function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      re += '.*';
      i += glob[i + 2] === '/' ? 2 : 1;
    } else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${re}$`);
}

function loadConfig(file) {
  if (!file) return { dir: process.cwd(), packages: {}, components: [], virtualModules: {}, ignore: [], own: [], inlineFonts: [], intro: [] };
  // Whole-line // comments only, so string contents are never touched.
  const source = fs.readFileSync(file, 'utf8').split('\n').filter((line) => !/^\s*\/\//.test(line)).join('\n');
  let config;
  try {
    config = JSON.parse(source);
  } catch (error) {
    fail(`${file}: ${error.message}`);
  }
  const problems = [];
  const needReason = (what, entry) => {
    if (typeof entry?.reason !== 'string' || !entry.reason.trim()) problems.push(`${what} needs a "reason"`);
  };
  for (const [key, entry] of Object.entries(config.packages ?? {})) needReason(`packages["${key}"]`, entry);
  for (const [i, entry] of (config.components ?? []).entries()) {
    needReason(`components[${i}] (${entry?.name})`, entry);
    if (!entry?.name || !entry?.license) problems.push(`components[${i}] needs "name" and "license"`);
  }
  for (const [i, entry] of (config.ignore ?? []).entries()) needReason(`ignore[${i}]`, entry);
  for (const [i, entry] of (config.own ?? []).entries()) needReason(`own[${i}]`, entry);
  for (const [i, entry] of (config.inlineFonts ?? []).entries()) needReason(`inlineFonts[${i}]`, entry);
  if (problems.length) fail(`${file}:\n  ${problems.join('\n  ')}`);
  return {
    dir: path.dirname(path.resolve(file)),
    file,
    intro: config.intro ?? [],
    packages: config.packages ?? {},
    components: config.components ?? [],
    virtualModules: config.virtualModules ?? {},
    ignore: config.ignore ?? [],
    own: config.own ?? [],
    inlineFonts: config.inlineFonts ?? [],
  };
}

// Repository (or workspace) root: own code lives below it, outside node_modules.
function findRepo(root) {
  const isWorkspace = (dir) => {
    if (fs.existsSync(path.join(dir, 'pnpm-workspace.yaml'))) return true;
    try {
      return Boolean(JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8')).workspaces);
    } catch {
      return false;
    }
  };
  for (let dir = root; ; dir = path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, '.git')) || isWorkspace(dir)) return dir;
    if (path.dirname(dir) === dir) return root;
  }
}

// File path behind a module id: absolute, relative to base, or wrapped in
// bundler namespaces ("angular:css-resource:node_modules/x/a.woff2",
// "angular:styles/component:css;<hash>;/abs/app.html"). Null for virtual ids.
function pathOf(id, base) {
  const direct = (p) => {
    if (/^[A-Za-z]:\//.test(p) || p.startsWith('/')) return path.resolve(p);
    if (/^[\w.+/-]+:/.test(p) || p.startsWith('<')) return null;
    const candidate = path.resolve(base, p);
    return fs.existsSync(candidate) ? candidate : null;
  };
  if (/^[A-Za-z]:\//.test(id) || id.startsWith('/')) return path.resolve(id);
  for (let rest = id; ; ) {
    const found = direct(rest) ?? rest.split(';')
      .map((part) => ((part.startsWith('/') || /^[A-Za-z]:\//.test(part)) && fs.existsSync(part) ? path.resolve(part) : null))
      .find(Boolean);
    if (found) return found;
    const next = rest.replace(/^[\w.+/-]+:/, '');
    if (next === rest) return null;
    rest = next;
  }
}

function findInstalled(name, root) {
  for (let dir = root; ; dir = path.dirname(dir)) {
    const candidate = path.join(dir, 'node_modules', name);
    if (fs.existsSync(path.join(candidate, 'package.json'))) return candidate;
    if (path.dirname(dir) === dir) return null;
  }
}

// Package root of a file below node_modules (handles scopes and pnpm's .pnpm).
function packageDirOf(file) {
  const p = slash(file);
  const at = p.lastIndexOf('/node_modules/');
  const parts = p.slice(at + '/node_modules/'.length).split('/');
  const name = parts[0].startsWith('@') ? `${parts[0]}/${parts[1]}` : parts[0];
  return `${p.slice(0, at)}/node_modules/${name}`;
}

function repositoryUrl(pkg) {
  let url = typeof pkg.repository === 'object' ? pkg.repository?.url : pkg.repository;
  if (typeof url !== 'string' || !url) return typeof pkg.homepage === 'string' ? pkg.homepage : undefined;
  url = url.replace(/^git\+/, '').replace(/\.git$/, '').replace(/^git:\/\//, 'https://')
    .replace(/^ssh:\/\/git@/, 'https://').replace(/^git@([^:]+):/, 'https://$1/');
  const shorthand = url.match(/^(github|gitlab|bitbucket):(.+)$/);
  if (shorthand) return `https://${shorthand[1]}.${shorthand[1] === 'bitbucket' ? 'org' : 'com'}/${shorthand[2]}`;
  if (/^[\w.-]+\/[\w.-]+$/.test(url)) return `https://github.com/${url}`;
  return url;
}

function licenseOf(pkg) {
  const value = pkg.license ?? pkg.licenses;
  if (typeof value === 'string') return value.trim();
  if (Array.isArray(value)) {
    const ids = value.map((v) => (typeof v === 'string' ? v : v?.type)).filter(Boolean);
    return ids.length > 1 ? `(${ids.join(' OR ')})` : ids[0];
  }
  return value?.type;
}

function licenseFiles(dir) {
  const files = [];
  // Top-level license files, plus everything below a licenses/ folder.
  const scan = (d, prefix) => {
    for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
      if (entry.isDirectory() && (prefix || /^licen[cs]es$/i.test(entry.name))) scan(path.join(d, entry.name), `${prefix}${entry.name}/`);
      else if ((prefix || LICENSE_FILE.test(entry.name)) && !NOT_TEXT.test(entry.name)
        && fs.statSync(path.join(d, entry.name), { throwIfNoEntry: false })?.isFile()) {
        files.push({ name: prefix + entry.name, file: path.join(d, entry.name) });
      }
    }
  };
  scan(dir, '');
  return files.sort((a, b) => compare(a.name.toLowerCase(), b.name.toLowerCase()) || compare(a.name, b.name));
}

function main() {
  let args;
  try {
    ({ values: args } = parseArgs({
      options: {
        out: { type: 'string' }, root: { type: 'string' }, repo: { type: 'string' },
        config: { type: 'string' }, title: { type: 'string' }, outputs: { type: 'string' },
        modules: { type: 'string', multiple: true }, 'esbuild-meta': { type: 'string', multiple: true },
        'webpack-stats': { type: 'string', multiple: true }, sourcemaps: { type: 'string', multiple: true },
        package: { type: 'string', multiple: true }, include: { type: 'string', multiple: true },
        'include-ssr': { type: 'boolean' }, 'check-assets': { type: 'string', multiple: true },
        'check-vendored': { type: 'string', multiple: true },
        list: { type: 'boolean' }, help: { type: 'boolean' },
      },
    }));
  } catch (error) {
    fail(`${error.message}\n${USAGE}`);
  }
  if (args.help) return void process.stdout.write(USAGE);
  if (!args.out) fail(`--out is required\n${USAGE}`);

  const root = path.resolve(args.root ?? '.');
  const repo = path.resolve(args.repo ?? findRepo(root));
  const config = loadConfig(args.config);
  const errors = [];
  const fromConfig = (p) => path.resolve(config.dir, p);
  const outputsFilter = args.outputs ? new RegExp(args.outputs) : null;

  const packages = new Map(); // package dir -> { dir, via: Set of 'code' | 'asset' | 'helper' | 'data' }
  const assetMap = new Map(); // output path (and basename) -> [absolute source paths]
  const matchedComponents = new Set();
  const usedOverrides = new Set();
  const missingHelpers = new Map(); // helper package -> virtual ids it explains
  let seen = 0; // module ids read from all inputs

  const virtualMap = [...Object.entries(config.virtualModules).map(([k, v]) => [k, [].concat(v)]), ...VIRTUAL_DEFAULTS];
  const componentByModule = (id) => config.components.find((c) => (c.modules ?? []).some((m) => id.startsWith(m)));
  const ignored = (id) => config.ignore.some((entry) => (entry.modules ?? []).some((m) => id.startsWith(m)));

  const addPackageDir = (dir, via) => {
    const real = fs.realpathSync(dir);
    // Workspace packages linked into node_modules are own code.
    if (isInside(real, repo) && !inNodeModules(real)) return;
    if (!packages.has(dir)) packages.set(dir, { dir, via: new Set() });
    packages.get(dir).via.add(via);
  };

  // Classify one module id or file path from any bundler.
  const addModule = (raw, base, via) => {
    const id = slash(String(raw)).replace(/^\0/, '').split('?')[0];
    if (!id || id.startsWith('data:') || id.startsWith('ignored|')) return;
    seen++;
    if (ignored(id)) return;
    const file = pathOf(id, base);
    if (file && inNodeModules(file)) {
      const dir = packageDirOf(file);
      if (!fs.existsSync(path.join(dir, 'package.json'))) errors.push(`${raw}: no package.json at ${dir}`);
      else addPackageDir(dir, via);
      return;
    }
    if (file && isInside(file, repo)) {
      // Own code, unless the config declares it as vendored third-party code.
      const component = componentByModule(slash(path.relative(config.dir, file)))
        ?? componentByModule(slash(path.relative(repo, file)));
      if (component) matchedComponents.add(component);
      return;
    }
    const component = componentByModule(id);
    if (component) return void matchedComponents.add(component);
    if (file) return void errors.push(`${raw}: outside the repository and node_modules; declare it in "components" with "modules"`);
    const virtual = virtualMap.find(([prefix]) => id.startsWith(prefix));
    if (!virtual) return void errors.push(`${raw}: unknown virtual module; map it in "virtualModules" or "ignore" it with a reason`);
    for (const name of virtual[1]) {
      const named = config.components.find((c) => c.name === name);
      if (named) return void matchedComponents.add(named);
      const dir = findInstalled(name, base) ?? findInstalled(name, root);
      if (dir) return void addPackageDir(dir, 'helper');
    }
    const missing = virtual[1].join(' or ');
    missingHelpers.set(missing, [...(missingHelpers.get(missing) ?? []), id]);
  };

  const addAsset = (output, sources) => {
    const list = sources.map((s) => path.resolve(s));
    for (const key of [slash(output), path.basename(output)]) assetMap.set(key, [...(assetMap.get(key) ?? []), ...list]);
  };

  let records = 0;
  for (const input of args.modules ?? []) {
    const stat = fs.statSync(input, { throwIfNoEntry: false });
    if (!stat) fail(`--modules ${input}: not found (is bundled-modules() in the bundler config?)`);
    const files = stat.isDirectory() ? fs.readdirSync(input).filter((f) => f.endsWith('.json')).map((f) => path.join(input, f)) : [input];
    if (!files.length) fail(`--modules ${input}: no bundle records`);
    for (const file of files.sort()) {
      const record = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (!args['include-ssr'] && /ssr|server/i.test(record.environment)) continue;
      records++;
      for (const [output, entry] of Object.entries(record.outputs)) {
        for (const id of entry.modules ?? []) addModule(id, record.root, 'code');
        for (const asset of entry.assets ?? []) addModule(path.resolve(record.root, asset), record.root, 'asset');
        if (entry.assets) addAsset(output, entry.assets.map((a) => path.resolve(record.root, a)));
      }
    }
  }

  if (args.modules && !records) fail('--modules: only SSR bundle records found; is bundled-modules() in the client build?');

  // Every input must contribute modules; an empty one means a wrong file or preset.
  const counted = (input, read) => {
    const before = seen;
    read();
    if (seen === before) errors.push(`${input}: no bundled modules found; wrong file, or stats without modules?`);
  };

  for (const input of args['esbuild-meta'] ?? []) counted(input, () => {
    const meta = JSON.parse(fs.readFileSync(input, 'utf8'));
    for (const [output, info] of Object.entries(meta.outputs ?? {})) {
      if (outputsFilter && !outputsFilter.test(output)) continue;
      const used = Object.entries(info.inputs ?? {}).filter(([, i]) => i.bytesInOutput > 0).map(([p]) => p);
      for (const p of used) addModule(p, root, FONT.test(p) ? 'asset' : 'code');
      if (FONT.test(output)) addAsset(output, used.map((p) => pathOf(slash(p), root)).filter(Boolean));
    }
  });

  for (const input of args['webpack-stats'] ?? []) counted(input, () => {
    const walk = (stats) => {
      const context = stats.context ?? root;
      // Modules inside a concatenated module inherit its chunks.
      const visit = (modules, nested) => {
        for (const m of modules ?? []) {
          if (!nested && (m.orphan || m.chunks?.length === 0)) continue;
          if (m.modules) visit(m.modules, true);
          else if (!/^external\b/.test(m.identifier ?? m.name ?? '')) {
            const id = m.nameForCondition ?? (m.identifier ?? m.name ?? '').split('!').pop();
            addModule(id || m.name, context, 'code');
          }
        }
      };
      visit(stats.modules);
      for (const child of stats.children ?? []) walk(child);
    };
    walk(JSON.parse(fs.readFileSync(input, 'utf8')));
  });

  for (const dir of args.sourcemaps ?? []) counted(dir, () => {
    const visit = (d) => {
      for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
        const file = path.join(d, entry.name);
        if (entry.isDirectory()) visit(file);
        else if (entry.name.endsWith('.map')) {
          const map = JSON.parse(fs.readFileSync(file, 'utf8'));
          for (const source of map.sources ?? []) {
            if (typeof source !== 'string') continue;
            const clean = source.replace(/^webpack:\/\/[^/]*\//, '').replace(/^file:\/\//, '');
            addModule(path.resolve(path.dirname(file), map.sourceRoot ?? '', clean), root, 'code');
          }
        }
      }
    };
    visit(dir);
  });

  for (const name of args.package ?? []) {
    const dir = findInstalled(name, root);
    if (!dir) errors.push(`--package ${name}: not installed below ${root}`);
    else addPackageDir(dir, 'data');
  }

  for (const [name, ids] of missingHelpers) {
    errors.push(`${ids.length} module(s) like "${ids[0]}" are runtime helpers of ${name}, which is not installed; add a component named "${name}" with its license text`);
  }

  // Build entries from packages, then apply overrides.
  const entries = new Map();
  for (const { dir, via } of packages.values()) {
    const pkg = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
    const key = `${pkg.name}@${pkg.version}`;
    const override = config.packages[key] ?? config.packages[pkg.name];
    if (override) usedOverrides.add(config.packages[key] ? key : pkg.name);
    if (override?.exclude) continue;
    if (entries.has(key)) continue; // same version installed twice (pnpm, nested copies)
    if (!pkg.name || !pkg.version) errors.push(`${dir}: package.json lacks name or version`);
    let files = licenseFiles(dir).map((f) => ({ ...f, text: readText(f.file) })).filter((f) => f.text);
    const notes = [];
    if (via.has('helper') && !via.has('code')) {
      notes.push('Bundler runtime helper code.');
      files = files.map((f) => {
        const at = f.text.search(BUNDLED_DEPS_HEADING);
        if (at <= 0) return f;
        notes.push(`${f.name} is cut before "${f.text.slice(at).split('\n')[0].replace(/^#+\s*/, '')}": those cover the tool's own distribution, not this output.`);
        return { ...f, text: f.text.slice(0, at).trimEnd() };
      });
    }
    if (override?.files) {
      const extra = override.files.map((f) => ({ name: path.basename(f), file: fromConfig(f) }));
      for (const f of extra) {
        if (!fs.existsSync(f.file) || !readText(f.file)) errors.push(`${key}: override file ${f.file} is missing or empty`);
      }
      const texts = extra.filter((f) => fs.existsSync(f.file)).map((f) => ({ ...f, text: readText(f.file) }));
      files = override.replaceFiles ? texts : [...files, ...texts];
    }
    if (override?.note) notes.push(override.note);
    const license = override?.license ?? licenseOf(pkg);
    entries.set(key, {
      name: pkg.name, version: pkg.version, license, files, notes, dir, fonts: Boolean(override?.fonts),
      attribution: override?.attribution, sourceOffer: override?.sourceOffer, sourceOfferPending: override?.sourceOfferPending,
      url: override?.sourceUrl ?? repositoryUrl(pkg) ?? `https://www.npmjs.com/package/${pkg.name}/v/${pkg.version}`,
      sourceForm: COPYLEFT.test(license ?? '')
        ? override?.sourceUrl ?? `https://registry.npmjs.org/${pkg.name}/-/${pkg.name.split('/').pop()}-${pkg.version}.tgz (unmodified npm package)`
        : undefined,
    });
    if (!license || /^UNLICENSED$/i.test(license) || /^SEE LICENSE IN/i.test(license)) {
      if (!override?.license) errors.push(`${key}: package.json has no SPDX license (${license ?? 'none'}); confirm the terms and set "license" in an override with a reason`);
    }
    if (!files.length && !override?.allowNoText) {
      errors.push(`${key} (${license ?? 'no license'}): no license text in ${slash(path.relative(root, dir))}; add an override with "files" (verbatim upstream text) and a reason`);
    }
  }

  for (const component of config.components) {
    const required = [].concat(component.requires ?? []);
    const gated = required.length || component.modules;
    const present = required.length
      ? required.every((name) => [...entries.values()].some((e) => e.name === name))
      : matchedComponents.has(component);
    if (gated && !present) continue;
    const key = `${component.name}@${component.version ?? ''}`;
    const files = (component.files ?? []).map((f) => ({ name: path.basename(f), file: fromConfig(f) }));
    for (const f of files) {
      if (!fs.existsSync(f.file) || !readText(f.file)) errors.push(`component ${component.name}: file ${f.file} is missing or empty`);
    }
    if (!files.length && !component.allowNoText) errors.push(`component ${component.name}: needs "files" with its license text`);
    entries.set(key, {
      name: component.name, version: component.version, license: component.license, url: component.url,
      sourceForm: component.sourceForm, notes: [].concat(component.note ?? []), fonts: Boolean(component.assets),
      attribution: component.attribution, sourceOffer: component.sourceOffer, sourceOfferPending: component.sourceOfferPending,
      assets: component.assets, files: files.filter((f) => fs.existsSync(f.file)).map((f) => ({ ...f, text: readText(f.file) })),
    });
  }

  // License terms a copied text cannot satisfy on its own need an explicit entry.
  for (const e of entries.values()) {
    const label = `${e.name}${e.version ? `@${e.version}` : ''} (${e.license})`;
    if (onlyUnder(e.license, CC_BY) && !e.attribution?.trim()) {
      errors.push(`${label}: CC BY needs "attribution" (creator, copyright notice, link to the material, changes made or "unmodified") in its override or component`);
    }
    if (!onlyUnder(e.license, GPL_FAMILY)) continue;
    if (e.sourceOffer?.trim()) continue;
    if (e.sourceOfferPending?.trim()) {
      console.error(`third-party-notices: warning: ${label}: GPL-family source/relink obligation not met yet: ${e.sourceOfferPending}`);
    } else {
      errors.push(`${label}: license text and source pointer do not meet GPL-family source or relinking terms; set "sourceOffer" (printed: where the complete corresponding source or relink materials are, or a written offer) or "sourceOfferPending" (the follow-up that tracks it)`);
    }
  }

  for (const key of Object.keys(config.packages)) {
    if (!usedOverrides.has(key)) console.error(`third-party-notices: warning: override packages["${key}"] matched no bundled package`);
  }

  for (const dir of args['check-assets'] ?? []) {
    const byDir = new Map([...entries.values()].filter((e) => e.dir).map((e) => [slash(e.dir), e]));
    const globs = [...entries.values()].flatMap((e) => (e.assets ?? []).map((g) => globToRegExp(g)));
    const visit = (d) => {
      for (const item of fs.readdirSync(d, { withFileTypes: true })) {
        const file = path.join(d, item.name);
        if (item.isDirectory()) { visit(file); continue; }
        const rel = slash(path.relative(dir, file));
        // Inlined fonts are neither files nor modules, so nothing can attribute them.
        if (TEXT_OUTPUT.test(item.name) && INLINE_FONT.test(fs.readFileSync(file, 'latin1'))
          && !config.inlineFonts.some((entry) => (entry.outputs ?? []).some((g) => globToRegExp(g).test(rel)))) {
          errors.push(`${rel}: contains a font inlined as a data: URI; emit fonts as files (Vite: build.assetsInlineLimit, see the recipe) or list the output in "inlineFonts" with a reason naming the font and its license entry`);
        }
        if (!FONT.test(item.name)) continue;
        if (globs.some((re) => re.test(rel))) continue;
        const sources = assetMap.get(rel) ?? assetMap.get(item.name) ?? [];
        const ok = sources.length > 0 && sources.every((source) => {
          if (globs.some((re) => re.test(slash(path.relative(config.dir, source))))) return true;
          if (!inNodeModules(source)) return false;
          const entry = byDir.get(packageDirOf(source));
          return entry && (entry.fonts || FONT_PACKAGE.test(entry.name) || FONT_LICENSE.test(entry.license ?? ''));
        });
        if (!ok) {
          const from = sources.length ? sources.map((s) => slash(path.relative(config.dir, s))).join(', ') : 'unknown source';
          errors.push(`font ${rel} (from ${from}) has no font license entry; add the font's license via "components" with "assets", or "fonts": true on the package override`);
        }
      }
    };
    if (!fs.existsSync(dir)) errors.push(`--check-assets ${dir}: not found`);
    else visit(dir);
  }

  for (const dir of args['check-vendored'] ?? []) {
    const covered = [...entries.values()].flatMap((e) => e.assets ?? [])
      .concat(config.own.flatMap((o) => o.paths ?? [])).map((g) => globToRegExp(g));
    const visit = (d) => {
      for (const item of fs.readdirSync(d, { withFileTypes: true })) {
        const file = path.join(d, item.name);
        if (item.isDirectory()) visit(file);
        else if (SHIPPED_FILE.test(item.name)) {
          const rel = slash(path.relative(config.dir, file));
          if (!covered.some((re) => re.test(rel))) errors.push(`${rel}: not covered by any component "assets" or "own" glob`);
        }
      }
    };
    if (!fs.existsSync(dir)) errors.push(`--check-vendored ${dir}: not found`);
    else visit(dir);
  }

  const includes = (args.include ?? []).map((file) => {
    if (!fs.existsSync(file) || !readText(file)) errors.push(`--include ${file}: missing or empty`);
    return { name: path.basename(file), text: fs.existsSync(file) ? readText(file) : '' };
  });

  if (errors.length) {
    fs.rmSync(args.out, { force: true });
    console.error(`third-party-notices: ${errors.length} problem(s); ${args.out} not written:\n  ${[...new Set(errors)].join('\n  ')}`);
    process.exit(1);
  }

  let title = args.title;
  if (!title) {
    try {
      title = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).name;
    } catch {
      // no package.json: fall back to the directory name
    }
    title ||= path.basename(root);
  }
  const sorted = [...entries.values()].sort((a, b) => compare(a.name, b.name) || compare(a.version ?? '', b.version ?? ''));
  const rule = '='.repeat(72);
  const parts = [
    `Third-party notices for ${title}\n\n`,
    `${title} bundles the third-party components listed below. Each component\nkeeps its own license; its license and notice texts follow verbatim.\n\n`,
    ...config.intro.map((line) => `${line}\n`),
    config.intro.length ? '\n' : '',
    `Components: ${sorted.length}\n`,
  ];
  for (const e of sorted) {
    const head = [`${rule}`, `${e.name}${e.version ? ` ${e.version}` : ''}`, `License: ${e.license ?? 'NOASSERTION'}`];
    if (e.url) head.push(`Source: ${e.url}`);
    if (e.sourceForm) head.push(`Source Code Form: ${e.sourceForm}`);
    if (e.sourceOffer) head.push(`Source offer: ${e.sourceOffer}`);
    if (e.attribution) head.push(`Attribution: ${e.attribution}`);
    for (const note of e.notes) head.push(`Note: ${note}`);
    parts.push(`\n${head.join('\n')}\n`);
    for (const f of e.files) parts.push(`\n--- ${f.name} ---\n\n${f.text}\n`);
  }
  for (const inc of includes) parts.push(`\n${rule}\nIncluded from ${inc.name}\n${rule}\n\n${inc.text}\n`);
  fs.mkdirSync(path.dirname(path.resolve(args.out)), { recursive: true });
  fs.writeFileSync(args.out, parts.join(''));
  if (args.list) for (const e of sorted) console.log(`${e.name}@${e.version ?? ''}\t${e.license}\t${e.files.map((f) => f.name).join(', ')}`);
  console.error(`third-party-notices: wrote ${args.out} (${sorted.length} components)`);
}

main();
