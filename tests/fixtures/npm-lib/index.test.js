'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const greet = require('./index.js');

test('greet', () => {
  assert.equal(greet('Octo'), 'Hello, Octo.');
});
