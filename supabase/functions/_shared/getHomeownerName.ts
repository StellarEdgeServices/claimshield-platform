/**
 * getHomeownerName — shared resolver for homeowner identity from the profiles table.
 *
 * Resolves: claim.user_id → profiles.{full_name, email}.
 *
 * NEVER substitute the contractor signer record for the homeowner identity —
 * doing so caused UNKNOWN_ENVELOPE_RECIPIENT in DocuSign (PFW canary 2026-05-20)
 * and was the source of two independent production patches before this consolidation.
 *
 * Callers should default missing values to a safe fallback at the call site
 * (e.g. "Homeowner" for envelope display).
 */

export interface HomeownerProfile {
  /** profiles.full_name, or "" if no claim, no user_id, or no profile row */
  fullName: string;
  /** profiles.email, or "" if no claim, no user_id, or no profile row */
  email: string;
}

export async function getHomeownerName(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  claimId: string | null | undefined,
): Promise<HomeownerProfile> {
  const empty: HomeownerProfile = { fullName: "", email: "" };
  if (!claimId) return empty;

  const { data: claimData } = await supabase
    .from("claims")
    .select("user_id")
    .eq("id", claimId)
    .single();

  if (!claimData?.user_id) return empty;

  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name, email")
    .eq("id", claimData.user_id)
    .single();

  return {
    fullName: profile?.full_name ?? "",
    email: profile?.email ?? "",
  };
}
