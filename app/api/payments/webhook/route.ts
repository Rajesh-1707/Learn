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
  console.log("[payments.webhook] request received");
  const signatureHeader = request.headers.get("x-razorpay-signature");
  console.log(
    "[payments.webhook] signature header present:",
    Boolean(signatureHeader),
  );

  const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;
  if (!webhookSecret) {
    console.log("[payments.webhook] webhook configuration missing");
    return NextResponse.json(
      { error: "Webhook unavailable" },
      { status: 500 },
    );
  }

  const signature = signatureHeader ?? "";
  let rawBody: string;
  try {
    rawBody = await request.text();
  } catch {
    console.log("[payments.webhook] raw body read failed");
    return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
  }
  if (!/^[a-f0-9]{64}$/i.test(signature)) {
    console.log("[payments.webhook] signature valid: false");
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
    console.log("[payments.webhook] signature valid: false");
    return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
  }
  console.log("[payments.webhook] signature valid: true");

  let webhook: RazorpayWebhook;
  try {
    webhook = JSON.parse(rawBody) as RazorpayWebhook;
  } catch {
    console.log("[payments.webhook] event type unavailable (invalid JSON)");
    return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
  }

  console.log(
    "[payments.webhook] event type:",
    typeof webhook.event === "string" ? webhook.event : "unknown",
  );
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
    console.log(
      "[payments.webhook] order id found:",
      typeof orderId === "string" && Boolean(orderId),
    );
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
    if (!order) {
      console.log("[payments.webhook] payment order record found: false");
      throw new Error("Payment order not found");
    }
    console.log("[payments.webhook] payment order record found: true");
    const userIdFound = typeof order.user_id === "string" && Boolean(order.user_id);
    console.log("[payments.webhook] user id found:", userIdFound);

    if (order.status === "paid") {
      return NextResponse.json({ received: true, processed: true });
    }
    if (
      !userIdFound ||
      !Number.isSafeInteger(order.amount_paise) ||
      amountPaise !== order.amount_paise
    ) {
      return NextResponse.json({ error: "Invalid webhook" }, { status: 400 });
    }

    let creditTopupFailed = false;
    try {
      const { error: creditError } = await serviceClient.rpc("credit_topup", {
        p_user_id: order.user_id,
        p_amount_paise: amountPaise,
        p_payment_id: paymentId,
      });
      creditTopupFailed = Boolean(creditError);
    } catch {
      creditTopupFailed = true;
    }
    if (creditTopupFailed) {
      console.log("[payments.webhook] credit_topup result: error");
      throw new Error("credit_topup failed");
    }
    console.log("[payments.webhook] credit_topup result: success");

    const { error: updateError } = await serviceClient
      .from("payment_orders")
      .update({ status: "paid" })
      .eq("razorpay_order_id", orderId);
    if (updateError) throw updateError;

    return NextResponse.json({ received: true, processed: true });
  } catch {
    console.log("[payments.webhook] processing error");
    return NextResponse.json(
      { error: "Could not process webhook" },
      { status: 500 },
    );
  }
}
