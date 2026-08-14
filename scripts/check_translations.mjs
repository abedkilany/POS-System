import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const translationsDir = path.join(root, 'assets', 'translations');
const libDir = path.join(root, 'lib');

const parseTranslations = (filename) => {
  const filePath = path.join(translationsDir, filename);
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    console.error(`Invalid JSON in ${filename}: ${error.message}`);
    process.exit(1);
  }
};

const en = parseTranslations('en.json');
const ar = parseTranslations('ar.json');
const fr = parseTranslations('fr.json');
const translations = { en, ar, fr };
const errors = [];

const enKeys = new Set(Object.keys(en));
const arKeys = new Set(Object.keys(ar));
const frKeys = new Set(Object.keys(fr));
const intentionallyUntranslatedArabic = new Set([
  'CSV',
  'Google Drive',
  'Wish',
  'FIFO',
  'ICE',
  'Bluetooth',
  'USB',
]);

for (const key of enKeys) {
  if (!arKeys.has(key)) errors.push(`Missing in ar.json: ${key}`);
  if (!frKeys.has(key)) errors.push(`Missing in fr.json: ${key}`);
}
for (const key of arKeys) {
  if (!enKeys.has(key)) errors.push(`Missing in en.json: ${key}`);
}
for (const key of frKeys) {
  if (!enKeys.has(key)) errors.push(`Extra in fr.json: ${key}`);
}

const placeholders = (value) =>
  [...String(value).matchAll(/\{[^}]+\}/g)]
    .map((match) => match[0])
    .sort()
    .join('|');

for (const key of enKeys) {
  if (typeof en[key] !== 'string') errors.push(`Non-string English value: ${key}`);
  if (typeof ar[key] !== 'string') errors.push(`Non-string Arabic value: ${key}`);
  if (typeof fr[key] !== 'string') errors.push(`Non-string French value: ${key}`);
  for (const [locale, values] of Object.entries(translations)) {
    if (placeholders(en[key]) !== placeholders(values[key])) {
      errors.push(`Placeholder mismatch in ${locale}.json: ${key}`);
    }
  }
  if (!String(en[key]).trim()) errors.push(`Empty English value: ${key}`);
  if (!String(ar[key]).trim()) errors.push(`Empty Arabic value: ${key}`);
  if (!String(fr[key]).trim()) errors.push(`Empty French value: ${key}`);
  if (en[key] === ar[key] && /[A-Za-z]/.test(en[key]) &&
      !intentionallyUntranslatedArabic.has(en[key])) {
    errors.push(`Arabic value is still English: ${key}`);
  }
  if (/[\u00d8\u00d9\ufffd]|\?{3,}/.test(ar[key])) {
    errors.push(`Corrupted Arabic value: ${key}`);
  }
  if (/[\u00d8\u00d9\ufffd]|\?{3,}/.test(fr[key])) {
    errors.push(`Corrupted French value: ${key}`);
  }
}

const usedKeys = new Set();
const dartFiles = [];
function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const filePath = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(filePath);
    else if (entry.name.endsWith('.dart')) dartFiles.push(filePath);
  }
}
walk(libDir);

for (const filePath of dartFiles) {
  const source = fs.readFileSync(filePath, 'utf8');
  for (const match of source.matchAll(/(?:\.text|\.format|\b_t|\b_tf)\s*\(\s*['"]([^'"]+)['"]/g)) {
    const key = match[1];
    // Runtime-composed keys are validated by their source maps, not as literals.
    if (!key.includes('$') && !key.includes('{')) usedKeys.add(key);
  }
}

for (const key of usedKeys) {
  if (!enKeys.has(key) || !arKeys.has(key) || !frKeys.has(key)) {
    errors.push(`Used key is not present in all translation files: ${key}`);
  }
}

// Scan UI-producing Dart files for literal user-facing text. Values that are
// data/protocol identifiers or universally displayed technical units are
// intentionally exempt; interpolated runtime data is ignored.
const visibleLiteralPatterns = [
  /\b(?:Text|SelectableText)\s*\(\s*(?:const\s*)?(['"])([^'"\r\n]*)\1/g,
  /\b(?:labelText|hintText|helperText|errorText|tooltip|semanticsLabel|emptyText)\s*:\s*(?:const\s*)?(['"])([^'"\r\n]*)\1/g,
];
const allowedVisibleLiterals = new Set([
  'USD',
  'LBP',
  'USB',
  'Bluetooth',
  'LAN',
  'Direct',
  '58 mm',
  '80 mm',
]);
const uiFile = (filePath) => {
  const relative = path.relative(root, filePath).replaceAll('\\', '/');
  return relative === 'lib/app.dart' ||
    relative.startsWith('lib/features/') ||
    relative.startsWith('lib/widgets/') ||
    relative === 'lib/core/snapshot/unified_snapshot_progress.dart';
};
const staticVisiblePart = (value) => value
  .replace(/\$\{[^}]*\}/g, '')
  .replace(/\$[A-Za-z_]\w*/g, '')
  .trim();

for (const filePath of dartFiles.filter(uiFile)) {
  const source = fs.readFileSync(filePath, 'utf8');
  const lineNumberAt = (offset) => source.slice(0, offset).split('\n').length;
  for (const pattern of visibleLiteralPatterns) {
    pattern.lastIndex = 0;
    for (const match of source.matchAll(pattern)) {
      const lineStart = source.lastIndexOf('\n', match.index) + 1;
      if (/^\s*\/\//.test(source.slice(lineStart, match.index))) continue;
      if (match[2].startsWith('${') ||
          /\$\{(?:tr\.|_t\(|_tf\(|AppLocalizations\.of\()/.test(match[2])) {
        continue;
      }
      const literal = staticVisiblePart(match[2]);
      if (!literal || allowedVisibleLiterals.has(literal)) continue;
      if (/[A-Za-z\u0600-\u06ff]/.test(literal)) {
        errors.push(
          `Hardcoded visible text: ${path.relative(root, filePath)}:${lineNumberAt(match.index)} -> ${match[2]}`,
        );
      }
    }
  }
  for (const match of source.matchAll(/\btr\.isArabic\s*\?\s*['"]/g)) {
    const lineStart = source.lastIndexOf('\n', match.index) + 1;
    if (!/^\s*\/\//.test(source.slice(lineStart, match.index))) {
      errors.push(
        `Inline bilingual UI text must use a translation key: ${path.relative(root, filePath)}:${lineNumberAt(match.index)}`,
      );
    }
  }
}

if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}

console.log(`Translation check passed: ${enKeys.size} keys in en/ar/fr, ${usedKeys.size} literal usages.`);
