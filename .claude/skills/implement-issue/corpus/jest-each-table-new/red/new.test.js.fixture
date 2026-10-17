const { total } = require('./suma.js');
it.each`
  a | b
  ${1} | ${2}
  ${2} | ${3}
`('adds $a to get $b', ({ a, b }) => { expect(total([a])).toBe(b); });
