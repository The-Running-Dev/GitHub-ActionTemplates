// node --test does not create the folders its reporters write to.
import { mkdirSync } from 'node:fs';

for (const folder of ['test-results', 'coverage']) mkdirSync(folder, { recursive: true });
