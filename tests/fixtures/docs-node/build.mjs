// Stands in for a site generator: writes build/index.html with a marker the tests look for.
import { mkdirSync, writeFileSync } from 'node:fs';

mkdirSync('build', { recursive: true });
writeFileSync('build/index.html', '<!doctype html><title>docs-node</title><p>docs-node-fixture-marker</p>\n');
