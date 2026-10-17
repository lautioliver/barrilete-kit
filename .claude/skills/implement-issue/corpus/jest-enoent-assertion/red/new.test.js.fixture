const { total } = require('./suma.js');
const fs = require('fs');
it('reads the missing file', () => {
  let msg = '';
  try { fs.readFileSync('/no/such/file.txt'); } catch (e) { msg = e.code; }
  expect(msg).toBe('OK');
});
