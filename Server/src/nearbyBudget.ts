/** Defense in depth, not a replacement for account-wide Google quotas.
 * Supply only the verified remaining allocation for this app. No defaults
 * enable requests, and these ceilings must never be raised by client input.
 */
export interface NearbyBudgetLimits { daily: number; monthly: number }

export function nearbyBudgetDay(now: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(now);
  const value = (type: string) => parts.find(part => part.type === type)!.value;
  return `${value("year")}-${value("month")}-${value("day")}`;
}

/** Reserve BEFORE each upstream attempt, including retries. One conditional
 * SQLite write enforces both limits across concurrent workers and both apps.
 * Database/configuration errors deny the request; no local fallback counter.
 */
export async function reserveNearbyRequest(db: D1Database, limits: NearbyBudgetLimits,
  now = new Date()): Promise<boolean> {
  if (!Number.isInteger(limits.daily) || limits.daily < 1 || limits.daily > 150 ||
      !Number.isInteger(limits.monthly) || limits.monthly < 1 || limits.monthly > 4500 ||
      !Number.isFinite(now.getTime())) return false;
  const day = nearbyBudgetDay(now);
  try {
    const row = await db.prepare(`
      INSERT INTO nearby_request_budget(month, day, month_used, day_used)
      VALUES (?, ?, 1, 1)
      ON CONFLICT(month) DO UPDATE SET
        month_used = month_used + 1,
        day_used = CASE WHEN excluded.day > day THEN 1 ELSE day_used + 1 END,
        day = excluded.day
      WHERE month_used < ? AND excluded.day >= day
        AND (excluded.day > day OR day_used < ?)
      RETURNING month_used
    `).bind(day.slice(0, 7), day, limits.monthly, limits.daily)
      .first<{ month_used: number }>();
    return row !== null;
  } catch { return false; }
}
