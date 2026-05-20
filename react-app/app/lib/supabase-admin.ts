/**
 * Server-side Supabase admin client — D-211.
 *
 * NEVER import this file in a 'use client' component or any file that is
 * imported by one. It references SUPABASE_SERVICE_ROLE_KEY which grants
 * unrestricted database access and must stay server-side only.
 *
 * Use only in Next.js API routes and server components.
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const adminKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

export const supabaseAdmin: SupabaseClient | null = (() => {
  if (!adminKey) {
    console.warn('SUPABASE_SERVICE_ROLE_KEY not set — admin operations unavailable.');
    return null;
  }
  return createClient(supabaseUrl, adminKey, {
    auth: { persistSession: false },
  });
})();
