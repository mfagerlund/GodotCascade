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

test('built-in contracts and reusable components canonicalize tag case', () => {
  const source = `<page>
    <component name="StatusCard"><panel /></component>
    <statuscard />
    <repeat items="{pilots}" key="id"><row /></repeat>
    <select><option text="One" /></select>
    <param name="title" required="true" default="fallback" />
</page>`;
  const parsed = core.parseGxml(source);
  assert.ok(parsed.components.has('StatusCard'));
  assert.deepEqual(new Set(parsed.diagnostics.map((item) => item.code)), new Set(['gxml.param-default']));
  const components = core.collectSymbols(source, 'gxml').filter((symbol) => symbol.kind === 'component');
  assert.equal(components.length, 2);
  assert.equal(components[0].definition, true);
  assert.equal(components[1].name, 'statuscard');
  assert.equal(components[1].definition, false);
});

test('lowercase built-ins enforce their canonical attributes and child contracts', () => {
  const diagnostics = core.parseGxml('<page><button disabeld="true" /><select><label /></select><repeat items="pilots"><row /><row /></repeat></page>').diagnostics;
  const codes = new Set(diagnostics.map((item) => item.code));
  assert.ok(codes.has('gxml.unknown-attribute'));
  assert.ok(codes.has('gxml.select-child'));
  assert.ok(codes.has('gxml.repeat-items'));
  assert.ok(codes.has('gxml.repeat-child'));
});

test('document-root and focus ownership diagnostics mirror hard runtime contracts', () => {
  assert.ok(core.parseGxml('<bindings class="ScreenBindings" />').diagnostics.some((item) => item.code === 'gxml.nonvisual-root'));
  assert.ok(core.parseGxml('<Page if="{show}" />').diagnostics.some((item) => item.code === 'gxml.root-if'));
  assert.ok(core.parseGxml('<RootCard if="{show}" />').diagnostics.some((item) => item.code === 'gxml.root-if'));
  for (const tag of ['Button', 'Label', 'Slider']) {
    assert.ok(core.parseGxml(`<Page><${tag} focus-trap="true" /></Page>`).diagnostics.some((item) => item.code === 'gxml.focus-trap-owner'));
  }
  assert.ok(!core.parseGxml('<Page><Button focus-trap="off" /></Page>').diagnostics.some((item) => item.code === 'gxml.focus-trap-owner'));
  assert.ok(!core.gxmlAttributeNames('Button').includes('focus-trap'));
  assert.ok(core.gxmlAttributeNames('Panel').includes('focus-trap'));
  assert.ok(core.gxmlAttributeNames('ProjectWidget').includes('focus-trap'));
});

test('Repeat diagnostics enforce stable focus and virtual item contracts', () => {
  const focus = core.parseGxml('<Page><Repeat items="{items}" key="id"><Row><Button autofocus="true" /><Panel focus-trap="true" /></Row></Repeat></Page>');
  assert.equal(focus.diagnostics.filter((item) => item.code === 'gxml.repeat-focus').length, 2);
  const nested = core.parseGxml('<Page><Repeat items="{groups}" key="id"><Repeat items="{item.rows}" key="id" virtual="true" item-height="30"><Row /></Repeat></Repeat></Page>');
  assert.ok(nested.diagnostics.some((item) => item.code === 'gxml.virtual-nesting'));
  const conditional = core.parseGxml('<Page><Scroll><Repeat items="{items}" key="id" virtual="true" item-height="30"><Row if="{item.shown}" visible="{item.shown}" /></Repeat></Scroll></Page>');
  assert.ok(conditional.diagnostics.some((item) => item.code === 'gxml.virtual-root-if'));
  assert.ok(conditional.diagnostics.some((item) => item.code === 'gxml.virtual-root-visible'));
  const harmless = core.parseGxml('<Page><Scroll><Repeat items="{items}" key="id" virtual="true" item-height="30"><Row visible="true"><Label visible="{item.shown}" /></Row></Repeat></Scroll></Page>');
  assert.ok(!harmless.diagnostics.some((item) => item.code === 'gxml.virtual-root-visible'));
});

test('Scroll and table diagnostics mirror runtime structural ownership', () => {
  assert.ok(core.parseGxml('<Scroll><Label /><Label /></Scroll>').diagnostics.some((item) => item.code === 'gxml.scroll-child'));
  assert.ok(!core.parseGxml('<Scroll><Bindings class="ViewBindings" /><Panel /></Scroll>').diagnostics.some((item) => item.code === 'gxml.scroll-child'));
  const invalidCases = [
    ['<Table><Label /></Table>', 'gxml.table-child'],
    ['<Table><TableHeader><Label /></TableHeader></Table>', 'gxml.table-group-child'],
    ['<Table><TableRow><Label /></TableRow></Table>', 'gxml.table-row-child'],
    ['<Page><TableHeader /></Page>', 'gxml.table-group-parent'],
    ['<Page><TableRow /></Page>', 'gxml.table-row-parent'],
    ['<Page><TableCell /></Page>', 'gxml.table-cell-parent'],
    ['<Table><Repeat items="{rows}" key="id"><Label /></Repeat></Table>', 'gxml.table-repeat-template']
  ];
  for (const [source, code] of invalidCases) assert.ok(core.parseGxml(source).diagnostics.some((item) => item.code === code), `${code} missing`);
  const valid = '<Table><TableHeader><TableRow><TableHeaderCell /></TableRow></TableHeader><TableBody><Repeat items="{rows}" key="id"><TableRow><TableCell /></TableRow></Repeat></TableBody></Table>';
  assert.ok(!core.parseGxml(valid).diagnostics.some((item) => item.code.startsWith('gxml.table-')));
  const reusableRow = '<Page><Component name="DataRow"><TableRow><TableCell /></TableRow></Component><Table><DataRow /></Table></Page>';
  assert.ok(!core.parseGxml(reusableRow).diagnostics.some((item) => item.code.startsWith('gxml.table-')));
  const slottedRow = '<Page><Component name="DataRow"><TableRow><Slot /></TableRow></Component><Table><DataRow><TableCell /></DataRow></Table></Page>';
  assert.ok(!core.parseGxml(slottedRow).diagnostics.some((item) => item.code.startsWith('gxml.table-')));
  const fallbackRow = '<Page><Component name="DataRow"><TableRow><Slot><TableCell /></Slot></TableRow></Component><Table><DataRow /></Table></Page>';
  assert.ok(!core.parseGxml(fallbackRow).diagnostics.some((item) => item.code.startsWith('gxml.table-')));
  const nestedSlotContext = '<Page><Component name="Rows"><Column><Table><TableBody><Slot /></TableBody></Table></Column></Component><Rows><TableRow><TableCell /></TableRow></Rows></Page>';
  assert.ok(!core.parseGxml(nestedSlotContext).diagnostics.some((item) => item.code.startsWith('gxml.table-')));
});

test('duplicate IDs are diagnosed within document or component-template scope', () => {
  const duplicate = core.parseGxml('<Page><Panel id="card" /><Panel id="card" /></Page>');
  assert.ok(duplicate.diagnostics.some((item) => item.code === 'gxml.duplicate-id'));
  const componentDuplicate = core.parseGxml('<Page><Component name="Card"><Panel><Label id="title" /><Label id="title" /></Panel></Component></Page>');
  assert.ok(componentDuplicate.diagnostics.some((item) => item.code === 'gxml.duplicate-id'));
  const scoped = core.parseGxml('<Page><Component name="Card"><Label id="title" /></Component><Component name="Dialog"><Label id="title" /></Component><Label id="title" /></Page>');
  assert.ok(!scoped.diagnostics.some((item) => item.code === 'gxml.duplicate-id'));
  const separateInvocations = core.parseGxml('<Page><Component name="Card"><Panel><Slot /></Panel></Component><Card id="a"><Label id="title" /></Card><Card id="b"><Label id="title" /></Card></Page>');
  assert.ok(!separateInvocations.diagnostics.some((item) => item.code === 'gxml.duplicate-id'));
  const oneInvocation = core.parseGxml('<Page><Component name="Card"><Panel><Slot /></Panel></Component><Card id="a"><Label id="title" /><Label id="title" /></Card></Page>');
  assert.ok(oneInvocation.diagnostics.some((item) => item.code === 'gxml.duplicate-id'));
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

test('GXML diagnostics reject unknown built-in attributes without constraining custom components', () => {
  const builtIn = core.parseGxml('<Page><Button disabeld="true" /></Page>');
  assert.ok(builtIn.diagnostics.some((item) => item.code === 'gxml.unknown-attribute'));
  const custom = core.parseGxml('<ProjectWidget project-setting="true" />');
  assert.ok(!custom.diagnostics.some((item) => item.code === 'gxml.unknown-attribute'));
  assert.ok(core.parseGxml('<Button Disabled="true" />').diagnostics.some((item) => item.code === 'gxml.unknown-attribute'));
  assert.ok(core.parseGxml('<Page __component_scope="spoofed" />').diagnostics.some((item) => item.code === 'gxml.unknown-attribute'));
  assert.ok(core.parseGxml('<ProjectWidget __virtual_scroll_offset="900" />').diagnostics.some((item) => item.code === 'gxml.unknown-attribute'));
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
  const quoted = '<Button text="1 > 0" dis';
  assert.deepEqual(core.gxmlCompletionContext(quoted, quoted.length), { kind: 'attribute', tag: 'Button', prefix: 'dis' });
  assert.equal(core.gcssCompletionContext('Page { flex-', 12).kind, 'property');
  assert.deepEqual(core.gcssCompletionContext('Page { display: fl', 18), { kind: 'value', property: 'display', prefix: 'fl' });
});

test('runtime element aliases are treated as built-ins', () => {
  assert.equal(core.isBuiltinElement('Input'), true);
  assert.equal(core.isBuiltinElement('radio'), true);
  assert.equal(core.isBuiltinElement('PAGE'), true);
  assert.equal(core.isBuiltinElement('ProjectWidget'), false);
});

test('attribute completion vocabulary canonicalizes aliases and element case', () => {
  assert.ok(core.gxmlAttributeNames('button').includes('on-pressed'));
  assert.ok(core.gxmlAttributeNames('Input').includes('bind-text'));
  assert.ok(core.gxmlAttributeNames('Radio').includes('bind-checked'));
  assert.ok(!core.gxmlAttributeNames('Bindings').includes('format-text'));
  assert.ok(core.gxmlAttributeNames('ProjectWidget').includes('id'));
  assert.ok(!core.gxmlAttributeNames('ProjectWidget').includes('format-text'));
});

test('formatters are deterministic and idempotent', () => {
  const gxml = '<Page>\n<Panel>\n<Label />\n</Panel>\n</Page>';
  const expectedGxml = '<Page>\n    <Panel>\n        <Label />\n    </Panel>\n</Page>\n';
  assert.equal(core.formatGxml(gxml), expectedGxml);
  assert.equal(core.formatGxml(expectedGxml), expectedGxml);
  const quotedGreaterThan = '<Page>\n<Button text="1 > 0" />\n<Label text="Still nested" />\n</Page>';
  assert.equal(core.formatGxml(quotedGreaterThan), '<Page>\n    <Button text="1 > 0" />\n    <Label text="Still nested" />\n</Page>\n');
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
  const languageServicePath = path.resolve(__dirname, '../../../addons/godot_cascade/tooling/language_service.gd');
  const schemaPath = path.resolve(__dirname, '../../../addons/godot_cascade/runtime/gxml_schema.gd');
  const source = fs.readFileSync(languageServicePath, 'utf8');
  const schemaSource = fs.readFileSync(schemaPath, 'utf8');
  function dictionaryBlock(name, sourceText = source) {
    const match = sourceText.match(new RegExp(`const ${name} := \\{([\\s\\S]*?)\\n\\}`));
    assert.ok(match, `missing ${name}`);
    return match[1];
  }
  function dictionaryKeys(name, sourceText = source) {
    return [...dictionaryBlock(name, sourceText).matchAll(/"([^"]+)"\s*:/g)].map((match) => match[1]).sort();
  }
  const pseudoMatch = source.match(/const PSEUDO_STATES := \[([^\]]+)\]/);
  assert.ok(pseudoMatch);
  const pseudos = [...pseudoMatch[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]).sort();
  assert.deepEqual(Object.keys(core.data.elements).sort(), dictionaryKeys('ELEMENTS'));
  assert.deepEqual(Object.keys(core.data.properties).sort(), dictionaryKeys('PROPERTIES'));
  assert.deepEqual(Object.keys(core.data.pseudoStates).sort(), pseudos);
  assert.deepEqual([...core.data.elementAttributes['*']].sort(), dictionaryKeys('GLOBAL_ATTRIBUTES'));

  const elementBlock = dictionaryBlock('ELEMENT_ATTRIBUTES', schemaSource);
  const canonicalElements = {};
  for (const match of elementBlock.matchAll(/"([^"]+)"\s*:\s*\[([^\]]*)\]/g)) {
    canonicalElements[match[1]] = [...match[2].matchAll(/"([^"]+)"/g)].map((value) => value[1]).sort();
  }
  const schemaElements = Object.fromEntries(Object.entries(core.data.elementAttributes).filter(([name]) => name !== '*').map(([name, values]) => [name, [...values].sort()]));
  assert.deepEqual(schemaElements, canonicalElements);
  const generatedMatch = schemaSource.match(/const GENERATED_BINDING_ATTRIBUTES := \[([^\]]+)\]/);
  assert.ok(generatedMatch);
  const generatedAttributes = [...generatedMatch[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]).sort();
  assert.deepEqual([...core.data.generatedBindingAttributes].sort(), generatedAttributes);
  const focusMatch = schemaSource.match(/const FOCUS_TRAP_ELEMENTS := \[([^\]]+)\]/);
  assert.ok(focusMatch);
  const focusElements = [...focusMatch[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]).sort();
  assert.deepEqual([...core.data.focusTrapElements].sort(), focusElements);
});

test('schema reflects generated-binding and focused transition contracts', () => {
  assert.ok(core.data.elementAttributes.Bindings.includes('output'));
  assert.ok(core.data.generatedBindingAttributes.includes('format-text'));
  assert.ok(core.data.generatedBindingAttributes.includes('parse-text'));
  assert.ok(core.data.generatedBindingAttributes.includes('format-min'));
  assert.ok(core.data.generatedBindingAttributes.includes('format-max'));
  assert.ok(!core.data.generatedBindingAttributes.includes('parse-min'));
  assert.ok(!core.data.generatedBindingAttributes.includes('parse-max'));
  assert.ok(core.data.elementAttributes.Option.includes('id'));
  assert.ok(core.data.elementAttributes.Option.includes('class'));
  assert.deepEqual(core.parseGxml('<Select><Option id="high" class="premium">High</Option></Select>').diagnostics, []);
  assert.ok(core.parseGxml('<Select><Option visible="false">Hidden</Option></Select>').diagnostics.some((item) => item.code === 'gxml.unknown-attribute'));
  assert.ok(core.gxmlAttributeNames('Option').includes('id'));
  assert.ok(core.gxmlAttributeNames('Option').includes('class'));
  assert.ok(!core.gxmlAttributeNames('Option').includes('visible'));
  assert.ok(!core.data.elementAttributes.Binding.includes('format'));
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
