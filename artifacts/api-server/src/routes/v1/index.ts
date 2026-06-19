import { Router } from "express";
import activateRouter from "./activate.js";
import refreshRouter from "./refresh.js";
import usageRouter from "./usage.js";
import publicKeyRouter from "./public-key.js";
import adminProvidersRouter from "./admin/providers.js";
import adminLicensesRouter from "./admin/licenses.js";
import adminSummaryRouter from "./admin/summary.js";

const router = Router();

router.use(activateRouter);
router.use(refreshRouter);
router.use(usageRouter);
router.use(publicKeyRouter);

router.use("/admin", adminProvidersRouter);
router.use("/admin", adminLicensesRouter);
router.use("/admin", adminSummaryRouter);

export default router;
