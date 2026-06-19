import type { Request, Response, NextFunction } from "express";
import { verifyEntitlement, type EntitlementClaims } from "../lib/jwt.js";

declare global {
  namespace Express {
    interface Request {
      entitlement?: EntitlementClaims;
    }
  }
}

export function requireEntitlement(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers["authorization"] ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (!token) {
    res.status(401).json({ error: "Missing authorization token" });
    return;
  }

  try {
    req.entitlement = verifyEntitlement(token);
    next();
  } catch {
    res.status(401).json({ error: "Invalid or expired token" });
  }
}
