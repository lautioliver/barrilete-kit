const { total } = require('./suma.js');
it.each([[1, 2], [2, 3]])('adds %i to get %i', (a, b) => { expect(total([a])).toBe(b); });
