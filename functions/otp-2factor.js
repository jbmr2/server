const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

const DEMO_PHONE = "9000000001";
const DEMO_OTP = "123456";
const DEMO_SESSION = "demo-apple-review";

function nationalPhone(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  return digits.length > 10 ? digits.slice(-10) : digits;
}

function apiKey() {
  return String(process.env.TWOFACTOR_API_KEY || "").trim();
}

async function twoFactorGet(path) {
  const key = apiKey();
  if (!key) throw new Error("2Factor API key missing");
  const url = `https://2factor.in/API/V1/${encodeURIComponent(key)}${path}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(20000) });
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, data };
}

async function rateLimit(phone, kind) {
  const db = getFirestore();
  const ref = db.collection("otpAttempts").doc(`${kind}_${phone}`);
  const snap = await ref.get();
  const row = snap.data() || {};
  const now = Date.now();
  const windowMs = 15 * 60 * 1000;
  const count = row.at && now - row.at < windowMs ? row.count || 0 : 0;
  const max = kind === "send" ? 6 : 10;
  if (count >= max) {
    const err = new Error("Too many attempts — try again later");
    err.status = 429;
    throw err;
  }
  await ref.set({ count: count + 1, at: now });
}

async function firebaseSessionForPhone(phone) {
  const e164 = `+91${phone}`;
  const auth = getAuth();
  let user;
  try {
    user = await auth.getUserByPhoneNumber(e164);
  } catch (err) {
    if (err.code !== "auth/user-not-found") throw err;
    user = await auth.createUser({ phoneNumber: e164, disabled: false });
  }
  const token = await auth.createCustomToken(user.uid, { phone: e164 });
  return { uid: user.uid, token, phone };
}

async function handleSendOtp(req, res) {
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, error: "POST required" });
    return;
  }
  const phone = nationalPhone(req.body?.phone);
  if (phone.length !== 10) {
    res.status(400).json({ ok: false, error: "Enter a 10-digit mobile number" });
    return;
  }
  try {
    await rateLimit(phone, "send");
    if (phone === DEMO_PHONE) {
      res.json({ ok: true, sessionId: DEMO_SESSION, demo: true });
      return;
    }
    const { data } = await twoFactorGet(`/SMS/${phone}/AUTOGEN`);
    const status = String(data?.Status || "").toLowerCase();
    const sessionId = String(data?.Details || "");
    if (status !== "success" || !sessionId) {
      res.status(502).json({
        ok: false,
        error: sessionId || "Couldn’t send OTP — try again",
      });
      return;
    }
    res.json({ ok: true, sessionId });
  } catch (err) {
    const code = err.status || 500;
    console.error("sendOtp", err);
    res.status(code).json({ ok: false, error: err.message || String(err) });
  }
}

async function handleVerifyOtp(req, res) {
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, error: "POST required" });
    return;
  }
  const phone = nationalPhone(req.body?.phone);
  const otp = String(req.body?.otp || "").replace(/\D/g, "");
  const sessionId = String(req.body?.sessionId || "").trim();
  if (phone.length !== 10 || otp.length !== 6 || !sessionId) {
    res.status(400).json({ ok: false, error: "Enter the 6-digit OTP" });
    return;
  }
  try {
    await rateLimit(phone, "verify");
    if (phone === DEMO_PHONE) {
      if (otp !== DEMO_OTP || sessionId !== DEMO_SESSION) {
        res.status(401).json({ ok: false, error: "Incorrect OTP — try again" });
        return;
      }
      const session = await firebaseSessionForPhone(phone);
      res.json({ ok: true, ...session });
      return;
    }
    const { data } = await twoFactorGet(
      `/SMS/VERIFY/${encodeURIComponent(sessionId)}/${otp}`
    );
    const status = String(data?.Status || "").toLowerCase();
    if (status !== "success") {
      res.status(401).json({
        ok: false,
        error: String(data?.Details || "Incorrect OTP — try again"),
      });
      return;
    }
    const session = await firebaseSessionForPhone(phone);
    res.json({ ok: true, ...session });
  } catch (err) {
    const code = err.status || 500;
    console.error("verifyOtp", err);
    res.status(code).json({ ok: false, error: err.message || String(err) });
  }
}

module.exports = { handleSendOtp, handleVerifyOtp };
