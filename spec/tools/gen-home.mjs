#!/usr/bin/env node
// Generates a PREMIUM `home` SDUI screen from catalog.json — the app chrome is
// itself server-driven, so it renders identically on iOS/Android/Aurora and
// dogfoods the engine. Design direction is our own (a developer-facing SDUI
// showcase), NOT a travel-photo clone: tonal gradients carry colour, bold type
// carries hierarchy, one accent, horizontal rails with peek + section rhythm.
// Single source of truth: the catalog categories. Run: node spec/tools/gen-home.mjs

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CATALOG = 'ios/Sources/SDUIPlayground/Content/catalog.json';
const OUT = 'ios/Sources/SDUIPlayground/Content/screens/home.json';
const catalog = JSON.parse(readFileSync(join(ROOT, CATALOG), 'utf8'));

const LG = '$token.spacing.lg';
const MD = '$token.spacing.md';
const SM = '$token.spacing.sm';
const XS = '$token.spacing.xs';
const text = (value, style, color, extra = {}) => ({ type: 'text', value, style, color, ...extra });
const pretty = (id) =>
  id.replace(/^\d+[-_]?/, '').replace(/[-_]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
const nav = (to) => ({ action: 'navigate', to, transition: 'push' });

// A glyph per screen so every card reads at a glance (what the screen shows) —
// falls back to the category icon. This is what makes the capabilities legible.
const ICONS = {
  fitness: 'figure.run', music: 'music.note', stocks: 'chart.line.uptrend.xyaxis', weather: 'cloud.sun.fill',
  cart: 'cart.fill', messenger: 'bubble.left.and.bubble.right.fill', feed: 'square.stack.fill', clips: 'play.rectangle.fill',
  todo: 'checklist', paywall: 'crown.fill', delivery: 'shippingbox.fill', gym: 'dumbbell.fill', discover: 'sparkles',
  product: 'tag.fill', inbox: 'tray.fill', signup: 'person.crop.circle.badge.plus', settings: 'gearshape.fill',
  typography: 'textformat', layout: 'square.grid.3x3.fill', buttons: 'capsule.fill', inputs: 'character.cursor.ibeam',
  controls: 'switch.2', uploader: 'arrow.up.doc.fill', cards: 'rectangle.stack.fill', components: 'square.grid.2x2.fill',
  feedback: 'exclamationmark.bubble.fill', calendar: 'calendar', materials: 'drop.fill', capabilities: 'bolt.shield.fill',
  swipe: 'hand.draw.fill', gestures: 'hand.tap.fill', animation: 'wand.and.rays', table: 'tablecells.fill',
  document: 'doc.text.fill', actions: 'bolt.fill', lists: 'list.bullet', reorder: 'arrow.up.arrow.down', figma: 'wand.and.stars',
};
const iconFor = (id, fallback) => ICONS[id] || fallback || 'square.grid.2x2.fill';

// A soft, single-tier shadow (premium apps cap elevation at one subtle tier).
const softShadow = { radius: 12, y: 6, color: '#0E0E1216' };

// ── 1. Header: eyebrow + big bold wordmark + one quiet subline ───────────────
const header = {
  type: 'vstack', alignment: 'leading', spacing: XS,
  modifiers: { padding: { leading: LG, trailing: LG, top: MD } },
  children: [
    text('SERVER-DRIVEN UI', '$token.typography.caption', '$token.color.primary'),
    text('SDUI', '$token.typography.hero', '$token.color.textPrimary'),
    text('Every screen here is JSON — rendered natively on iOS, Android and Aurora.',
      '$token.typography.subheadline', '$token.color.textSecondary'),
  ],
};

// ── 2. Story rail: capability circles (the engine's pitch, tappable) ─────────
// Aligned 1:1 with the native CapabilityStory.all so tapping opens the real
// segmented stories player at the matching index (a `custom` action the host
// interprets — the legitimate full-screen immersive case).
const STORIES = [
  { label: 'Server', icon: 'arrow.triangle.2.circlepath', colors: ['#6666F5', '#754AB5'] },
  { label: 'One JSON', icon: 'square.on.square', colors: ['#00B89E', '#00738C'] },
  { label: 'Theming', icon: 'paintpalette.fill', colors: ['#FA8C30', '#D94D4D'] },
  { label: 'Components', icon: 'square.grid.2x2.fill', colors: ['#C93DDB', '#8C2EB8'] },
];
// A square size helper (for circles via a pill corner radius).
const sq = (n) => ({ width: { mode: 'fixed', value: n }, height: { mode: 'fixed', value: n } });

// Instagram-style story: a gradient RING (outer) → a background gap → an inner
// circle carrying the feature glyph. Tapping opens the feature.
const storyCircle = (s, i) => ({
  type: 'vstack', alignment: 'center', spacing: XS,
  modifiers: { size: { width: { mode: 'fixed', value: 84 } },
    onTap: { action: 'custom', name: 'story', payload: { index: i } } },
  children: [
    { type: 'zstack', alignment: 'center', children: [
      { type: 'gradient', colors: s.colors, direction: 'diagonal',
        modifiers: { size: sq(72), cornerRadius: '$token.radius.pill' } },
      { type: 'vstack', children: [],
        modifiers: { size: sq(63), background: '$token.color.surface', cornerRadius: '$token.radius.pill' } },
      { type: 'zstack', alignment: 'center',
        modifiers: { size: sq(55), background: '$token.color.surfaceElevated', cornerRadius: '$token.radius.pill' },
        children: [{ type: 'icon', name: s.icon, color: s.colors[1], size: 24 }] },
    ] },
    text(s.label, '$token.typography.caption', '$token.color.textSecondary', { alignment: 'center', lineLimit: 1 }),
  ],
});
const storyRail = {
  type: 'scroll', axis: 'horizontal', showsIndicators: false,
  child: { type: 'hstack', spacing: MD, modifiers: { padding: { horizontal: LG } },
    children: STORIES.map((s, i) => storyCircle(s, i)) },
};

// ── 3. Hero: a swipeable collection of full-bleed banners (peek of the next) ──
const HERO_W = 330;
const HERO_H = 220;
const BANNERS = [
  { eyebrow: 'FEATURED', title: 'Ship whole screens from JSON',
    subtitle: 'One contract, three native apps — no release.',
    colors: ['#5B5BF0', '#7C4DFF', '#FF6B9D'], shadow: '#5B5BF033', to: 'discover' },
  { eyebrow: 'ONE CONTRACT', title: 'iOS · Android · Aurora',
    subtitle: 'The same JSON renders natively on all three.',
    colors: ['#00B89E', '#0A84FF'], shadow: '#00B89E33', to: 'figma' },
  { eyebrow: 'LIVE THEMING', title: 'Re-theme the whole app',
    subtitle: 'Design tokens ship over the wire, instantly.',
    colors: ['#FA8C30', '#D94D4D'], shadow: '#FA8C3033', to: 'materials' },
];
const banner = (b) => ({
  type: 'zstack', alignment: 'bottomLeading',
  modifiers: { size: { width: { mode: 'fixed', value: HERO_W } }, onTap: nav(b.to) },
  children: [
    { type: 'gradient', colors: b.colors, direction: 'diagonal',
      modifiers: { size: { width: { mode: 'fixed', value: HERO_W }, height: { mode: 'fixed', value: HERO_H } },
        cornerRadius: '$token.radius.lg', shadow: { radius: 20, y: 12, color: b.shadow } } },
    { type: 'gradient', colors: ['#00000000', '#00000066'], direction: 'vertical',
      modifiers: { size: { width: { mode: 'fixed', value: HERO_W }, height: { mode: 'fixed', value: HERO_H } },
        cornerRadius: '$token.radius.lg' } },
    { type: 'vstack', alignment: 'leading', spacing: XS, modifiers: { padding: LG },
      children: [
        text(b.eyebrow, '$token.typography.caption', '#FFFFFFCC'),
        text(b.title, '$token.typography.title2', '#FFFFFF'),
        text(b.subtitle, '$token.typography.subheadline', '#FFFFFFCC'),
        text('Explore  →', '$token.typography.subheadline', '$token.color.primary', {
          modifiers: { padding: { leading: MD, trailing: MD, top: XS, bottom: XS },
            background: '#FFFFFF', cornerRadius: '$token.radius.pill' } }),
      ] },
  ],
});
const heroRail = {
  type: 'scroll', axis: 'horizontal', showsIndicators: false,
  child: { type: 'hstack', spacing: MD, modifiers: { padding: { horizontal: LG } },
    children: BANNERS.map(banner) },
};

// ── 4. Per-category horizontal rails (peek of the next card) ─────────────────
const railCard = (entry, colors, catIcon) => ({
  type: 'vstack', alignment: 'leading', spacing: SM,
  // Fixed size so every card in a rail is identical height — even bottoms, no ragged rail.
  modifiers: {
    size: { width: { mode: 'fixed', value: 172 }, height: { mode: 'fixed', value: 212 } },
    padding: MD, background: '$token.color.surfaceElevated',
    cornerRadius: '$token.radius.lg', shadow: softShadow,
    onTap: nav(entry.id),
  },
  children: [
    // Tonal gradient cover with the screen's glyph centred — reads at a glance.
    { type: 'zstack', alignment: 'center', children: [
      { type: 'gradient', colors, direction: 'diagonal',
        modifiers: { size: { width: { mode: 'fill' }, height: { mode: 'fixed', value: 96 } },
          cornerRadius: '$token.radius.md' } },
      { type: 'icon', name: iconFor(entry.id, catIcon), color: '#FFFFFF', size: 30 },
    ] },
    text(pretty(entry.id), '$token.typography.headline', '$token.color.textPrimary', { lineLimit: 1 }),
    text(entry.subtitle, '$token.typography.caption', '$token.color.textSecondary', { lineLimit: 2 }),
  ],
});
const railSection = (cat) => ({
  type: 'vstack', alignment: 'leading', spacing: SM,
  children: [
    { type: 'hstack', modifiers: { padding: { horizontal: LG } }, children: [
      text(cat.name, '$token.typography.title2', '$token.color.textPrimary'),
      { type: 'spacer' },
      text('See all', '$token.typography.subheadline', '$token.color.primary'),
    ] },
    { type: 'scroll', axis: 'horizontal', showsIndicators: false,
      child: { type: 'hstack', spacing: MD, modifiers: { padding: { horizontal: LG } },
        children: cat.screens.map((s) => railCard(s, cat.colors, cat.icon)) } },
  ],
});

const doc = {
  version: '0.1',
  screen: {
    id: 'home',
    content: {
      type: 'scroll',
      child: {
        type: 'vstack', alignment: 'leading', spacing: '$token.spacing.xl',
        modifiers: { padding: { top: SM, bottom: '$token.spacing.xl' }, size: { width: { mode: 'fill' } } },
        children: [header, storyRail, heroRail, ...catalog.categories.map(railSection)],
      },
    },
  },
};

writeFileSync(join(ROOT, OUT), JSON.stringify(doc, null, 2) + '\n');
console.log(`wrote ${OUT} (${catalog.categories.length} rails, ${catalog.categories.reduce((n, c) => n + c.screens.length, 0)} cards)`);
