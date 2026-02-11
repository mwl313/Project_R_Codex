#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const ROOT = process.cwd();

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === '.git' || entry.name === 'node_modules') continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, out);
    } else if (entry.isFile() && fullPath.endsWith('.lua')) {
      out.push(fullPath);
    }
  }
  return out;
}

function parseLocaleKeys(filePath) {
  const text = fs.readFileSync(filePath, 'utf8');
  let index = text.indexOf('{');
  const keys = new Set();
  const stack = [];

  function skipWhitespaceAndComments() {
    while (index < text.length) {
      const ch = text[index];
      if (/\s/.test(ch)) {
        index += 1;
        continue;
      }
      if (ch === '-' && text[index + 1] === '-') {
        index += 2;
        while (index < text.length && text[index] !== '\n') index += 1;
        continue;
      }
      break;
    }
  }

  function readIdentifier() {
    const match = text.slice(index).match(/^([A-Za-z_][A-Za-z0-9_]*)/);
    if (!match) return null;
    index += match[1].length;
    return match[1];
  }

  function readString() {
    const quote = text[index];
    if (quote !== '"' && quote !== "'") return null;
    index += 1;
    let value = '';
    while (index < text.length) {
      const ch = text[index++];
      if (ch === '\\') {
        if (index < text.length) value += text[index++];
      } else if (ch === quote) {
        return value;
      } else {
        value += ch;
      }
    }
    return value;
  }

  function parseTable() {
    index += 1;
    while (index < text.length) {
      skipWhitespaceAndComments();
      if (text[index] === '}') {
        index += 1;
        return;
      }

      let key = null;
      const backup = index;

      if (text[index] === '[') {
        index += 1;
        skipWhitespaceAndComments();
        key = readString();
        skipWhitespaceAndComments();
        if (text[index] === ']') index += 1;
      } else {
        key = readIdentifier();
      }

      if (!key) {
        index = backup + 1;
        continue;
      }

      skipWhitespaceAndComments();
      if (text[index] !== '=') continue;
      index += 1;
      skipWhitespaceAndComments();

      stack.push(key);
      if (text[index] === '{') {
        parseTable();
      } else if (text[index] === '"' || text[index] === "'") {
        readString();
        keys.add(stack.join('.'));
      } else {
        while (index < text.length && text[index] !== ',' && text[index] !== '}') index += 1;
        keys.add(stack.join('.'));
      }
      stack.pop();

      skipWhitespaceAndComments();
      if (text[index] === ',') index += 1;
    }
  }

  if (index < 0) return keys;
  parseTable();
  return keys;
}

function extractUsedKeys(luaText) {
  const keys = new Set();
  const pattern = /\bt\(\s*["']([A-Za-z0-9_.]+)["']/g;
  let match;
  while ((match = pattern.exec(luaText)) !== null) {
    keys.add(match[1]);
  }
  return keys;
}

function run() {
  const localeKoPath = path.join(ROOT, 'i18n', 'locales', 'ko.lua');
  const localeEnPath = path.join(ROOT, 'i18n', 'locales', 'en.lua');

  const koKeys = parseLocaleKeys(localeKoPath);
  const enKeys = parseLocaleKeys(localeEnPath);

  const luaFiles = walk(ROOT).filter((filePath) => {
    const normalized = filePath.replace(/\\/g, '/');
    return !normalized.includes('/i18n/locales/');
  });

  const missingInKo = [];
  const missingInEn = [];

  for (const filePath of luaFiles) {
    const relPath = path.relative(ROOT, filePath).replace(/\\/g, '/');
    const content = fs.readFileSync(filePath, 'utf8');
    const usedKeys = extractUsedKeys(content);

    for (const key of usedKeys) {
      if (!koKeys.has(key)) {
        missingInKo.push({ file: relPath, key });
      }
      if (!enKeys.has(key)) {
        missingInEn.push({ file: relPath, key });
      }
    }
  }

  if (missingInKo.length === 0 && missingInEn.length === 0) {
    console.log('[i18n-audit] PASS: no missing locale keys.');
    process.exit(0);
  }

  if (missingInKo.length > 0) {
    console.error('[i18n-audit] Missing keys in ko.lua:');
    for (const item of missingInKo) {
      console.error(`- ${item.file}: ${item.key}`);
    }
  }

  if (missingInEn.length > 0) {
    console.error('[i18n-audit] Missing keys in en.lua:');
    for (const item of missingInEn) {
      console.error(`- ${item.file}: ${item.key}`);
    }
  }

  process.exit(1);
}

run();
