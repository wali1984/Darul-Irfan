import { describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/contracts";

const statement = { bind: () => statement, first: async () => null, all: async () => ({results:[]}) };
const env = { DB: {prepare: () => statement} } as unknown as Env;

describe("public browser routes", () => {
  it("exposes verified live status to the web app", async () => {
    const response=await worker.fetch(new Request("https://api.example.com/v1/live"),env);
    expect(response.status).toBe(200);
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
    expect((await response.json() as {state:string}).state).toBe("offline");
  });
  it("never exposes admin responses through CORS", async () => {
    const response=await worker.fetch(new Request("https://api.example.com/admin/api/state"),env);
    expect(response.status).toBe(401);
    expect(response.headers.has("access-control-allow-origin")).toBe(false);
  });
  it.each(["NaN","Infinity","0","-5","1.2","51"])("rejects malformed feed limit %s", async limit => {
    const response=await worker.fetch(new Request(`https://api.example.com/v1/feed?limit=${limit}`),env);
    expect(response.status).toBe(400);
  });
});
