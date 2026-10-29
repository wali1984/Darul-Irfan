/// <reference types="node" />
// A D1 stand-in over Node's built-in SQLite, with every real migration
// applied, so the community rules run against the actual schema and SQL
// rather than a fixture that guesses at it.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

type Value = string | number | null | bigint | Uint8Array;

const clean = (values: unknown[]): Value[] =>
  values.map(value => value === undefined ? null : typeof value === "boolean" ? (value ? 1 : 0) : value as Value);

export function sqliteD1(): { db: D1Database; raw: DatabaseSync } {
  const raw = new DatabaseSync(":memory:");
  const dir = join(__dirname, "..", "migrations");
  for (const file of readdirSync(dir).filter((name: string) => name.endsWith(".sql")).sort()) {
    raw.exec(readFileSync(join(dir, file), "utf8"));
  }
  const db = {
    prepare(sql: string) {
      let bound: Value[] = [];
      const statement = {
        bind(...values: unknown[]) { bound = clean(values); return statement; },
        async first<T>() { return (raw.prepare(sql).get(...bound) ?? null) as T | null; },
        async all<T>() { return { results: raw.prepare(sql).all(...bound) as T[], success: true, meta: {} }; },
        async run() {
          const result = raw.prepare(sql).run(...bound);
          return { success: true, meta: { changes: Number(result.changes) } };
        },
      };
      return statement;
    },
    /** Like D1: the statements run in order as one transaction, and a
     *  failure in any of them undoes them all. */
    async batch(statements: Array<{ run: () => Promise<unknown> }>) {
      raw.exec("BEGIN");
      try {
        const results: unknown[] = [];
        for (const statement of statements) results.push(await statement.run());
        raw.exec("COMMIT");
        return results;
      } catch (error) {
        raw.exec("ROLLBACK");
        throw error;
      }
    },
  };
  return { db: db as unknown as D1Database, raw };
}
