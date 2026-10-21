import { createHash, randomBytes } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const authorization = request.headers.get("authorization");
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  const supabaseUrl = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!token || !supabaseUrl || !anonKey || !serviceRoleKey) {
    return NextResponse.json({ error: "Could not save recovery code" }, { status: 400 });
  }
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Could not save recovery code" }, { status: 400 });
  }
  const code = (body as { recovery_code?: unknown })?.recovery_code;
  if (typeof code !== "string" || !/^[A-Z0-9]{8}$/.test(code)) {
    return NextResponse.json({ error: "Could not save recovery code" }, { status: 400 });
  }
  try {
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) throw new Error();
    const salt = randomBytes(16).toString("hex");
    const digest = createHash("sha256").update(`${salt}:${code}`).digest("hex");
    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error } = await serviceClient.from("profiles").update({
      recovery_code_hash: `sha256$${salt}$${digest}`,
    }).eq("id", user.id);
    if (error) throw error;
    return NextResponse.json({ saved: true });
  } catch {
    return NextResponse.json({ error: "Could not save recovery code" }, { status: 400 });
  }
}
