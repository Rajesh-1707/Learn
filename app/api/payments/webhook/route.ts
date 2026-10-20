import { createHmac, timingSafeEqual } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

type RazorpayWebhook = {
  event?: unknown;
  payload?: {
    payment?: {
      entity?: unknown;
    };
  };
};

type RazorpayPayment = {
  id?: unknown;
  order_id?: unknown;
  amount?: unknown;
  currency?: unknown;
  status?: unknown;
};

export async function POST(request: Request) {
  const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;
  if (!webhookSecret) {
    return NextResponse.json(
      { error: "Webhook unavailable" },
      { status: 500 },
    );
  }

  const signature = request.headers.get("x-razorpay-signature") ?? "";
  let rawBody: string;
  try {
    rawBody = await request.text();
  } catch {
    return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
  }
  if (!/^[a-f0-9]{64}$/i.test(signature)) {
    return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
  }
  const expected = createHmac("sha256", webhookSecret)
    .update(rawBody, "utf8")
    .digest();
  const received = Buffer.from(signature, "hex");
  if (
    received.length !== expected.length ||
    !timingSafeEqual(received, expected)
  ) {
    return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
  }

  let webhook: RazorpayWebhook;
  try {
    webhook = JSON.parse(rawBody) as RazorpayWebhook;
  } catch {
    return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
  }

  if (webhook.event !== "payment.captured") {
    return NextResponse.json({ received: true });
  }

  try {
    const supabaseUrl = process.env.SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Required server configuration is missing");
    }

    const payment = webhook.payload?.payment?.entity as
      | RazorpayPayment
      | undefined;
    const paymentId = payment?.id;
    const orderId = payment?.order_id;
    const amountPaise = payment?.amount;
    if (
      typeof paymentId !== "string" ||
      !paymentId ||
      typeof orderId !== "string" ||
      !orderId ||
      typeof amountPaise !== "number" ||
      !Number.isSafeInteger(amountPaise) ||
      amountPaise <= 0 ||
      payment?.currency !== "INR" ||
      payment?.status !== "captured"
    ) {
      return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
    }

    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: order, error: orderError } = await serviceClient
      .from("payment_orders")
      .select("user_id, amount_paise, status")
      .eq("razorpay_order_id", orderId)
      .maybeSingle();
    if (orderError) throw orderError;
    if (!order) throw new Error("Payment order not found");

    if (order.status === "paid") {
      return NextResponse.json({ received: true, processed: true });
    }
    if (
      typeof order.user_id !== "string" ||
      !Number.isSafeInteger(order.amount_paise) ||
      amountPaise !== order.amount_paise
    ) {
      return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
    }

    const { error: creditError } = await serviceClient.rpc("credit_topup", {
      p_user_id: order.user_id,
      p_amount_paise: amountPaise,
      p_payment_id: paymentId,
    });
    if (creditError) throw creditError;

    const { error: updateError } = await serviceClient
      .from("payment_orders")
      .update({ status: "paid" })
      .eq("razorpay_order_id", orderId);
    if (updateError) throw updateError;

    return NextResponse.json({ received: true, processed: true });
  } catch {
    return NextResponse.json(
      { error: "Could not process webhook" },
      { status: 500 },
    );
  }
}
