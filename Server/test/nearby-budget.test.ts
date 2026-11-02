import { describe, expect, it } from "vitest";
import { nearbyBudgetDay, reserveNearbyRequest } from "../src/nearbyBudget";
import { sqliteD1 } from "./sqlite-d1";

describe("shared nearby request budget", () => {
  it("bounds simultaneous callers with the actual migration and conditional SQL", async () => {
    const { db, raw } = sqliteD1();
    try {
      const results = await Promise.all(Array.from({ length: 40 }, () =>
        reserveNearbyRequest(db, { daily: 7, monthly: 10 }, new Date("2026-11-02T12:00:00Z"))));
      expect(results.filter(Boolean)).toHaveLength(7);
      expect(raw.prepare("SELECT month_used,day_used FROM nearby_request_budget").get())
        .toMatchObject({ month_used: 7, day_used: 7 });
    } finally { raw.close(); }
  });
  it("resets days without resetting the month and rejects backward day resets", async () => {
    const { db, raw } = sqliteD1();
    const reserve = (day: number) => reserveNearbyRequest(db, { daily: 2, monthly: 4 },
      new Date(`2026-11-0${day}T12:00:00Z`));
    try {
      expect(await reserve(1)).toBe(true); expect(await reserve(1)).toBe(true);
      expect(await reserve(1)).toBe(false); expect(await reserve(2)).toBe(true);
      expect(await reserve(1)).toBe(false); // Daily rollback denied before monthly exhaustion.
      expect(await reserve(2)).toBe(true); expect(await reserve(3)).toBe(false);
      expect(await reserveNearbyRequest(db, { daily: 2, monthly: 4 }, new Date("2026-12-01T12:00:00Z"))).toBe(true);
    } finally { raw.close(); }
  });
  it("uses Pacific quota boundaries, including daylight saving time", () => {
    expect(nearbyBudgetDay(new Date("2026-07-01T06:59:59Z"))).toBe("2026-06-30");
    expect(nearbyBudgetDay(new Date("2026-07-01T07:00:00Z"))).toBe("2026-07-01");
    expect(nearbyBudgetDay(new Date("2026-12-01T07:59:59Z"))).toBe("2026-11-30");
    expect(nearbyBudgetDay(new Date("2026-12-01T08:00:00Z"))).toBe("2026-12-01");
  });
  it("fails closed on absent database and disabled or oversized allocations", async () => {
    const db = {} as D1Database;
    for (const limits of [{daily:0,monthly:0}, {daily:151,monthly:4500},
      {daily:150,monthly:5000}, {daily:1.5,monthly:20}, {daily:1,monthly:1}]) {
      expect(await reserveNearbyRequest(db, limits)).toBe(false);
    }
  });
});
