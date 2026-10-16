// Stands in for a bundler: writes dist/index.html with a marker, the base path and a build
// variable, so the self-test can see what pages.yml handed to the build.
import { mkdirSync, writeFileSync } from 'node:fs';

const base = process.env.PAGES_BASE_PATH ?? '';
const value = process.env.PAGES_FIXTURE_VALUE ?? '';
mkdirSync('dist', { recursive: true });
writeFileSync('dist/index.html', `<!doctype html><title>pages-app</title><base href="${base}"><p>pages-app-fixture-marker ${value}</p>\n`);
