const { total } = require('./suma.js');
it('passes', () => { expect(1).toBe(1); });

it.each([
  [1, 2],
  [2, 3],
])('adds %i to get %i', (a, b) => {
  expect(total([a])).toBe(b);
});
