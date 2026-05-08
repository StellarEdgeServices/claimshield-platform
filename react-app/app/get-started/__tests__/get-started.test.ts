/**
 * Unit tests for get-started page utility functions — D-211 Phase 2
 */

import { describe, it, expect } from 'vitest';
import { formatPhoneValue, isValidEmail } from '../page';

describe('formatPhoneValue', () => {
  it('formats a 10-digit number', () => {
    expect(formatPhoneValue('3175551234')).toBe('(317) 555-1234');
  });

  it('strips leading country code 1 from 11-digit number', () => {
    expect(formatPhoneValue('13175551234')).toBe('(317) 555-1234');
  });

  it('handles partial input — 3 digits', () => {
    expect(formatPhoneValue('317')).toBe('(317');
  });

  it('handles partial input — 6 digits', () => {
    expect(formatPhoneValue('317555')).toBe('(317) 555');
  });

  it('returns empty string for empty input', () => {
    expect(formatPhoneValue('')).toBe('');
  });

  it('strips non-numeric characters', () => {
    expect(formatPhoneValue('(317) 555-1234')).toBe('(317) 555-1234');
  });

  it('truncates to 10 digits max', () => {
    expect(formatPhoneValue('31755512349999')).toBe('(317) 555-1234');
  });
});

describe('isValidEmail', () => {
  it('accepts valid email addresses', () => {
    expect(isValidEmail('jane@example.com')).toBe(true);
    expect(isValidEmail('user+tag@domain.org')).toBe(true);
    expect(isValidEmail('a@b.co')).toBe(true);
  });

  it('rejects invalid email addresses', () => {
    expect(isValidEmail('')).toBe(false);
    expect(isValidEmail('notanemail')).toBe(false);
    expect(isValidEmail('@domain.com')).toBe(false);
    expect(isValidEmail('user@')).toBe(false);
    expect(isValidEmail('user @domain.com')).toBe(false);
  });
});
