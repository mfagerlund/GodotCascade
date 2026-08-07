'use strict';

const data = require('./language-data.json');

const BUILTIN_ELEMENTS = new Set(Object.keys(data.elements));
const KNOWN_PROPERTIES = new Set(Object.keys(data.properties));
const KNOWN_PSEUDOS = new Set(Object.keys(data.pseudoStates));

function diagnostic(start, end, message, severity = 'error', code = '') {
  return { start, end: Math.max(end, start + 1), message, severity, code };
}

function scanGxml(text) {
  const tags = [];
  const diagnostics = [];
  let index = 0;
  while (index < text.length) {
    const open = text.indexOf('<', index);
    if (open < 0) break;
    if (text.startsWith('<!--', open)) {
      const close = text.indexOf('-->', open + 4);
      if (close < 0) {
        diagnostics.push(diagnostic(open, text.length, 'Unclosed GXML comment.', 'error', 'gxml.unclosed-comment'));
        break;
      }
      index = close + 3;
      continue;
    }
    if (text.startsWith('<![CDATA[', open)) {
      const close = text.indexOf(']]>', open + 9);
      if (close < 0) {
        diagnostics.push(diagnostic(open, text.length, 'Unclosed CDATA section.', 'error', 'gxml.unclosed-cdata'));
        break;
      }
      index = close + 3;
      continue;
    }
    if (text.startsWith('<?', open) || text.startsWith('<!', open)) {
      const close = text.indexOf('>', open + 2);
      if (close < 0) {
        diagnostics.push(diagnostic(open, text.length, 'Unclosed GXML declaration.', 'error', 'gxml.unclosed-declaration'));
        break;
      }
      index = close + 1;
      continue;
    }
    let cursor = open + 1;
    let closing = false;
    if (text[cursor] === '/') { closing = true; cursor++; }
    while (/\s/.test(text[cursor] || '')) cursor++;
    const nameStart = cursor;
    while (/[A-Za-z0-9_.:-]/.test(text[cursor] || '')) cursor++;
    const name = text.slice(nameStart, cursor);
    if (!name) {
      diagnostics.push(diagnostic(open, open + 1, 'Expected an element name after <.', 'error', 'gxml.missing-name'));
      index = open + 1;
      continue;
    }
    const attrs = [];
    let quote = '';
    let tagEnd = -1;
    while (cursor < text.length) {
      const ch = text[cursor];
      if (quote) {
        if (ch === quote) quote = '';
        cursor++;
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; cursor++; continue; }
      if (ch === '>') { tagEnd = cursor + 1; break; }
      cursor++;
    }
    if (tagEnd < 0) {
      diagnostics.push(diagnostic(open, text.length, `Unclosed <${name}> tag.`, 'error', 'gxml.unclosed-tag'));
      break;
    }
    const rawEnd = text.slice(open, tagEnd);
    const selfClosing = /\/\s*>$/.test(rawEnd);
    if (!closing) {
      const attrEnd = tagEnd - (selfClosing ? 2 : 1);
      let p = nameStart + name.length;
      while (p < attrEnd) {
        while (/\s/.test(text[p] || '')) p++;
        if (p >= attrEnd) break;
        const attrNameStart = p;
        while (/[^\s=/>]/.test(text[p] || '')) p++;
        const attrName = text.slice(attrNameStart, p);
        if (!attrName) { p++; continue; }
        while (/\s/.test(text[p] || '')) p++;
        let value = '';
        let valueStart = p;
        let valueEnd = p;
        if (text[p] === '=') {
          p++;
          while (/\s/.test(text[p] || '')) p++;
          if (text[p] === '"' || text[p] === "'") {
            const attrQuote = text[p++];
            valueStart = p;
            const closeQuote = text.indexOf(attrQuote, p);
            if (closeQuote < 0 || closeQuote > attrEnd) {
              diagnostics.push(diagnostic(attrNameStart, p, `Unclosed value for attribute '${attrName}'.`, 'error', 'gxml.unclosed-attribute'));
              value = text.slice(p, attrEnd);
              valueEnd = attrEnd;
              p = attrEnd;
            } else {
              value = text.slice(p, closeQuote);
              valueEnd = closeQuote;
              p = closeQuote + 1;
            }
          } else {
            valueStart = p;
            while (/[^\s/>]/.test(text[p] || '')) p++;
            valueEnd = p;
            value = text.slice(valueStart, valueEnd);
            diagnostics.push(diagnostic(valueStart, valueEnd, `Attribute '${attrName}' should use a quoted XML value.`, 'warning', 'gxml.unquoted-attribute'));
          }
        }
        attrs.push({ name: attrName, nameStart: attrNameStart, nameEnd: attrNameStart + attrName.length, value, valueStart, valueEnd });
      }
    }
    tags.push({ name, nameStart, nameEnd: nameStart + name.length, start: open, end: tagEnd, closing, selfClosing, attrs });
    index = tagEnd;
  }
  return { tags, diagnostics };
}

function attribute(tag, name) {
  return tag.attrs.find((item) => item.name === name);
}

function parseGxml(text) {
  const scanned = scanGxml(text);
  const diagnostics = [...scanned.diagnostics];
  const roots = [];
  const stack = [];
  const nodes = [];
  const components = new Map();

  for (const tag of scanned.tags) {
    if (tag.closing) {
      if (!stack.length) {
        diagnostics.push(diagnostic(tag.start, tag.end, `Unexpected closing tag </${tag.name}>.`, 'error', 'gxml.unexpected-close'));
      } else if (stack[stack.length - 1].tag.name !== tag.name) {
        const expected = stack[stack.length - 1].tag.name;
        diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, `Expected </${expected}> before </${tag.name}>.`, 'error', 'gxml.mismatched-close'));
        const match = stack.map((node) => node.tag.name).lastIndexOf(tag.name);
        if (match >= 0) stack.length = match;
      } else {
        stack.pop();
      }
      continue;
    }
    const node = { tag, children: [], parent: stack.length ? stack[stack.length - 1] : null };
    if (node.parent) node.parent.children.push(node); else roots.push(node);
    nodes.push(node);
    if (tag.name === 'Component') {
      const name = attribute(tag, 'name');
      if (name && name.value) components.set(name.value, name);
    }
    const seenAttributes = new Set();
    for (const attr of tag.attrs) {
      if (seenAttributes.has(attr.name)) diagnostics.push(diagnostic(attr.nameStart, attr.nameEnd, `Duplicate attribute '${attr.name}'.`, 'error', 'gxml.duplicate-attribute'));
      seenAttributes.add(attr.name);
      if (data.booleanAttributes.includes(attr.name) && attr.value && !attr.value.startsWith('{') && !attr.value.startsWith('@') && !['true', 'false', '1', '0', 'yes', 'no', 'on', 'off', attr.name].includes(attr.value.toLowerCase())) {
        diagnostics.push(diagnostic(attr.valueStart, attr.valueEnd, `Attribute '${attr.name}' requires a boolean literal or exact binding.`, 'error', 'gxml.invalid-boolean'));
      }
    }
    if (!tag.selfClosing) stack.push(node);
  }
  for (const node of stack) diagnostics.push(diagnostic(node.tag.nameStart, node.tag.nameEnd, `Element <${node.tag.name}> is not closed.`, 'error', 'gxml.unclosed-element'));
  if (roots.length === 0 && text.trim()) diagnostics.push(diagnostic(0, Math.min(1, text.length), 'GXML document contains no root element.', 'error', 'gxml.no-root'));
  if (roots.length > 1) {
    for (const root of roots.slice(1)) diagnostics.push(diagnostic(root.tag.start, root.tag.end, 'GXML documents must contain exactly one root element.', 'error', 'gxml.multiple-roots'));
  }

  for (const node of nodes) {
    const tag = node.tag;
    if (tag.name === 'Repeat') {
      const items = attribute(tag, 'items');
      if (!items || !/^\{[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*|\.\d+)*\}$/.test(items.value)) {
        diagnostics.push(diagnostic(items ? items.valueStart : tag.nameStart, items ? items.valueEnd : tag.nameEnd, "Repeat 'items' must be an exact binding such as '{inventory.items}'.", 'error', 'gxml.repeat-items'));
      }
      if (node.children.length !== 1) diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, 'Repeat requires exactly one child template.', 'error', 'gxml.repeat-child'));
    }
    if (tag.name === 'Select') {
      for (const child of node.children) if (child.tag.name !== 'Option') diagnostics.push(diagnostic(child.tag.nameStart, child.tag.nameEnd, 'Select only accepts <Option> children.', 'error', 'gxml.select-child'));
    }
    if (tag.name === 'Param' && attribute(tag, 'required') && attribute(tag, 'default')) {
      diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, "Param 'required' and 'default' are mutually exclusive.", 'error', 'gxml.param-default'));
    }
  }
  return { tags: scanned.tags, nodes, roots, components, diagnostics };
}

function maskComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, (match) => match.replace(/[^\r\n]/g, ' '));
}

function splitTopLevel(text, start, end, separator) {
  const ranges = [];
  let segmentStart = start;
  let quote = '';
  let parens = 0;
  for (let i = start; i < end; i++) {
    const ch = text[i];
    if (quote) {
      if (ch === '\\') i++;
      else if (ch === quote) quote = '';
      continue;
    }
    if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '(') parens++;
    else if (ch === ')') parens--;
    else if (ch === separator && parens === 0) { ranges.push([segmentStart, i]); segmentStart = i + 1; }
  }
  ranges.push([segmentStart, end]);
  return ranges;
}

function trimRange(text, start, end) {
  while (start < end && /\s/.test(text[start])) start++;
  while (end > start && /\s/.test(text[end - 1])) end--;
  return [start, end];
}

function parseDeclarations(text, start, end, diagnostics) {
  const declarations = [];
  for (const rawRange of splitTopLevel(text, start, end, ';')) {
    const [partStart, partEnd] = trimRange(text, rawRange[0], rawRange[1]);
    if (partStart >= partEnd) continue;
    const colons = splitTopLevel(text, partStart, partEnd, ':');
    if (colons.length < 2) {
      diagnostics.push(diagnostic(partStart, partEnd, 'Expected : after the GCSS property name.', 'error', 'gcss.missing-colon'));
      continue;
    }
    const [nameStart, nameEnd] = trimRange(text, colons[0][0], colons[0][1]);
    const [valueStart, valueEnd] = trimRange(text, colons[1][0], partEnd);
    const name = text.slice(nameStart, nameEnd);
    const value = text.slice(valueStart, valueEnd);
    declarations.push({ name, nameStart, nameEnd, value, valueStart, valueEnd });
    if (!name.startsWith('--') && !KNOWN_PROPERTIES.has(name.toLowerCase())) diagnostics.push(diagnostic(nameStart, nameEnd, `Unsupported GCSS property '${name}'.`, 'warning', 'gcss.unknown-property'));
    if (!value) diagnostics.push(diagnostic(nameStart, nameEnd, `Property '${name}' has no value.`, 'error', 'gcss.missing-value'));
    if (name.startsWith('--') && !/^--[A-Za-z_][A-Za-z0-9_-]*$/.test(name)) diagnostics.push(diagnostic(nameStart, nameEnd, `Invalid custom-property name '${name}'.`, 'error', 'gcss.invalid-custom-property'));
  }
  return declarations;
}

function parseGcss(text) {
  const masked = maskComments(text);
  const diagnostics = [];
  const rules = [];
  const stack = [];
  let quote = '';
  let parens = 0;
  for (let i = 0; i < masked.length; i++) {
    const ch = masked[i];
    if (quote) {
      if (ch === '\\') i++;
      else if (ch === quote) quote = '';
      continue;
    }
    if (ch === '"' || ch === "'") { quote = ch; continue; }
    if (ch === '(') { parens++; continue; }
    if (ch === ')') { parens = Math.max(0, parens - 1); continue; }
    if (parens) continue;
    if (ch === '{') {
      let headerStart = i - 1;
      while (headerStart >= 0 && !'{};'.includes(masked[headerStart])) headerStart--;
      headerStart++;
      const range = trimRange(text, headerStart, i);
      const header = text.slice(range[0], range[1]);
      const mediaInvalid = header.startsWith('@media') && !/^@media\s*\(\s*(?:min|max)-width\s*:\s*(?:\d+(?:\.\d+)?)px\s*\)$/.test(header);
      if (mediaInvalid) diagnostics.push(diagnostic(range[0], range[1], 'Only @media (min-width: <px>) and @media (max-width: <px>) are supported.', 'warning', 'gcss.unsupported-media'));
      stack.push({ header, headerStart: range[0], headerEnd: range[1], bodyStart: i + 1, depth: stack.length, mediaInvalid });
    } else if (ch === '}') {
      if (!stack.length) {
        diagnostics.push(diagnostic(i, i + 1, 'Unexpected } in GCSS.', 'error', 'gcss.unexpected-close'));
        continue;
      }
      const block = stack.pop();
      if (!block.header.startsWith('@media')) {
        block.bodyEnd = i;
        block.end = i + 1;
        block.declarations = parseDeclarations(text, block.bodyStart, i, diagnostics);
        rules.push(block);
        const pseudoRegex = /:([A-Za-z-]+)/g;
        let match;
        while ((match = pseudoRegex.exec(block.header))) {
          if (!KNOWN_PSEUDOS.has(match[1])) diagnostics.push(diagnostic(block.headerStart + match.index + 1, block.headerStart + match.index + match[0].length, `Unsupported pseudo state :${match[1]}.`, 'warning', 'gcss.unknown-pseudo'));
        }
      }
    }
  }
  for (const block of stack) diagnostics.push(diagnostic(block.headerStart, block.headerEnd, `Unclosed GCSS block '${block.header}'.`, 'error', 'gcss.unclosed-block'));
  return { rules, diagnostics };
}

function collectSymbols(text, language) {
  const symbols = [];
  if (language === 'gxml') {
    const parsed = parseGxml(text);
    for (const tag of parsed.tags) {
      symbols.push({ kind: 'tag', name: tag.name, start: tag.nameStart, end: tag.nameEnd, definition: false });
      for (const attr of tag.attrs) {
        if (attr.name === 'id' && attr.value) symbols.push({ kind: 'id', name: attr.value, start: attr.valueStart, end: attr.valueEnd, definition: true });
        if (attr.name === 'class') {
          const re = /[A-Za-z_][\w-]*/g; let match;
          while ((match = re.exec(attr.value))) symbols.push({ kind: 'class', name: match[0], start: attr.valueStart + match.index, end: attr.valueStart + match.index + match[0].length, definition: true });
        }
        if (tag.name === 'Component' && attr.name === 'name' && attr.value) symbols.push({ kind: 'component', name: attr.value, start: attr.valueStart, end: attr.valueEnd, definition: true });
      }
    }
    const componentNames = new Set(symbols.filter((s) => s.kind === 'component').map((s) => s.name));
    for (const symbol of symbols) if (symbol.kind === 'tag' && componentNames.has(symbol.name)) symbol.kind = 'component';
  } else if (language === 'gcss') {
    const parsed = parseGcss(text);
    for (const rule of parsed.rules) {
      const re = /([.#])([A-Za-z_][\w-]*)/g; let match;
      while ((match = re.exec(rule.header))) symbols.push({ kind: match[1] === '.' ? 'class' : 'id', name: match[2], start: rule.headerStart + match.index + 1, end: rule.headerStart + match.index + match[0].length, definition: false });
      for (const declaration of rule.declarations) {
        if (declaration.name.startsWith('--')) symbols.push({ kind: 'custom-property', name: declaration.name, start: declaration.nameStart, end: declaration.nameEnd, definition: true });
        const varRegex = /var\(\s*(--[A-Za-z_][A-Za-z0-9_-]*)/g; let varMatch;
        while ((varMatch = varRegex.exec(declaration.value))) {
          const relative = varMatch.index + varMatch[0].lastIndexOf(varMatch[1]);
          symbols.push({ kind: 'custom-property', name: varMatch[1], start: declaration.valueStart + relative, end: declaration.valueStart + relative + varMatch[1].length, definition: false });
        }
      }
    }
  }
  return symbols;
}

function symbolAt(text, language, offset) {
  return collectSymbols(text, language).find((symbol) => offset >= symbol.start && offset <= symbol.end) || null;
}

function gxmlCompletionContext(text, offset) {
  const before = text.slice(0, offset);
  const open = before.lastIndexOf('<');
  const close = before.lastIndexOf('>');
  if (open <= close) return null;
  const fragment = before.slice(open + 1);
  if (/^\s*\//.test(fragment)) return { kind: 'closing-tag', prefix: fragment.replace(/^\s*\//, '').trim() };
  if (/^\s*[A-Za-z0-9_.:-]*$/.test(fragment)) return { kind: 'tag', prefix: fragment.trim() };
  const nameMatch = fragment.match(/^\s*([A-Za-z0-9_.:-]+)/);
  if (!nameMatch) return { kind: 'tag', prefix: '' };
  const quoteMatch = fragment.match(/([A-Za-z_][\w-]*)\s*=\s*(["'])([^"']*)$/);
  if (quoteMatch) return { kind: 'attribute-value', tag: nameMatch[1], attribute: quoteMatch[1], prefix: quoteMatch[3] };
  const prefixMatch = fragment.match(/(?:^|\s)([A-Za-z_][\w-]*)$/);
  return { kind: 'attribute', tag: nameMatch[1], prefix: prefixMatch ? prefixMatch[1] : '' };
}

function gcssCompletionContext(text, offset) {
  const before = maskComments(text.slice(0, offset));
  let depth = 0; let lastOpen = -1;
  for (let i = 0; i < before.length; i++) {
    if (before[i] === '{') { depth++; lastOpen = i; }
    else if (before[i] === '}') depth = Math.max(0, depth - 1);
  }
  if (!depth) return { kind: 'selector', prefix: (before.match(/[.#:@A-Za-z_-][\w-]*$/) || [''])[0] };
  const segmentStart = Math.max(lastOpen, before.lastIndexOf(';')) + 1;
  const segment = before.slice(segmentStart);
  const colon = segment.indexOf(':');
  if (colon < 0) return { kind: 'property', prefix: segment.trim() };
  return { kind: 'value', property: segment.slice(0, colon).trim().toLowerCase(), prefix: segment.slice(colon + 1).trim() };
}

function formatGxml(text, options = {}) {
  if (text.includes('<![CDATA[')) return text;
  const unit = options.insertSpaces === false ? '\t' : ' '.repeat(options.tabSize || 4);
  let depth = 0;
  const lines = [];
  for (const original of text.replace(/\r\n/g, '\n').split('\n')) {
    const trimmed = original.trim();
    if (!trimmed) { if (lines.length && lines[lines.length - 1] !== '') lines.push(''); continue; }
    if (/^<\//.test(trimmed)) depth = Math.max(0, depth - 1);
    lines.push(unit.repeat(depth) + trimmed.replace(/\s+\/>$/, ' />'));
    const opening = (trimmed.match(/<(?!\/|!|\?)[A-Za-z][^>]*>/g) || []).filter((tag) => !/\/\s*>$/.test(tag)).length;
    const closing = (trimmed.match(/<\/[A-Za-z][^>]*>/g) || []).length;
    depth = Math.max(0, depth + opening - closing - (/^<\//.test(trimmed) ? -1 : 0));
  }
  while (lines.length && lines[lines.length - 1] === '') lines.pop();
  return lines.join('\n') + '\n';
}

function formatGcss(text, options = {}) {
  const unit = options.insertSpaces === false ? '\t' : ' '.repeat(options.tabSize || 4);
  let output = '';
  let token = '';
  let depth = 0;
  let quote = '';
  let parens = 0;
  let comment = false;
  const blockKinds = [];
  const flush = () => { const value = token.trim(); if (value) output += unit.repeat(depth) + value; token = ''; };
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]; const next = text[i + 1];
    if (comment) {
      token += ch;
      if (ch === '*' && next === '/') { token += '/'; i++; comment = false; }
      continue;
    }
    if (!quote && ch === '/' && next === '*') { if (token.trim()) flush(); token = '/*'; i++; comment = true; continue; }
    if (quote) { token += ch; if (ch === '\\') token += text[++i] || ''; else if (ch === quote) quote = ''; continue; }
    if (ch === '"' || ch === "'") { quote = ch; token += ch; continue; }
    if (ch === '(') { parens++; token += ch; continue; }
    if (ch === ')') { parens--; token += ch; continue; }
    if (parens) { token += ch; continue; }
    if (ch === '{') {
      const header = token.trim();
      flush();
      output = output.trimEnd() + ' {\n';
      blockKinds.push(header.startsWith('@media') ? 'media' : 'rule');
      depth++;
    }
    else if (ch === '}') { flush(); if (!output.endsWith('\n')) output += '\n'; depth = Math.max(0, depth - 1); blockKinds.pop(); output += unit.repeat(depth) + '}\n'; }
    else if (ch === ';') { flush(); output = output.trimEnd() + ';\n'; }
    else if (ch === ':') { token = token.trimEnd() + (blockKinds[blockKinds.length - 1] === 'rule' ? ': ' : ':'); }
    else if (/\s/.test(ch)) { if (token && !token.endsWith(' ')) token += ' '; }
    else token += ch;
  }
  flush();
  return output.replace(/\n{3,}/g, '\n\n').trimEnd() + '\n';
}

module.exports = {
  data,
  scanGxml,
  parseGxml,
  parseGcss,
  collectSymbols,
  symbolAt,
  gxmlCompletionContext,
  gcssCompletionContext,
  formatGxml,
  formatGcss
};
