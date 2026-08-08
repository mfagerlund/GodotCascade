'use strict';

const core = require('./core');

function isReusableComponentTarget(symbol) {
  return Boolean(symbol) && (symbol.kind === 'component' || (symbol.kind === 'tag' && !core.isBuiltinElement(symbol.name)));
}

function isRenameableTarget(symbol) {
  if (!symbol) return false;
  if (symbol.kind === 'component') return !core.isBuiltinElement(symbol.name);
  if (symbol.kind === 'tag') return !core.isBuiltinElement(symbol.name);
  return ['class', 'id', 'custom-property'].includes(symbol.kind);
}

function renameScope(target) {
  return isReusableComponentTarget(target) ? 'document' : 'workspace';
}

function renameMatches(target, candidate) {
  if (!isRenameableTarget(target)) return false;
  if (isReusableComponentTarget(target)) {
    return (candidate.kind === 'component' || (candidate.kind === 'tag' && !core.isBuiltinElement(candidate.name)))
      && core.sameElementName(candidate.name, target.name);
  }
  return candidate.kind === target.kind && candidate.name === target.name;
}

function definitionMatches(target, candidate) {
  if (isReusableComponentTarget(target)) {
    return candidate.kind === 'component' && candidate.definition && core.sameElementName(candidate.name, target.name);
  }
  return candidate.kind === target.kind && candidate.definition && candidate.name === target.name;
}

function selectRenameSources(target, documentSource, workspaceSources) {
  if (renameScope(target) === 'document') return [documentSource];
  const sourcesByUri = new Map(workspaceSources.map((source) => [String(source.uri), source]));
  sourcesByUri.set(String(documentSource.uri), documentSource);
  return [...sourcesByUri.values()];
}

module.exports = {
  definitionMatches,
  isRenameableTarget,
  isReusableComponentTarget,
  renameMatches,
  renameScope,
  selectRenameSources
};
