'use client';

import {
  QueryClient,
  QueryClientProvider as TanstackQueryClientProvider,
} from '@tanstack/react-query';
import { ReactNode } from 'react';

/**
 * React Query client singleton with documented defaults for OtterQuote.
 *
 * Defaults:
 * - staleTime: 30s (claims data changes infrequently)
 * - retry: 2 (transient Supabase errors are common; 3 total attempts)
 * - refetchOnWindowFocus: true (stay in sync when tab regains focus)
 * - gcTime: 5min (5 minute cache before garbage collection)
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: 2,
      refetchOnWindowFocus: true,
      gcTime: 5 * 60 * 1000,
    },
  },
});

/**
 * QueryClientProvider wrapper component.
 */
export function QueryClientProvider({ children }: { children: ReactNode }) {
  return (
    <TanstackQueryClientProvider client={queryClient}>
      {children}
    </TanstackQueryClientProvider>
  );
}
