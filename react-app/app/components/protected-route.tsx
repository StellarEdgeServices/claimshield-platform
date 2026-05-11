/**
 * ProtectedRoute — D-211
 *
 * Client component that auth-gates its children.
 * Uses useAuthReady() (which waits for INITIAL_SESSION) so there is
 * no flash of unauthenticated content or premature redirect.
 *
 * Props:
 *   requireAdmin   — if true, also requires isAdmin === true
 *   redirectTo     — where to send unauthenticated users (default: '/get-started')
 *   adminRedirect  — where to send authenticated non-admins (default: '/dashboard')
 *   fallback       — what to render while loading (default: null / blank)
 */

'use client';

import { useEffect } from 'react';
import type { ReactNode } from 'react';
import { useRouter } from 'next/navigation';
import { useAuthReady } from '../hooks/use-auth-ready';

interface ProtectedRouteProps {
  children: ReactNode;
  requireAdmin?: boolean;
  redirectTo?: string;
  adminRedirect?: string;
  fallback?: ReactNode;
}

export function ProtectedRoute({
  children,
  requireAdmin = false,
  redirectTo = '/get-started',
  adminRedirect = '/dashboard',
  fallback = null,
}: ProtectedRouteProps) {
  const { user, isAdmin, loading } = useAuthReady();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;

    if (!user) {
      router.replace(redirectTo);
      return;
    }

    if (requireAdmin && !isAdmin) {
      router.replace(adminRedirect);
    }
  }, [loading, user, isAdmin, requireAdmin, redirectTo, adminRedirect, router]);

  // Show fallback while loading or while redirect is in flight
  if (loading) return <>{fallback}</>;
  if (!user) return <>{fallback}</>;
  if (requireAdmin && !isAdmin) return <>{fallback}</>;

  return <>{children}</>;
}
