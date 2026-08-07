'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const core = require('../core');

test('valid GXML parses without diagnostics and exposes navigation symbols', () => {
  const source = `<Page id="root" class="screen shell">
    <Component name="StatusCard"><Panel><Slot /></Panel></Component>
    <StatusCard id="status" />
    <Repeat items="{pilots}" key="id"><Row class="pilot" /></Repeat>
</Page>`;
  const parsed = core.parseGxml(source);
  assert.deepEqual(parsed.diagnostics, []);
  assert.equal(parsed.roots.length, 1);
  assert.ok(parsed.components.has('StatusCard'));
  const symbols = core.collectSymbols(source, 'gxml');
  assert.ok(symbols.some((item) => item.kind === 'component' && item.name === 'StatusCard' && item.definition));
  assert.equal(symbols.filter((item) => item.kind === 'component' && item.name === 'StatusCard').length, 2);
  assert.ok(symbols.some((item) => item.kind === 'class' && item.name === 'pilot'));
  assert.ok(symbols.some((item) => item.kind === 'id' && item.name === 'status'));
});

test('GXML diagnostics catch structural and focused contract errors', () => {
  const source = `<Page><Repeat items="pilots"><Row /><Row /></Repeat><Select><Label /></Select><Param required="true" default="x"></Page>`;
  const codes = new Set(core.parseGxml(source).diagnostics.map((item) => item.code));
  assert.ok(codes.has('gxml.repeat-items'));
  assert.ok(codes.has('gxml.repeat-child'));
  assert.ok(codes.has('gxml.select-child'));
  assert.ok(codes.has('gxml.param-default'));
  assert.ok(codes.has('gxml.mismatched-close'));
});

test('valid nested media GCSS parses properties and custom-property symbols', () => {
  const source = `Page {
    --Ink: #f2f4f7;
    display: flex;
    color: var(--Ink);
}
@media (min-width: 800px) {
    Row:hover { gap: calc(4px * 2); }
}`;
  const parsed = core.parseGcss(source);
  assert.deepEqual(parsed.diagnostics, []);
  assert.equal(parsed.rules.length, 2);
  const symbols = core.collectSymbols(source, 'gcss').filter((item) => item.kind === 'custom-property');
  assert.equal(symbols.length, 2);
  assert.equal(symbols[0].name, '--Ink');
  assert.equal(symbols[0].definition, true);
  assert.equal(symbols[1].definition, false);
});

test('GCSS diagnostics are recoverable and focused', () => {
  const source = `.card:active { browser-property: 10px; color } @media (orientation: landscape) { Row { gap: 4px; }`;
  const codes = new Set(core.parseGcss(source).diagnostics.map((item) => item.code));
  assert.ok(codes.has('gcss.unknown-pseudo'));
  assert.ok(codes.has('gcss.unknown-property'));
  assert.ok(codes.has('gcss.missing-colon'));
  assert.ok(codes.has('gcss.unsupported-media'));
  assert.ok(codes.has('gcss.unclosed-block'));
});

test('completion contexts distinguish GXML tags, attributes, and values', () => {
  assert.deepEqual(core.gxmlCompletionContext('<Pa', 3), { kind: 'tag', prefix: 'Pa' });
  assert.deepEqual(core.gxmlCompletionContext('<Slider st', 10), { kind: 'attribute', tag: 'Slider', prefix: 'st' });
  assert.deepEqual(core.gxmlCompletionContext('<Slider disabled="tr', 20), { kind: 'attribute-value', tag: 'Slider', attribute: 'disabled', prefix: 'tr' });
  assert.equal(core.gcssCompletionContext('Page { flex-', 12).kind, 'property');
  assert.deepEqual(core.gcssCompletionContext('Page { display: fl', 18), { kind: 'value', property: 'display', prefix: 'fl' });
});

test('formatters are deterministic and idempotent', () => {
  const gxml = '<Page>\n<Panel>\n<Label />\n</Panel>\n</Page>';
  const expectedGxml = '<Page>\n    <Panel>\n        <Label />\n    </Panel>\n</Page>\n';
  assert.equal(core.formatGxml(gxml), expectedGxml);
  assert.equal(core.formatGxml(expectedGxml), expectedGxml);
  const gcss = 'Page{display:flex;color:#fff;}\nPage:hover{background:#123;}';
  const formatted = 'Page {\n    display: flex;\n    color: #fff;\n}\nPage:hover {\n    background: #123;\n}\n';
  assert.equal(core.formatGcss(gcss), formatted);
  assert.equal(core.formatGcss(formatted), formatted);
  const media = '@media (min-width: 800px){Row:hover{gap:8px;}}';
  assert.equal(core.formatGcss(media), '@media (min-width: 800px) {\n    Row:hover {\n        gap: 8px;\n    }\n}\n');
  const cdata = '<Page><![CDATA[<raw>]]></Page>';
  assert.equal(core.formatGxml(cdata), cdata);
});

test('extension schema stays in parity with the canonical GDScript vocabulary', () => {
  const canonicalPath = path.resolve(__dirname, '../../../addons/godot_cascade/tooling/language_service.gd');
  const source = fs.readFileSync(canonicalPath, 'utf8');
  function dictionaryBlock(name) {
    const match = source.match(new RegExp(`const ${name} := \\{([\\s\\S]*?)\\n\\}`));
    assert.ok(match, `missing ${name}`);
    return match[1];
  }
  function dictionaryKeys(name) {
    return [...dictionaryBlock(name).matchAll(/"([^"]+)"\s*:/g)].map((match) => match[1]).sort();
  }
  const pseudoMatch = source.match(/const PSEUDO_STATES := \[([^\]]+)\]/);
  assert.ok(pseudoMatch);
  const pseudos = [...pseudoMatch[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]).sort();
  assert.deepEqual(Object.keys(core.data.elements).sort(), dictionaryKeys('ELEMENTS'));
  assert.deepEqual(Object.keys(core.data.properties).sort(), dictionaryKeys('PROPERTIES'));
  assert.deepEqual(Object.keys(core.data.pseudoStates).sort(), pseudos);
  assert.deepEqual([...core.data.elementAttributes['*']].sort(), dictionaryKeys('GLOBAL_ATTRIBUTES'));

  const elementBlock = dictionaryBlock('ELEMENT_ATTRIBUTES');
  const canonicalElements = {};
  for (const match of elementBlock.matchAll(/"([^"]+)"\s*:\s*\[([^\]]*)\]/g)) {
    canonicalElements[match[1]] = [...match[2].matchAll(/"([^"]+)"/g)].map((value) => value[1]).sort();
  }
  const schemaElements = Object.fromEntries(Object.entries(core.data.elementAttributes).filter(([name]) => name !== '*').map(([name, values]) => [name, [...values].sort()]));
  assert.deepEqual(schemaElements, canonicalElements);
});

test('schema reflects generated-binding and focused transition contracts', () => {
  assert.ok(core.data.elementAttributes.Bindings.includes('output'));
  assert.deepEqual(core.data.properties['transform-origin'].values, [
    'left top', 'left center', 'left bottom',
    'center top', 'center center', 'center bottom',
    'right top', 'right center', 'right bottom'
  ]);
  assert.ok(!core.data.properties['transition-property'].values.includes('opacity'));
  assert.ok(!core.data.properties['transition-property'].values.includes('transform'));
  assert.ok(core.data.properties['transition-property'].values.includes('flex-basis'));
});

test('package and grammar manifests are valid and dependency-free', () => {
  const root = path.resolve(__dirname, '..');
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  assert.equal(manifest.main, './extension.js');
  assert.equal(manifest.license, 'Unlicense');
  assert.equal(manifest.dependencies, undefined);
  assert.deepEqual(manifest.contributes.languages.flatMap((language) => language.extensions).sort(), ['.gcss', '.gxml']);
  for (const grammar of manifest.contributes.grammars) JSON.parse(fs.readFileSync(path.join(root, grammar.path), 'utf8'));
});
