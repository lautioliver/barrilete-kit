import { describe, it, expect } from 'vitest';
import { total } from './suma.js';
it.each([[1, 2], [2, 3], [3, 4]])('adds %i to get %i', (a, b) => { expect(total([a])).toBe(b); });
