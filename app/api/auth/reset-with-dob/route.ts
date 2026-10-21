import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

const failure = () => NextResponse.json({ error: "Details do not match" }, { status: 400 });
const validEmail = (value: unknown): value is string =>
  typeof value === "string" && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value);

function codeMatches(value: string, stored: string | null): boolean {
  if (!stored) return false;
  const [algorithm, salt, digest] = stored.split("$");
  if (algorithm !== "sha256" || !salt || !/^[a-f0-9]{64}$/i.test(digest ?? "")) return false;
  const actual = createHash("sha256").update(`${salt}:${value.toUpperCase()}`).digest();
  const expected = Buffer.from(digest, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export async function POST(request: Request) {
  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return failure();
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return failure();
  }
  const input = body as Record<string, unknown>;
  const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
  const newPassword = input.new_password;
  const dob = input.dob;
  const recoveryCode = input.recovery_code;
  const hasDob = typeof dob === "string" && /^\d{4}-\d{2}-\d{2}$/.test(dob);
  const hasCode = typeof recoveryCode === "string" && /^[a-zA-Z0-9]{8}$/.test(recoveryCode);
  if (!validEmail(email) || typeof newPassword !== "string" || newPassword.length < 8 || newPassword.length > 128 || hasDob === hasCode) {
    return failure();
  }

  const ip = request.headers.get("x-vercel-forwarded-for")?.split(",")[0]?.trim()
    ?? request.headers.get("x-real-ip")?.trim()
    ?? request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    ?? "unknown";
  const emailKey = createHmac("sha256", serviceRoleKey).update(`email:${email}`).digest("hex");
  const ipKey = createHmac("sha256", serviceRoleKey).update(`ip:${ip}`).digest("hex");
  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const { data: attemptRows, error: attemptError } = await client.rpc("begin_reset_attempt", {
      p_email_key: emailKey,
      p_ip_key: ipKey,
    });
    if (attemptError) throw attemptError;
    const attempt = Array.isArray(attemptRows) ? attemptRows[0] : null;
    if (!attempt?.allowed || typeof attempt.attempt_id !== "string") return failure();
    const attemptId = attempt.attempt_id;

    const { data: rows, error: lookupError } = await client.rpc("lookup_reset_profile", { p_email: email });
    if (lookupError) throw lookupError;
    const profile = Array.isArray(rows) ? rows[0] : null;
    if (!profile || (profile.reset_locked_until && Date.parse(profile.reset_locked_until) > Date.now())) {
      await client.rpc("finish_reset_attempt", { p_attempt_id: attemptId, p_succeeded: true, p_user_id: profile?.user_id ?? null });
      return failure();
    }

    const matched = hasDob
      ? profile.dob === dob
      : codeMatches(recoveryCode as string, profile.recovery_code_hash ?? null);
    if (!matched) {
      await client.rpc("finish_reset_attempt", { p_attempt_id: attemptId, p_succeeded: false, p_user_id: profile.user_id });
      return failure();
    }

    const { error: passwordError } = await client.auth.admin.updateUserById(profile.user_id, {
      password: newPassword,
    });
    if (passwordError) {
      await client.rpc("finish_reset_attempt", { p_attempt_id: attemptId, p_succeeded: false, p_user_id: profile.user_id });
      return failure();
    }
    const { error: profileError } = await client
      .from("profiles")
      .update({ password_reset_at: new Date().toISOString(), reset_locked_until: null })
      .eq("id", profile.user_id);
    if (profileError) throw profileError;
    await client.rpc("finish_reset_attempt", { p_attempt_id: attemptId, p_succeeded: true, p_user_id: profile.user_id });
    return NextResponse.json({ message: "Password reset successfully. Please log in." });
  } catch {
    return failure();
  }
}
