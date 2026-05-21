#!/usr/bin/env node
/**
 * generate-code-map.js
 * OtterQuote code-map generator — scans HTML pages and their externally referenced
 * JS files to produce a complete edge-function reference map.
 *
 * Outputs:
 *   ../Docs/code-map.json   — machine-readable map
 *   ../Docs/code-map.md     — human-readable summary
 *
 * Usage: node scripts/generate-code-map.js [--repo-root <path>]
 *
 * Fix (86e1ewyvh): Now scans external JS files (src="js/*.js") in addition to
 * inline <script> blocks for EF fetch() and supabase.functions.invoke() calls.
 *
 * EF call patterns detected:
 *   1. fetch(...) calls:     /functions/v1/<ef-name>
 *   2. invoke calls:         supabase.functions.invoke('<ef-name>')
 */

'use strict';

const fs   = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const args     = process.argv.slice(2);
const rootIdx  = args.indexOf('--repo-root');
const REPO_ROOT = rootIdx !== -1 ? args[rootIdx + 1] : path.resolve(__dirname, '..');
const DOCS_DIR  = path.resolve(REPO_ROOT, '..', 'Docs');

const TODAY = new Date().toISOString().slice(0, 10);

// ---------------------------------------------------------------------------
// EF name extraction patterns
// ---------------------------------------------------------------------------
const EF_PATTERNS = [
  // fetch('/functions/v1/ef-name'  or  fetch(`...functions/v1/ef-name`...)
  /\/functions\/v1\/([a-z0-9][a-z0-9_-]*[a-z0-9])/g,
  // supabase.functions.invoke('ef-name') or invoke("ef-name")
  /supabase\.functions\.invoke\(['"]([a-z0-9][a-z0-9_-]*[a-z0-9])['"]/g,
];

/**
 * Extract all EF names referenced in a block of text.
 * Returns a de-duplicated sorted array.
 */
function extractEfNames(text) {
  const found = new Set();
  for (const pattern of EF_PATTERNS) {
    pattern.lastIndex = 0; // reset stateful regex
    let m;
    while ((m = pattern.exec(text)) !== null) {
      found.add(m[1]);
    }
  }
  return [...found].sort();
}

// ---------------------------------------------------------------------------
// Script / stylesheet extraction from HTML
// ---------------------------------------------------------------------------
const SCRIPT_SRC_RE    = /<script[^>]+\bsrc=["']([^"']+)["'][^>]*>/gi;
const INLINE_SCRIPT_RE = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
const STYLESHEET_RE    = /<link[^>]+rel=["']stylesheet["'][^>]+href=["']([^"']+)["'][^>]*>|<link[^>]+href=["']([^"']+)["'][^>]+rel=["']stylesheet["'][^>]*>/gi;

function parseHtml(html) {
  const scripts     = [];
  const stylesheets = [];

  // External script sources
  let m;
  SCRIPT_SRC_RE.lastIndex = 0;
  while ((m = SCRIPT_SRC_RE.exec(html)) !== null) {
    scripts.push(m[1]);
  }

  // Stylesheets
  STYLESHEET_RE.lastIndex = 0;
  while ((m = STYLESHEET_RE.exec(html)) !== null) {
    stylesheets.push(m[1] || m[2]);
  }

  // Inline EF refs (from <script> blocks without src)
  const inlineEfRefs = [];
  INLINE_SCRIPT_RE.lastIndex = 0;
  while ((m = INLINE_SCRIPT_RE.exec(html)) !== null) {
    for (const ef of extractEfNames(m[1])) inlineEfRefs.push(ef);
  }

  return { scripts, stylesheets, inlineEfRefs };
}

// ---------------------------------------------------------------------------
// Build per-JS-file EF cache so we only read each file once
// ---------------------------------------------------------------------------
function buildJsEfCache(jsDir) {
  const cache = {}; // basename → [ef-name, ...]
  if (!fs.existsSync(jsDir)) return cache;
  for (const file of fs.readdirSync(jsDir)) {
    if (!file.endsWith('.js')) continue;
    try {
      const src = fs.readFileSync(path.join(jsDir, file), 'utf8');
      cache[file] = extractEfNames(src);
    } catch (_) {
      cache[file] = [];
    }
  }
  return cache;
}

// ---------------------------------------------------------------------------
// Main scan
// ---------------------------------------------------------------------------
function run() {
  const jsDir  = path.join(REPO_ROOT, 'js');
  const jsCache = buildJsEfCache(jsDir);

  const htmlFiles = fs.readdirSync(REPO_ROOT)
    .filter(f => f.endsWith('.html'))
    .sort();

  const pages = {};
  let totalPageToEf = 0;

  for (const htmlFile of htmlFiles) {
    const html = fs.readFileSync(path.join(REPO_ROOT, htmlFile), 'utf8');
    const { scripts, stylesheets, inlineEfRefs } = parseHtml(html);

    // Collect EF refs from inline blocks
    const efSet = new Set(inlineEfRefs);

    // --- FIX 86e1ewyvh: also scan external js/*.js files ---
    for (const src of scripts) {
      // Match paths like js/foo.js or ./js/foo.js
      const jsMatch = src.match(/(?:^|\/)(js\/[a-zA-Z0-9_-]+\.js)$/);
      if (!jsMatch) continue;
      const basename = path.basename(jsMatch[1]);
      if (jsCache[basename]) {
        for (const ef of jsCache[basename]) efSet.add(ef);
      }
    }

    const edge_function_refs = [...efSet].sort();
    totalPageToEf += edge_function_refs.length;

    pages[htmlFile] = { scripts, stylesheets, edge_function_refs };
  }

  // Count distinct EF names referenced from pages (for console output)
  const referencedEfNames = new Set();
  for (const { edge_function_refs } of Object.values(pages)) {
    for (const ef of edge_function_refs) referencedEfNames.add(ef);
  }

  // Count total deployed EFs from supabase/functions directory
  const efFunctionsDir = path.join(REPO_ROOT, 'supabase', 'functions');
  let deployedEfCount = 0;
  if (fs.existsSync(efFunctionsDir)) {
    deployedEfCount = fs.readdirSync(efFunctionsDir)
      .filter(f => fs.statSync(path.join(efFunctionsDir, f)).isDirectory())
      .length;
  }

  // Build output
  const output = {
    generated_date: TODAY,
    repo: 'otterquote-platform',
    state: 'pre-D-211-static-site',
    summary: {
      pages: htmlFiles.length,
      edge_functions: deployedEfCount || referencedEfNames.size,
      sql_tables: 46, // maintained manually — schema changes tracked in sql/ migrations
      cross_references: {
        page_to_edge_function: totalPageToEf,
        edge_function_to_table: 131, // maintained manually — EF→table refs from supabase/functions
        total: totalPageToEf + 131,
      },
    },
    pages,
  };

  // Write JSON
  fs.mkdirSync(DOCS_DIR, { recursive: true });
  fs.writeFileSync(path.join(DOCS_DIR, 'code-map.json'), JSON.stringify(output, null, 2), 'utf8');

  // Write Markdown
  const md = buildMarkdown(output);
  fs.writeFileSync(path.join(DOCS_DIR, 'code-map.md'), md, 'utf8');

  console.log(`✓ code-map generated: ${htmlFiles.length} pages, ${deployedEfCount} deployed EFs, ${referencedEfNames.size} referenced, ${totalPageToEf} page→EF refs`);
  return output;
}

// ---------------------------------------------------------------------------
// Markdown renderer
// ---------------------------------------------------------------------------
function buildMarkdown(output) {
  const { generated_date, repo, state, summary, pages } = output;
  const lines = [
    `# OtterQuote Code Map`,
    ``,
    `**Generated:** ${generated_date}  `,
    `**Repo:** ${repo}  `,
    `**State:** ${state}  `,
    ``,
    `## Summary`,
    ``,
    `| Category | Count |`,
    `|---|---|`,
    `| HTML Pages | ${summary.pages} |`,
    `| Edge Functions | ${summary.edge_functions} |`,
    `| SQL Tables (created) | ${summary.sql_tables} |`,
    `| Cross-refs: page→EF | ${summary.cross_references.page_to_edge_function} |`,
    `| Cross-refs: EF→table | ${summary.cross_references.edge_function_to_table} |`,
    `| Cross-refs total | ${summary.cross_references.total} |`,
    ``,
    `---`,
    ``,
    `## HTML Pages`,
  ];

  // Count external (CDN) vs local scripts
  for (const [htmlFile, data] of Object.entries(pages)) {
    lines.push(``, `### \`${htmlFile}\``);
    const localScripts  = data.scripts.filter(s => !s.startsWith('http'));
    const externalCount = data.scripts.filter(s => s.startsWith('http')).length;
    if (localScripts.length)  lines.push(`- **Local scripts:** ${localScripts.join(', ')}`);
    if (externalCount)        lines.push(`- **External scripts:** ${externalCount} (Sentry, Supabase JS, GTM, etc.)`);
    if (data.stylesheets.filter(s => !s.startsWith('http')).length) {
      lines.push(`- **Stylesheets:** ${data.stylesheets.filter(s => !s.startsWith('http')).join(', ')}`);
    }
    if (data.edge_function_refs.length) {
      lines.push(`- **Edge functions called:** ${data.edge_function_refs.join(', ')}`);
    }
  }

  return lines.join('\n') + '\n';
}

// ---------------------------------------------------------------------------
run();
