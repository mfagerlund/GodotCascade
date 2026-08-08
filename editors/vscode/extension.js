'use strict';

const vscode = require('vscode');
const core = require('./core');
const providerCore = require('./provider-core');

const SELECTOR = [{ language: 'gxml', scheme: 'file' }, { language: 'gcss', scheme: 'file' }, { language: 'gxml', scheme: 'untitled' }, { language: 'gcss', scheme: 'untitled' }];

function languageOf(document) {
  return document.languageId === 'gxml' || document.fileName.endsWith('.gxml') ? 'gxml' : 'gcss';
}

function range(document, start, end) {
  return new vscode.Range(document.positionAt(start), document.positionAt(end));
}

function markdown(title, body) {
  const value = new vscode.MarkdownString();
  value.appendMarkdown(`**${title}**\n\n${body}`);
  return value;
}

function completion(label, detail, kind = vscode.CompletionItemKind.Property, insertText = null) {
  const item = new vscode.CompletionItem(label, kind);
  item.detail = detail;
  if (insertText) item.insertText = new vscode.SnippetString(insertText);
  return item;
}

async function workspaceSources() {
  const uris = await vscode.workspace.findFiles('**/*.{gxml,gcss}', '**/{.git,.godot,node_modules,dist,build}/**');
  const openDocuments = new Map(vscode.workspace.textDocuments.filter((document) => document.uri.scheme === 'file').map((document) => [document.uri.toString(), document]));
  return Promise.all(uris.map(async (uri) => {
    try {
      const openDocument = openDocuments.get(uri.toString());
      const text = openDocument ? openDocument.getText() : Buffer.from(await vscode.workspace.fs.readFile(uri)).toString('utf8');
      return { uri, text, language: uri.path.toLowerCase().endsWith('.gxml') ? 'gxml' : 'gcss', symbols: core.collectSymbols(text, uri.path.toLowerCase().endsWith('.gxml') ? 'gxml' : 'gcss') };
    } catch (_) {
      return null;
    }
  })).then((items) => items.filter(Boolean));
}

function documentSymbols(document) {
  return core.collectSymbols(document.getText(), languageOf(document));
}

function currentSymbol(document, position) {
  return core.symbolAt(document.getText(), languageOf(document), document.offsetAt(position));
}

async function vocabulary() {
  const sources = await workspaceSources();
  const values = { classes: new Set(), ids: new Set(), components: new Set(), customProperties: new Set() };
  for (const source of sources) for (const symbol of source.symbols) {
    if (symbol.kind === 'class') values.classes.add(symbol.name);
    if (symbol.kind === 'id') values.ids.add(symbol.name);
    if (symbol.kind === 'component' && symbol.definition) values.components.add(symbol.name);
    if (symbol.kind === 'custom-property') values.customProperties.add(symbol.name);
  }
  return values;
}

function provideGxmlCompletions(document, position) {
  const context = core.gxmlCompletionContext(document.getText(), document.offsetAt(position));
  if (!context) return [];
  if (context.kind === 'tag') {
    const localComponents = [...core.parseGxml(document.getText()).components.keys()];
    return [...Object.keys(core.data.elements), ...localComponents].map((name) => completion(name, core.data.elements[name] || 'Reusable GXML component.', vscode.CompletionItemKind.Class));
  }
  if (context.kind === 'closing-tag') {
    const parsed = core.scanGxml(document.getText().slice(0, document.offsetAt(position)));
    const stack = [];
    for (const tag of parsed.tags) {
      if (tag.closing) { if (stack[stack.length - 1] === tag.name) stack.pop(); }
      else if (!tag.selfClosing) stack.push(tag.name);
    }
    return [...stack].reverse().map((name) => completion(name, `Close <${name}>.`, vscode.CompletionItemKind.Class));
  }
  if (context.kind === 'attribute') {
    return core.gxmlAttributeNames(context.tag).map((name) => completion(name, core.data.attributes[name] || 'GXML attribute.', vscode.CompletionItemKind.Property, `${name}="$1"`));
  }
  if (context.kind === 'attribute-value' && core.data.booleanAttributes.includes(context.attribute)) {
    return ['true', 'false'].map((value) => completion(value, `Boolean ${value}.`, vscode.CompletionItemKind.Value));
  }
  if (context.kind === 'attribute-value' && context.attribute === 'type') {
    return ['String', 'bool', 'int', 'float', 'Variant'].map((value) => completion(value, 'Supported GXML parameter type.', vscode.CompletionItemKind.Value));
  }
  return [];
}

async function provideGcssCompletions(document, position) {
  const context = core.gcssCompletionContext(document.getText(), document.offsetAt(position));
  if (!context) return [];
  if (context.kind === 'property') {
    const items = Object.entries(core.data.properties).map(([name, entry]) => completion(name, entry.description, vscode.CompletionItemKind.Property, `${name}: ${entry.snippet || (entry.values && entry.values[0]) || '$1'};`));
    items.unshift(completion('--custom-property', 'Declares a case-sensitive inherited GCSS custom property.', vscode.CompletionItemKind.Variable, '--${1:name}: $2;'));
    return items;
  }
  if (context.kind === 'value') {
    const entry = core.data.properties[context.property];
    const items = entry && entry.values ? entry.values.map((value) => completion(value, entry.description, vscode.CompletionItemKind.Value)) : [];
    const vars = await vocabulary();
    for (const name of vars.customProperties) items.push(completion(`var(${name})`, 'Resolve a GCSS custom property.', vscode.CompletionItemKind.Variable));
    items.push(completion('calc()', 'Focused typed NUMBER, LENGTH, or TIME arithmetic.', vscode.CompletionItemKind.Function, 'calc(${1:expression})'));
    return items;
  }
  const words = await vocabulary();
  const items = Object.keys(core.data.elements).map((name) => completion(name, core.data.elements[name], vscode.CompletionItemKind.Class));
  for (const name of words.components) items.push(completion(name, 'Reusable GXML component selector.', vscode.CompletionItemKind.Class));
  for (const name of words.classes) items.push(completion(`.${name}`, 'Class declared in GXML.', vscode.CompletionItemKind.Reference));
  for (const name of words.ids) items.push(completion(`#${name}`, 'ID declared in GXML.', vscode.CompletionItemKind.Reference));
  for (const [name, description] of Object.entries(core.data.pseudoStates)) items.push(completion(`:${name}`, description, vscode.CompletionItemKind.EnumMember));
  items.push(completion('@media', 'Focused min-width/max-width pixel viewport query.', vscode.CompletionItemKind.Keyword, '@media (${1:min-width}: ${2:800px}) {\n\t$0\n}'));
  return items;
}

function provideHover(document, position) {
  const text = document.getText();
  const offset = document.offsetAt(position);
  const language = languageOf(document);
  const symbol = core.symbolAt(text, language, offset);
  if (symbol) {
    if (symbol.kind === 'class') return new vscode.Hover(markdown(`.${symbol.name}`, 'GCSS class selector shared with GXML `class` values.'), range(document, symbol.start, symbol.end));
    if (symbol.kind === 'id') return new vscode.Hover(markdown(`#${symbol.name}`, 'Stable GXML identity and GCSS ID selector.'), range(document, symbol.start, symbol.end));
    if (symbol.kind === 'custom-property') return new vscode.Hover(markdown(symbol.name, 'Case-sensitive, inherited GCSS custom property resolved with `var()`.'), range(document, symbol.start, symbol.end));
    if (symbol.kind === 'component') return new vscode.Hover(markdown(symbol.name, 'Reusable source-level GXML component.'), range(document, symbol.start, symbol.end));
    if (symbol.kind === 'tag') {
      const canonical = core.canonicalElementName(symbol.name);
      if (canonical) return new vscode.Hover(markdown(`<${canonical}>`, core.data.elements[canonical]), range(document, symbol.start, symbol.end));
    }
  }
  if (language === 'gxml') {
    const parsed = core.scanGxml(text);
    for (const tag of parsed.tags) for (const attr of tag.attrs) if (offset >= attr.nameStart && offset <= attr.nameEnd && core.data.attributes[attr.name]) return new vscode.Hover(markdown(attr.name, core.data.attributes[attr.name]), range(document, attr.nameStart, attr.nameEnd));
  } else {
    const parsed = core.parseGcss(text);
    for (const rule of parsed.rules) {
      for (const declaration of rule.declarations) if (offset >= declaration.nameStart && offset <= declaration.nameEnd) {
        const entry = core.data.properties[declaration.name.toLowerCase()];
        if (entry) return new vscode.Hover(markdown(declaration.name, entry.description), range(document, declaration.nameStart, declaration.nameEnd));
      }
      if (offset >= rule.headerStart && offset <= rule.headerEnd) {
        const relative = offset - rule.headerStart;
        const match = [...rule.header.matchAll(/:([A-Za-z-]+)/g)].find((item) => relative >= item.index + 1 && relative <= item.index + item[0].length);
        if (match && core.data.pseudoStates[match[1]]) return new vscode.Hover(markdown(`:${match[1]}`, core.data.pseudoStates[match[1]]));
      }
    }
  }
  return null;
}

async function provideDefinition(document, position) {
  const target = currentSymbol(document, position);
  if (!target || (target.kind === 'tag' && core.isBuiltinElement(target.name))) return null;
  const locations = [];
  if (target.kind === 'component' || (target.kind === 'tag' && !core.isBuiltinElement(target.name))) {
    for (const candidate of documentSymbols(document)) {
      if (providerCore.definitionMatches(target, candidate)) locations.push(new vscode.Location(document.uri, range(document, candidate.start, candidate.end)));
    }
    return locations;
  }
  for (const source of await workspaceSources()) for (const candidate of source.symbols) {
    if (providerCore.definitionMatches(target, candidate)) locations.push(new vscode.Location(source.uri, new vscode.Range(positionFromOffset(source.text, candidate.start), positionFromOffset(source.text, candidate.end))));
  }
  return locations;
}

function positionFromOffset(text, offset) {
  const prefix = text.slice(0, offset);
  const lines = prefix.split(/\r?\n/);
  return new vscode.Position(lines.length - 1, lines[lines.length - 1].length);
}

async function provideRenameEdits(document, position, newName) {
  const target = currentSymbol(document, position);
  if (!target) throw new Error('Rename is available for GXML classes, IDs, reusable components, and GCSS custom properties.');
  if (!providerCore.isRenameableTarget(target)) throw new Error('Built-in GXML elements and reserved component names cannot be renamed.');
  const bareName = target.kind === 'custom-property' ? /^--[A-Za-z_][A-Za-z0-9_-]*$/ : /^[A-Za-z_][A-Za-z0-9_-]*$/;
  if (!bareName.test(newName)) throw new Error(`'${newName}' is not a valid ${target.kind} name.`);
  if (providerCore.isReusableComponentTarget(target) && core.isBuiltinElement(newName)) throw new Error(`'${newName}' is reserved for a built-in GXML element.`);
  const edit = new vscode.WorkspaceEdit();
  const documentSource = { uri: document.uri, text: document.getText(), language: languageOf(document), symbols: documentSymbols(document) };
  const workspace = providerCore.renameScope(target) === 'workspace' ? await workspaceSources() : [];
  const sources = providerCore.selectRenameSources(target, documentSource, workspace);
  for (const source of sources) for (const candidate of source.symbols) {
    if (providerCore.renameMatches(target, candidate)) {
      edit.replace(source.uri, new vscode.Range(positionFromOffset(source.text, candidate.start), positionFromOffset(source.text, candidate.end)), newName);
    }
  }
  return edit;
}

function prepareRename(document, position) {
  const target = currentSymbol(document, position);
  if (!providerCore.isRenameableTarget(target)) return null;
  return { range: range(document, target.start, target.end), placeholder: target.name };
}

function updateDiagnostics(collection, document) {
  if (!SELECTOR.some((entry) => entry.language === document.languageId)) return;
  if (!vscode.workspace.getConfiguration('godotCascade', document.uri).get('diagnostics.enabled', true)) {
    collection.delete(document.uri);
    return;
  }
  const result = languageOf(document) === 'gxml' ? core.parseGxml(document.getText()) : core.parseGcss(document.getText());
  const items = result.diagnostics.map((entry) => {
    const item = new vscode.Diagnostic(range(document, entry.start, entry.end), entry.message, entry.severity === 'warning' ? vscode.DiagnosticSeverity.Warning : vscode.DiagnosticSeverity.Error);
    item.source = 'GodotCascade';
    item.code = entry.code;
    return item;
  });
  collection.set(document.uri, items);
}

function activate(context) {
  const diagnostics = vscode.languages.createDiagnosticCollection('godotCascade');
  context.subscriptions.push(diagnostics);
  for (const document of vscode.workspace.textDocuments) updateDiagnostics(diagnostics, document);
  context.subscriptions.push(vscode.workspace.onDidOpenTextDocument((document) => updateDiagnostics(diagnostics, document)));
  context.subscriptions.push(vscode.workspace.onDidChangeTextDocument((event) => updateDiagnostics(diagnostics, event.document)));
  context.subscriptions.push(vscode.workspace.onDidCloseTextDocument((document) => diagnostics.delete(document.uri)));
  context.subscriptions.push(vscode.workspace.onDidChangeConfiguration((event) => { if (event.affectsConfiguration('godotCascade.diagnostics.enabled')) for (const document of vscode.workspace.textDocuments) updateDiagnostics(diagnostics, document); }));

  context.subscriptions.push(vscode.languages.registerCompletionItemProvider({ language: 'gxml' }, { provideCompletionItems: provideGxmlCompletions }, '<', ' ', '"', "'"));
  context.subscriptions.push(vscode.languages.registerCompletionItemProvider({ language: 'gcss' }, { provideCompletionItems: provideGcssCompletions }, '.', '#', ':', '-', '@'));
  context.subscriptions.push(vscode.languages.registerHoverProvider(SELECTOR, { provideHover }));
  context.subscriptions.push(vscode.languages.registerDefinitionProvider(SELECTOR, { provideDefinition }));
  context.subscriptions.push(vscode.languages.registerRenameProvider(SELECTOR, { provideRenameEdits, prepareRename }));
  context.subscriptions.push(vscode.languages.registerDocumentFormattingEditProvider({ language: 'gxml' }, { provideDocumentFormattingEdits(document, options) { return [vscode.TextEdit.replace(new vscode.Range(document.positionAt(0), document.positionAt(document.getText().length)), core.formatGxml(document.getText(), options))]; } }));
  context.subscriptions.push(vscode.languages.registerDocumentFormattingEditProvider({ language: 'gcss' }, { provideDocumentFormattingEdits(document, options) { return [vscode.TextEdit.replace(new vscode.Range(document.positionAt(0), document.positionAt(document.getText().length)), core.formatGcss(document.getText(), options))]; } }));
  context.subscriptions.push(vscode.commands.registerCommand('godotCascade.validateWorkspace', () => {
    let count = 0;
    for (const document of vscode.workspace.textDocuments) {
      if (document.languageId === 'gxml' || document.languageId === 'gcss') { updateDiagnostics(diagnostics, document); count++; }
    }
    vscode.window.showInformationMessage(`GodotCascade validated ${count} open source file${count === 1 ? '' : 's'}.`);
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
