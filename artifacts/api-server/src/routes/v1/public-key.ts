import { Router } from "express";
import { getPublicKeyPem, getPublicKeyJwks } from "../../lib/jwt.js";

const router = Router();

router.get("/public-key", (_req, res) => {
  try {
    res.type("text/plain").send(getPublicKeyPem());
  } catch (err) {
    res.status(500).json({ error: "Public key not configured" });
  }
});

router.get("/jwks", (_req, res) => {
  try {
    res.json(getPublicKeyJwks());
  } catch (err) {
    res.status(500).json({ error: "Public key not configured" });
  }
});

export default router;
