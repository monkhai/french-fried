import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export default {
  appRoot: root,
  appPath: resolve(root, 'release/output/simulator/Build/Products/Release-iphonesimulator/FrenchFried.app'),
  bundleId: 'local.frenchfried.app',
  devices: ['iphone-6.9'],
  locales: ['en-US'],
  appearance: 'light',
  frame: { variant: '17-pro-orange' },
  theme: {
    background: 'linear-gradient(160deg, #FFF5DF 0%, #FFE1A6 100%)',
    headlineColor: '#382117',
    subheadColor: '#76513B',
    fontFamily: 'DM Sans',
    layout: 'classic',
    copyHeightRatio: 0.24,
    deviceWidthRatio: 0.84,
  },
  store: {
    name: 'French Fried',
    subtitle: { 'en-US': 'From couch to running crew' },
    developer: 'Yohai Wiener',
    category: 'Health & Fitness',
    price: 'Free',
    description: { 'en-US': 'Build a running habit, one session at a time. A nine-week program, free runs, and a crew to cheer you on.' },
  },
  // Add authenticated scenes after testing a dedicated screenshot account.
  // Never capture a real user's routes, invitation codes, or personal data.
  scenes: [{
    kind: 'screenshot',
    id: 'welcome',
    flow: 'store-01-welcome',
    headline: { 'en-US': 'From couch potato\nto hot potato.' },
    subhead: { 'en-US': 'Your next chapter starts with a run.' },
  }],
};
