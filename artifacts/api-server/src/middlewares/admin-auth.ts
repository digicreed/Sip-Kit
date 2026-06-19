import type { Request, Response, NextFunction } from "express";

export function requireAdminKey(req: Request, res: Response, next: NextFunction): void {
  const adminKey = process.env["ADMIN_API_KEY"];
  if (!adminKey) {
    res.status(500).json({ error: "Admin API key not configured" });
    return;
  }

  const authHeader = req.headers["authorization"] ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (!token || token !== adminKey) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }

  next();
}
