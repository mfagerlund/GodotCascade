'use strict';

const data = require('./language-data.json');

const ELEMENT_ALIASES = new Map([['input', 'TextInput'], ['radio', 'RadioButton']]);
const BUILTIN_ELEMENTS = new Set([...Object.keys(data.elements).map((name) => name.toLowerCase()), ...ELEMENT_ALIASES.keys()]);
const FOCUS_TRAP_ELEMENTS = new Set((data.focusTrapElements || []).map((name) => name.toLowerCase()));
const KNOWN_PROPERTIES = new Set(Object.keys(data.properties));
const KNOWN_PSEUDOS = new Set(Object.keys(data.pseudoStates));

function isBuiltinElement(name) {
  return BUILTIN_ELEMENTS.has(String(name).toLowerCase());
}

function canonicalElementName(name) {
  const normalized = String(name).toLowerCase();
  if (ELEMENT_ALIASES.has(normalized)) return ELEMENT_ALIASES.get(normalized);
  return Object.keys(data.elements).find((candidate) => candidate.toLowerCase() === normalized) || '';
}

function sameElementName(left, right) {
  return String(left).toLowerCase() === String(right).toLowerCase();
}

function isAllowedAttribute(tagName, attributeName) {
  const normalized = String(attributeName).toLowerCase();
  if (String(attributeName) !== normalized) return false;
  const canonical = canonicalElementName(tagName);
  if (!canonical) return true;
  if (normalized.startsWith('__')) return false;
  if (!data.nonVisualElements.includes(canonical) && (/^(?:on|bind)-/.test(normalized) || data.generatedBindingAttributes.includes(normalized))) return true;
  const common = data.nonVisualElements.includes(canonical) ? [] : (data.elementAttributes['*'] || []);
  return [...common, ...(data.elementAttributes[canonical] || [])].includes(normalized);
}

function gxmlAttributeNames(tagName) {
  const canonical = canonicalElementName(tagName);
  if (!canonical) return [...(data.elementAttributes['*'] || [])];
  const nonVisual = data.nonVisualElements.includes(canonical);
  const names = [...new Set([
    ...(nonVisual ? [] : (data.elementAttributes['*'] || [])),
    ...(data.elementAttributes[canonical] || []),
    ...(nonVisual ? [] : (data.generatedBindingAttributes || [])),
  ])];
  return FOCUS_TRAP_ELEMENTS.has(canonical.toLowerCase()) ? names : names.filter((name) => name !== 'focus-trap');
}

function attributeIsTrue(tag, name) {
  const item = attribute(tag, name);
  return Boolean(item) && ['true', '1', 'yes', 'on', name].includes(item.value.trim().toLowerCase());
}

function visibleLiteralIsTrue(value) {
  return ['true', '1', 'yes', 'on', 'visible'].includes(String(value).trim().toLowerCase());
}

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
    const canonicalTag = canonicalElementName(tag.name);
    if (canonicalTag === 'Component') {
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
      if (attr.name.startsWith('__') || (isBuiltinElement(tag.name) && !isAllowedAttribute(tag.name, attr.name))) {
        diagnostics.push(diagnostic(attr.nameStart, attr.nameEnd, `Unknown attribute '${attr.name}' on <${tag.name}>.`, 'error', 'gxml.unknown-attribute'));
      }
    }
    if (!tag.selfClosing) stack.push(node);
  }
  for (const node of stack) diagnostics.push(diagnostic(node.tag.nameStart, node.tag.nameEnd, `Element <${node.tag.name}> is not closed.`, 'error', 'gxml.unclosed-element'));
  if (roots.length === 0 && text.trim()) diagnostics.push(diagnostic(0, Math.min(1, text.length), 'GXML document contains no root element.', 'error', 'gxml.no-root'));
  if (roots.length > 1) {
    for (const root of roots.slice(1)) diagnostics.push(diagnostic(root.tag.start, root.tag.end, 'GXML documents must contain exactly one root element.', 'error', 'gxml.multiple-roots'));
  }

  if (roots.length) {
    const root = roots[0];
    const rootCanonical = canonicalElementName(root.tag.name);
    if (data.nonVisualElements.includes(rootCanonical)) {
      diagnostics.push(diagnostic(root.tag.nameStart, root.tag.nameEnd, `The document root must be visual; <${root.tag.name}> is a non-visual declaration element.`, 'error', 'gxml.nonvisual-root'));
    }
    const rootIf = attribute(root.tag, 'if');
    if (rootIf) diagnostics.push(diagnostic(rootIf.nameStart, rootIf.valueEnd, "The document root cannot use 'if'; bind 'visible' or put the conditional on a child element.", 'error', 'gxml.root-if'));
  }

  const componentTemplates = new Map();
  for (const node of nodes) {
    if (canonicalElementName(node.tag.name) !== 'Component') continue;
    const name = attribute(node.tag, 'name');
    const templates = node.children.filter((child) => canonicalElementName(child.tag.name) !== 'Param');
    if (name && name.value && templates.length === 1) componentTemplates.set(name.value.toLowerCase(), templates[0]);
  }
  const structuralTag = (node, seen = new Set()) => {
    const canonical = canonicalElementName(node.tag.name);
    if (canonical) return canonical;
    const normalized = node.tag.name.toLowerCase();
    if (seen.has(normalized) || !componentTemplates.has(normalized)) return '';
    const nextSeen = new Set(seen);
    nextSeen.add(normalized);
    return structuralTag(componentTemplates.get(normalized), nextSeen);
  };
  const componentSlot = (template, wantedName) => {
    if (canonicalElementName(template.tag.name) === 'Slot' && (attribute(template.tag, 'name')?.value || '') === wantedName) return template;
    for (const child of template.children) {
      const found = componentSlot(child, wantedName);
      if (found) return found;
    }
    return null;
  };

  const repeatFocusOffenders = new Set();
  const idsByScope = new Map();
  for (const node of nodes) {
    const tag = node.tag;
    const canonicalTag = canonicalElementName(tag.name);
    const id = attribute(tag, 'id');
    if (id && id.value) {
      let scopeNode = node.parent;
      while (scopeNode && canonicalElementName(scopeNode.tag.name) !== 'Component' && !componentTemplates.has(scopeNode.tag.name.toLowerCase())) scopeNode = scopeNode.parent;
      let scopeName = 'document';
      if (scopeNode && canonicalElementName(scopeNode.tag.name) === 'Component') {
        scopeName = `template:${attribute(scopeNode.tag, 'name')?.value.toLowerCase() || `@${scopeNode.tag.start}`}`;
      } else if (scopeNode) {
        const invocationId = attribute(scopeNode.tag, 'id')?.value;
        scopeName = `invocation:${invocationId || `@${scopeNode.tag.start}`}`;
      }
      const scopedId = `${scopeName}\u0000${id.value}`;
      if (idsByScope.has(scopedId)) {
        const first = idsByScope.get(scopedId);
        diagnostics.push(diagnostic(id.valueStart, id.valueEnd, `Duplicate id '${id.value}'; first declared at source offset ${first.valueStart}.`, 'error', 'gxml.duplicate-id'));
      } else {
        idsByScope.set(scopedId, id);
      }
    }
    if (canonicalTag === 'Repeat') {
      const items = attribute(tag, 'items');
      if (!items || !/^\{[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*|\.\d+)*\}$/.test(items.value)) {
        diagnostics.push(diagnostic(items ? items.valueStart : tag.nameStart, items ? items.valueEnd : tag.nameEnd, "Repeat 'items' must be an exact Array or CascadeItemModel binding such as '{inventory.items}'.", 'error', 'gxml.repeat-items'));
      }
      if (node.children.length !== 1) diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, 'Repeat requires exactly one child template.', 'error', 'gxml.repeat-child'));
      const virtual = attribute(tag, 'virtual');
      if (virtual && ['true', '1', 'yes', 'on', 'virtual'].includes(virtual.value.toLowerCase())) {
        const key = attribute(tag, 'key');
        const height = attribute(tag, 'item-height');
        const overscan = attribute(tag, 'overscan');
        if (!key || !key.value.trim()) diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, 'Virtual Repeat requires an explicit stable key.', 'error', 'gxml.virtual-key'));
        if (!height || !/^\d+(?:\.\d+)?(?:px)?$/.test(height.value) || parseFloat(height.value) <= 0) diagnostics.push(diagnostic(height ? height.valueStart : tag.nameStart, height ? height.valueEnd : tag.nameEnd, "Virtual Repeat 'item-height' requires a positive pixel length.", 'error', 'gxml.virtual-height'));
        if (overscan && (!/^\d+$/.test(overscan.value) || Number(overscan.value) < 0)) diagnostics.push(diagnostic(overscan.valueStart, overscan.valueEnd, "Virtual Repeat 'overscan' requires a non-negative integer.", 'error', 'gxml.virtual-overscan'));
      }
    }
    if (canonicalTag === 'Select') {
      for (const child of node.children) if (canonicalElementName(child.tag.name) !== 'Option') diagnostics.push(diagnostic(child.tag.nameStart, child.tag.nameEnd, 'Select only accepts <Option> children.', 'error', 'gxml.select-child'));
    }
    if (canonicalTag === 'Param' && attribute(tag, 'required') && attribute(tag, 'default')) {
      diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, "Param 'required' and 'default' are mutually exclusive.", 'error', 'gxml.param-default'));
    }

    const focusTrap = attribute(tag, 'focus-trap');
    if (focusTrap && attributeIsTrue(tag, 'focus-trap') && canonicalTag && !FOCUS_TRAP_ELEMENTS.has(canonicalTag.toLowerCase())) {
      diagnostics.push(diagnostic(focusTrap.nameStart, focusTrap.valueEnd, "Attribute 'focus-trap' requires an element backed by a native Container.", 'error', 'gxml.focus-trap-owner'));
    }

    if (canonicalTag === 'Repeat' && node.children.length) {
      const visitTemplate = (templateNode) => {
        const offender = ['autofocus', 'focus-trap'].map((name) => attribute(templateNode.tag, name)).find((item) => item && attributeIsTrue(templateNode.tag, item.name));
        if (offender && !repeatFocusOffenders.has(templateNode)) {
          repeatFocusOffenders.add(templateNode);
          diagnostics.push(diagnostic(offender.nameStart, offender.valueEnd, 'Repeat templates cannot author autofocus or focus-trap; focus one stable control outside the collection and manage row focus from application code.', 'error', 'gxml.repeat-focus'));
        }
        for (const child of templateNode.children) visitTemplate(child);
      };
      visitTemplate(node.children[0]);
    }

    if (canonicalTag === 'Repeat' && attributeIsTrue(tag, 'virtual')) {
      let ancestor = node.parent;
      while (ancestor) {
        if (canonicalElementName(ancestor.tag.name) === 'Repeat') {
          diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, 'Virtual Repeat cannot be nested inside another Repeat.', 'error', 'gxml.virtual-nesting'));
          break;
        }
        ancestor = ancestor.parent;
      }
      if (node.children.length) {
        const itemRoot = node.children[0];
        const conditional = attribute(itemRoot.tag, 'if');
        if (conditional) diagnostics.push(diagnostic(conditional.nameStart, conditional.valueEnd, "Virtual Repeat item roots cannot use 'if'; filter the collection model instead.", 'error', 'gxml.virtual-root-if'));
        const visible = attribute(itemRoot.tag, 'visible');
        if (visible && !visibleLiteralIsTrue(visible.value)) {
          diagnostics.push(diagnostic(visible.nameStart, visible.valueEnd, "Virtual Repeat item roots cannot use conditional 'visible'; filter the collection model instead. Literal visible=true is harmless, and descendants may still bind visibility.", 'error', 'gxml.virtual-root-visible'));
        }
      }
    }

    if (canonicalTag === 'Scroll') {
      const contentChildren = node.children.filter((child) => canonicalElementName(child.tag.name) !== 'Bindings');
      if (contentChildren.length !== 1) diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, '<Scroll> requires exactly one content child.', 'error', 'gxml.scroll-child'));
    }

    let structuralParent = node.parent;
    if (structuralParent && componentTemplates.has(structuralParent.tag.name.toLowerCase())) {
      const wantedSlot = attribute(tag, 'slot')?.value || '';
      const placement = componentSlot(componentTemplates.get(structuralParent.tag.name.toLowerCase()), wantedSlot);
      structuralParent = placement ? placement.parent : null;
    }
    while (structuralParent && canonicalElementName(structuralParent.tag.name) === 'Slot') structuralParent = structuralParent.parent;
    if (canonicalTag !== 'Slot' && structuralParent && canonicalElementName(structuralParent.tag.name) !== 'Component') {
      const effectiveTag = structuralTag(node);
      const parentTag = structuralTag(structuralParent);
      if (parentTag === 'Table' && !['TableHeader', 'TableBody', 'TableRow', 'Repeat', 'Bindings'].includes(effectiveTag)) {
        diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, `<Table> accepts only TableHeader, TableBody, TableRow, or Repeat children; got <${tag.name}>.`, 'error', 'gxml.table-child'));
      } else if (['TableHeader', 'TableBody'].includes(parentTag) && !['TableRow', 'Repeat'].includes(effectiveTag)) {
        diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, `<${structuralParent.tag.name}> accepts only TableRow or Repeat children; got <${tag.name}>.`, 'error', 'gxml.table-group-child'));
      } else if (parentTag === 'TableRow' && !['TableHeaderCell', 'TableCell'].includes(effectiveTag)) {
        diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, `<TableRow> accepts only TableHeaderCell or TableCell children; got <${tag.name}>.`, 'error', 'gxml.table-row-child'));
      } else if (['TableHeader', 'TableBody'].includes(effectiveTag) && parentTag !== 'Table') {
        diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, `<${tag.name}> must be a direct child of <Table>.`, 'error', 'gxml.table-group-parent'));
      } else if (effectiveTag === 'TableRow' && !['Table', 'TableHeader', 'TableBody', 'Repeat'].includes(parentTag)) {
        diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, '<TableRow> must be inside Table, TableHeader, TableBody, or a repeated table group.', 'error', 'gxml.table-row-parent'));
      } else if (['TableHeaderCell', 'TableCell'].includes(effectiveTag) && parentTag !== 'TableRow') {
        diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, `<${tag.name}> must be a direct child of <TableRow>.`, 'error', 'gxml.table-cell-parent'));
      } else if (effectiveTag === 'Repeat' && ['Table', 'TableHeader', 'TableBody'].includes(parentTag) && (node.children.length !== 1 || structuralTag(node.children[0]) !== 'TableRow')) {
        diagnostics.push(diagnostic(tag.nameStart, tag.nameEnd, 'Repeat inside table structure must contain exactly one TableRow template.', 'error', 'gxml.table-repeat-template'));
      }
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
        if (canonicalElementName(tag.name) === 'Component' && attr.name === 'name' && attr.value) symbols.push({ kind: 'component', name: attr.value, start: attr.valueStart, end: attr.valueEnd, definition: true });
      }
    }
    const componentNames = new Set(symbols.filter((s) => s.kind === 'component').map((s) => s.name.toLowerCase()));
    for (const symbol of symbols) {
      if (symbol.kind === 'tag' && !isBuiltinElement(symbol.name) && componentNames.has(symbol.name.toLowerCase())) symbol.kind = 'component';
    }
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
  const open = openGxmlTagStart(before);
  if (open < 0) return null;
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

function openGxmlTagStart(text) {
  let open = -1;
  let quote = '';
  let comment = false;
  for (let index = 0; index < text.length; index++) {
    if (comment) {
      if (text.startsWith('-->', index)) { comment = false; index += 2; }
      continue;
    }
    if (open < 0 && text.startsWith('<!--', index)) { comment = true; index += 3; continue; }
    const ch = text[index];
    if (open < 0) { if (ch === '<') open = index; continue; }
    if (quote) { if (ch === quote) quote = ''; continue; }
    if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '>') open = -1;
  }
  return open;
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
    const tags = scanGxml(trimmed).tags;
    const leadingClose = tags.length > 0 && tags[0].closing && tags[0].start === 0;
    if (leadingClose) depth = Math.max(0, depth - 1);
    lines.push(unit.repeat(depth) + trimmed.replace(/\s+\/>$/, ' />'));
    const opening = tags.filter((tag) => !tag.closing && !tag.selfClosing).length;
    const closing = tags.filter((tag) => tag.closing).length;
    depth = Math.max(0, depth + opening - closing - (leadingClose ? -1 : 0));
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
  isBuiltinElement,
  canonicalElementName,
  sameElementName,
  gxmlAttributeNames,
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
