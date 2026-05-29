export function formatPhoneValue(raw: string): string {
  let v = raw.replace(/\D/g, '');
  if (v.length === 11 && v.startsWith('1')) v = v.slice(1);
  if (v.length > 10) v = v.slice(0, 10);
  if (v.length === 0) return '';
  if (v.length <= 3) return `(${v}`;
  if (v.length <= 6) return `(${v.slice(0, 3)}) ${v.slice(3)}`;
  return `(${v.slice(0, 3)}) ${v.slice(3, 6)}-${v.slice(6, 10)}`;
}

export function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}
