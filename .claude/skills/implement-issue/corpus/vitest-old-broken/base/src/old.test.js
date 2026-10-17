import { describe, it, expect } from 'vitest';
import { total } from './suma.js';
it('parses', () => { expect(total([1])).toBe(1); });
