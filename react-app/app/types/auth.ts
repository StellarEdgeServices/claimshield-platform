/**
 * Auth types for OtterQuote React app — D-211
 * Mirrors F-007 pattern from js/auth.js
 */

export type OtterRole =
  | 'homeowner'
  | 'contractor'
  | 're_agent'
  | 'insurance_agent'
  | 'home_inspector'
  | null;

export interface AuthUser {
  id: string;
  email: string;
  [key: string]: unknown;
}

export interface AuthState {
  /** null = unauthenticated or still loading */
  user: AuthUser | null;
  /** contractor-table-first role check (F-007) */
  role: OtterRole;
  /** True if user is in the admin allow-list (D-211) */
  isAdmin: boolean;
  /** True while INITIAL_SESSION has not yet fired */
  loading: boolean;
}

export interface AuthContextValue extends AuthState {
  /** Imperatively sign out the current user */
  signOut: () => Promise<void>;
}
