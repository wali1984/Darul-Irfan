import { describe, expect, it } from "vitest";
import { cleanText, isUUID, redactDiagnostics, validHTTPURL, validISODate } from "../src/util";
import bootstrapFixture from "./fixtures/bootstrap.json" with { type: "json" };

describe("public input validation", () => {
  it("keeps the shared bootstrap contract fixture on schema v1", () => {
    expect(bootstrapFixture.schemaVersion).toBe(1);
    expect(bootstrapFixture.live.sources[0]?.kind).toBe("youtube");
    expect(bootstrapFixture.schedules[0]?.timeZoneIdentifier).toBe("Asia/Karachi");
  });
  it("normalizes control characters and whitespace", () => expect(cleanText("  Live\n\tZikr  ")).toBe("Live Zikr"));
  it("accepts HTTPS and rejects other URL schemes", () => {
    expect(validHTTPURL("https://example.com/live")).toBe("https://example.com/live");
    expect(validHTTPURL("javascript:alert(1)")).toBeUndefined();
    expect(validHTTPURL("http://example.com")).toBeUndefined();
  });
  it("accepts timezone-qualified ISO dates and rejects ambiguous dates", () => {
    expect(validISODate("2026-07-23T21:15:00+05:00")).toBe("2026-07-23T16:15:00.000Z");
    expect(validISODate("2026-07-23 21:15")).toBeUndefined();
  });
  it("validates installation UUIDs", () => {
    expect(isUUID("550e8400-e29b-41d4-a716-446655440000")).toBe(true);
    expect(isUUID("not-a-device")).toBe(false);
  });
  it("recursively redacts diagnostic identifiers and parses MetricKit JSON", () => {
    const value = redactDiagnostics({
      email: "person@example.com",
      nested: { latitude: 51.5, message: "contact person@example.com" },
      metricKitPayload: JSON.stringify({ diagnostics: [{ phone: "+1 555", safe: true }] }),
    });
    expect(value).toEqual({
      email: "[redacted]",
      nested: { latitude: "[redacted]", message: "contact [redacted-email]" },
      metricKitPayload: { diagnostics: [{ phone: "[redacted]", safe: true }] },
    });
  });
});
