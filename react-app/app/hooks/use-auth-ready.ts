/**
 * useAuthReady — D-211
 *
 * Returns the resolved AuthState after INITIAL_SESSION fires.
 * Components should check `loading` before acting on `user` or `role`
 * to avoid the auth race described in F-007 (May 4, 2026 fix).
 *
 * Usage:
 *   const { user, role, isAdmin, loading, signOut } = useAuthReady();
 *   if (loading) return <Spinner />;
 *   if (!user) return <Redirect to="/get-started" />;
 */

export { useAuth as useAuthReady } from '../providers/auth-provider';
