import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const token = request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  const supabaseUrl = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!token || !supabaseUrl || !anonKey || !serviceRoleKey) {
    return NextResponse.json({ error: "Could not complete password reset" }, { status: 400 });
  }
  try {
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) throw new Error();
    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error } = await serviceClient.from("profiles").update({ password_reset_at: new Date().toISOString() }).eq("id", user.id);
    if (error) throw error;
    return NextResponse.json({ saved: true });
  } catch {
    return NextResponse.json({ error: "Could not complete password reset" }, { status: 400 });
  }
}
