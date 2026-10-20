import { randomBytes } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import Razorpay from "razorpay";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

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
    const razorpayKeyId = process.env.RAZORPAY_KEY_ID;
    const razorpayKeySecret = process.env.RAZORPAY_KEY_SECRET;
    if (
      !supabaseUrl ||
      !anonKey ||
      !serviceRoleKey ||
      !razorpayKeyId ||
      !razorpayKeySecret
    ) {
      throw new Error("Required server configuration is missing");
    }

    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const {
      data: { user },
      error: authError,
    } = await authClient.auth.getUser(bearerMatch[1]);
    if (authError || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json({ error: "Invalid request" }, { status: 400 });
    }
    const amountRupees =
      typeof body === "object" && body !== null && "amount_rupees" in body
        ? (body as { amount_rupees?: unknown }).amount_rupees
        : undefined;
    if (
      typeof amountRupees !== "number" ||
      !Number.isSafeInteger(amountRupees) ||
      amountRupees < 10 ||
      amountRupees > 5000
    ) {
      return NextResponse.json({ error: "Invalid amount" }, { status: 400 });
    }

    const amountPaise = amountRupees * 100;
    const razorpay = new Razorpay({
      key_id: razorpayKeyId,
      key_secret: razorpayKeySecret,
    });
    const order = await razorpay.orders.create({
      amount: amountPaise,
      currency: "INR",
      receipt: `topup_${randomBytes(16).toString("hex")}`,
      notes: { user_id: user.id },
    });
    if (order.amount !== amountPaise || order.currency !== "INR") {
      throw new Error("Unexpected payment order details");
    }

    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error: insertError } = await serviceClient
      .from("payment_orders")
      .insert({
        user_id: user.id,
        razorpay_order_id: order.id,
        amount_paise: amountPaise,
        status: "created",
      });
    if (insertError) throw insertError;

    return NextResponse.json({
      order_id: order.id,
      key_id: razorpayKeyId,
      amount_paise: order.amount,
    });
  } catch {
    return NextResponse.json(
      { error: "Could not create payment order" },
      { status: 500 },
    );
  }
}
