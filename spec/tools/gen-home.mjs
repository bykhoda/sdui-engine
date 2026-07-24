#!/usr/bin/env node
// Generates a premium `home` SDUI screen from catalog.json, so the app CHROME is
// itself server-driven — rendered by the engine identically on iOS/Android/Aurora
// (dogfooding the whole thesis). Single source of truth: the catalog categories.
// Run:  node spec/tools/gen-home.mjs   (re-run after editing catalog.json)

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CATALOG = 'ios/Sources/SDUIPlayground/Content/catalog.json';
const OUT = 'ios/Sources/SDUIPlayground/Content/screens/home.json';

const catalog = JSON.parse(readFileSync(join(ROOT, CATALOG), 'utf8'));

const text = (value, style, color) => ({ type: 'text', value, style, color });
const pretty = (id) =>
  id.replace(/^\d+[-_]?/, '').replace(/[-_]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

// One tappable catalog card: gradient chip (category identity) + title + subtitle,
// firing a server-driven navigate to the target screen.
const card = (entry, colors) => ({
  type: 'vstack',
  alignment: 'leading',
  spacing: '$token.spacing.sm',
  modifiers: {
    padding: '$token.spacing.md',
    background: '$token.color.surfaceElevated',
    cornerRadius: '$token.radius.lg',
    shadow: { radius: 10, y: 4, color: '#0E0E1214' },
    size: { width: { mode: 'fill' } },
    onTap: { action: 'navigate', to: entry.id, transition: 'push' },
  },
  children: [
    {
      type: 'gradient',
      colors,
      direction: 'diagonal',
      modifiers: {
        size: { width: { mode: 'fixed', value: 40 }, height: { mode: 'fixed', value: 40 } },
        cornerRadius: '$token.radius.md',
      },
    },
    text(pretty(entry.id), '$token.typography.headline', '$token.color.textPrimary'),
    { ...text(entry.subtitle, '$token.typography.caption', '$token.color.textSecondary'), lineLimit: 2 },
  ],
});

const section = (cat) => [
  text(cat.name.toUpperCase(), '$token.typography.caption', '$token.color.primary'),
  { type: 'grid', columns: 2, spacing: '$token.spacing.md', children: cat.screens.map((s) => card(s, cat.colors)) },
];

const header = {
  type: 'vstack',
  alignment: 'leading',
  spacing: '$token.spacing.xs',
  children: [
    text('SERVER-DRIVEN UI', '$token.typography.caption', '$token.color.primary'),
    text('SDUI', '$token.typography.hero', '$token.color.textPrimary'),
    text('Ship whole screens from JSON — one contract, three native apps.',
      '$token.typography.subheadline', '$token.color.textSecondary'),
  ],
};

const doc = {
  version: '0.1',
  screen: {
    id: 'home',
    title: 'SDUI',
    content: {
      type: 'scroll',
      child: {
        type: 'vstack',
        alignment: 'leading',
        spacing: '$token.spacing.lg',
        modifiers: { padding: '$token.spacing.lg', size: { width: { mode: 'fill' } } },
        children: [header, ...catalog.categories.flatMap(section)],
      },
    },
  },
};

writeFileSync(join(ROOT, OUT), JSON.stringify(doc, null, 2) + '\n');
console.log(`wrote ${OUT} (${catalog.categories.length} categories, ${catalog.categories.reduce((n, c) => n + c.screens.length, 0)} cards)`);
