'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const core = require('../core');
const providers = require('../provider-core');

function source(uri, text, language) {
  return { uri, text, language, symbols: core.collectSymbols(text, language) };
}

test('class, ID, and custom-property rename plans retain workspace scope', () => {
  const document = source('file:///screen.gxml', '<Page id="hud" class="card" />', 'gxml');
  const style = source('file:///theme.gcss', '.card, #hud { --accent: #fff; color: var(--accent); }', 'gcss');
  for (const [target, current, workspace] of [
    [document.symbols.find((symbol) => symbol.kind === 'class'), document, [style]],
    [document.symbols.find((symbol) => symbol.kind === 'id'), document, [style]],
    [style.symbols.find((symbol) => symbol.kind === 'custom-property'), style, [document]]
  ]) {
    assert.equal(providers.renameScope(target), 'workspace');
    assert.deepEqual(providers.selectRenameSources(target, current, workspace).map((item) => item.uri).sort(), ['file:///screen.gxml', 'file:///theme.gcss']);
  }
  assert.equal(providers.renameMatches(document.symbols.find((symbol) => symbol.kind === 'class'), style.symbols.find((symbol) => symbol.kind === 'class')), true);
  assert.equal(providers.renameMatches(document.symbols.find((symbol) => symbol.kind === 'id'), style.symbols.find((symbol) => symbol.kind === 'id')), true);
  const customProperties = style.symbols.filter((symbol) => symbol.kind === 'custom-property');
  assert.equal(providers.renameMatches(customProperties[0], customProperties[1]), true);
});

test('reusable component rename is document-local and case-insensitive', () => {
  const document = source('file:///screen.gxml', '<component name="StatusCard"><Panel /></component><STATUSCARD />', 'gxml');
  const other = source('file:///other.gxml', '<Component name="StatusCard"><Panel /></Component><StatusCard />', 'gxml');
  const target = document.symbols.find((symbol) => symbol.kind === 'component' && symbol.definition);
  assert.ok(target);
  assert.equal(providers.renameScope(target), 'document');
  assert.deepEqual(providers.selectRenameSources(target, document, [other]), [document]);
  const localMatches = document.symbols.filter((symbol) => providers.renameMatches(target, symbol));
  assert.equal(localMatches.length, 2);
  assert.deepEqual(localMatches.map((symbol) => symbol.name), ['StatusCard', 'STATUSCARD']);
  const invocation = document.symbols.find((symbol) => symbol.kind === 'component' && !symbol.definition);
  assert.equal(providers.definitionMatches(invocation, target), true);
  assert.equal(providers.renameMatches(target, { kind: 'tag', name: 'statuscard' }), true);
  assert.equal(providers.renameMatches(target, { kind: 'tag', name: 'Button' }), false);
});

test('current source replaces a stale workspace copy in workspace rename plans', () => {
  const current = source('file:///screen.gxml', '<Page class="new-name" />', 'gxml');
  const stale = source('file:///screen.gxml', '<Page class="old-name" />', 'gxml');
  const target = current.symbols.find((symbol) => symbol.kind === 'class');
  const selected = providers.selectRenameSources(target, current, [stale]);
  assert.equal(selected.length, 1);
  assert.equal(selected[0].text, current.text);
});

test('a component using a reserved built-in name cannot become a rename target', () => {
  const document = source('file:///invalid.gxml', '<Page><Component name="Component"><Panel /></Component></Page>', 'gxml');
  const declaration = document.symbols.find((symbol) => symbol.kind === 'component' && symbol.definition);
  const declarationTags = document.symbols.filter((symbol) => symbol.kind === 'tag' && symbol.name === 'Component');
  assert.ok(declaration);
  assert.equal(providers.isRenameableTarget(declaration), false);
  assert.equal(providers.renameMatches(declaration, declarationTags[0]), false);
  assert.equal(providers.renameMatches(declaration, declarationTags[1]), false);
});
