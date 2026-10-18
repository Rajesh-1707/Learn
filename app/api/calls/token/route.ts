import { RtcRole, RtcTokenBuilder } from "agora-token";
import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN_LIFETIME_SECONDS = 1800;
const CALL_MAX_AGE_MS = 35 * 60 * 1000;

export async function POST(request: Request) {
  try {
    const authorization = request.headers.get("authorization");
    const bearerMatch = authorization?.match(/^Bearer\s+(.+)$/i);
    if (!bearerMatch) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const supabaseUrl = process.env.SUPABASE_URL;
    const anonKey = process.env.SUPABASE_ANON_KEY;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    const appId = process.env.AGORA_APP_ID;
    const appCertificate = process.env.AGORA_APP_CERTIFICATE;

    if (!supabaseUrl || !anonKey || !serviceRoleKey || !appId || !appCertificate) {
      throw new Error("Required server configuration is missing");
    }

    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: { user }, error: authError } = await authClient.auth.getUser(bearerMatch[1]);
    if (authError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
    }

    const callId = typeof body === "object" && body !== null && "call_id" in body
      ? (body as { call_id?: unknown }).call_id
      : undefined;
    if (typeof callId !== "string" || !UUID_PATTERN.test(callId)) {
      return NextResponse.json({ error: "Invalid call_id" }, { status: 400 });
    }

    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: call, error: callError } = await serviceClient
      .from("calls")
      .select("id, caller_id, receiver_id, status, created_at")
      .eq("id", callId)
      .maybeSingle();

    if (callError) throw callError;
    if (!call) {
      return NextResponse.json({ error: "Call not found" }, { status: 404 });
    }

    if (user.id !== call.caller_id && user.id !== call.receiver_id) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const createdAt = Date.parse(call.created_at);
    if (
      (call.status !== "matched" && call.status !== "connected") ||
      !Number.isFinite(createdAt) ||
      Date.now() - createdAt > CALL_MAX_AGE_MS
    ) {
      return NextResponse.json({ error: "Call is no longer active" }, { status: 409 });
    }

    const uid = user.id === call.caller_id ? 1 : 2;
    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      call.id,
      uid,
      RtcRole.PUBLISHER,
      TOKEN_LIFETIME_SECONDS,
      TOKEN_LIFETIME_SECONDS,
    );

    return NextResponse.json({
      app_id: appId,
      channel: call.id,
      uid,
      token,
      expires_in: TOKEN_LIFETIME_SECONDS,
    });
  } catch {
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
