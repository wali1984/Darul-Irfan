import { describe, expect, it } from "vitest";
import type { Env } from "../src/contracts";
import { deleteMember } from "../src/members";
import { sqliteD1 } from "./sqlite-d1";

function setup() {
  const { raw, db } = sqliteD1();
  for (const id of ["departing", "remaining"]) {
    raw.prepare("INSERT INTO members(id,apple_subject,display_name,email,created_at,last_seen_at) VALUES(?,?,?,?,?,?)")
      .run(id, id, id, `${id}@example.com`, "now", "now");
    raw.prepare("INSERT INTO member_group_members(group_id,member_id,added_at,added_by,role) VALUES('usa',?,'now','departing','admin')").run(id);
    raw.prepare("INSERT INTO member_sessions(token_hash,member_id,created_at,expires_at,last_seen_at) VALUES(?,?,'now','future','now')").run(id, id);
    raw.prepare("INSERT INTO sheikh_public_profiles(member_id,display_name,city,country_code,contact_email,updated_at) VALUES(?,?,'City','US','unverified@example.com','now')").run(id, id);
    raw.prepare("INSERT INTO group_live_presence(session_id,group_id,member_id,first_seen_at,last_seen_at) VALUES('session','usa',?,'now','now')").run(id);
    raw.prepare("INSERT INTO group_dua_requests(id,group_id,member_id,text,created_at,read_by) VALUES(?,'usa',?,?,'now','departing')").run(id, id, `${id} personal request`);
    raw.prepare("INSERT INTO group_zikr_stages(group_id,id,title,created_by,created_at) VALUES('usa',?,?,?,'now')").run(id, id, id);
    raw.prepare("INSERT INTO group_zikr_cues(group_id,event_id,stage_id,title,author_id,created_at) VALUES('usa',?,'departing','Copied stage title',?,'now')").run(id, id);
    raw.prepare("INSERT INTO group_stage_messages(group_id,id,author_id,body,created_at) VALUES('usa',?,?,?,'now')").run(id, id, `${id} message`);
    raw.prepare("INSERT INTO member_community_consent(member_id,terms_version,accepted_at) VALUES(?,'test','now')").run(id);
    raw.prepare("INSERT INTO community_reports(id,group_id,reporter_id,target_kind,target_id,reason,details,created_at) VALUES(?,'usa',?,'group','usa','privacy',?,'now')")
      .run(id, id, `${id} personal report`);
  }
  return { raw, env: { DB: db } as Env };
}

describe("account deletion against the migrated database", () => {
  it("deletes an author and their private data without deleting other people's content or group access", async () => {
    const { env, raw } = setup();
    expect((await deleteMember(env, "departing")).status).toBe(204);
    expect(raw.prepare("SELECT id FROM members").all()).toEqual([{ id: "remaining" }]);
    for (const table of ["member_sessions", "member_group_members", "sheikh_public_profiles", "group_live_presence", "group_dua_requests", "member_community_consent"]) {
      expect(raw.prepare(`SELECT member_id FROM ${table}`).all(), table).toEqual([{ member_id: "remaining" }]);
    }
    expect(raw.prepare("SELECT reporter_id,details FROM community_reports").all()).toEqual([{ reporter_id: "remaining", details: "remaining personal report" }]);
    expect(raw.prepare("SELECT id,created_by FROM group_zikr_stages").all()).toEqual([{ id: "remaining", created_by: "remaining" }]);
    expect(raw.prepare("SELECT event_id,author_id,title FROM group_zikr_cues").all()).toEqual([{ event_id: "remaining", author_id: "remaining", title: "Copied stage title" }]);
    expect(raw.prepare("SELECT id,author_id FROM group_stage_messages").all()).toEqual([{ id: "remaining", author_id: "remaining" }]);
    expect(raw.prepare("SELECT added_by FROM member_group_members").get()).toEqual({ added_by: "deleted-account" });
    expect(raw.prepare("SELECT read_by FROM group_dua_requests").get()).toEqual({ read_by: null });
    expect(raw.prepare("SELECT id FROM member_groups WHERE id='usa'").get()).toEqual({ id: "usa" });
    expect(raw.prepare("PRAGMA foreign_key_check").all()).toEqual([]);
  });

  it("rolls every deletion back if the final account removal fails", async () => {
    const { env, raw } = setup();
    raw.exec("CREATE TRIGGER reject_account_deletion BEFORE DELETE ON members BEGIN SELECT RAISE(ABORT,'injected storage failure'); END;");
    await expect(deleteMember(env, "departing")).rejects.toThrow("injected storage failure");
    expect(raw.prepare("SELECT id FROM members ORDER BY id").all()).toHaveLength(2);
    expect(raw.prepare("SELECT token_hash FROM member_sessions WHERE member_id='departing'").get()).toEqual({ token_hash: "departing" });
    expect(raw.prepare("SELECT added_by FROM member_group_members WHERE member_id='remaining'").get()).toEqual({ added_by: "departing" });
    expect(raw.prepare("SELECT id FROM group_zikr_stages WHERE id='departing'").get()).toEqual({ id: "departing" });
    expect(raw.prepare("SELECT text FROM group_dua_requests WHERE id='departing'").get()).toEqual({ text: "departing personal request" });
    expect(raw.prepare("SELECT details FROM community_reports WHERE id='departing'").get()).toEqual({ details: "departing personal report" });
  });

  it("removes only the account's claimed or verified-address grants, not an unverified contact's access", async () => {
    const { env, raw } = setup();
    for (const [id, email, claimed] of [["claimed", "old@example.com", "departing"], ["verified", "DEPARTING@example.com", null], ["contact", "unverified@example.com", null], ["other", "departing@example.com", "remaining"]]) {
      raw.prepare("INSERT INTO member_group_grants(id,group_id,email,created_by,created_at,claimed_by) VALUES(?, ?,?,'departing','now',?)")
        .run(id!, id === "other" ? "canada" : "usa", email!, claimed);
    }
    raw.prepare("INSERT INTO member_invites(code_hash,group_id,created_by,created_at,expires_at,redeemed_by) VALUES('redeemed','usa','departing','now','future','departing')").run();
    raw.prepare("INSERT INTO member_invites(code_hash,group_id,created_by,created_at,expires_at) VALUES('unclaimed','usa','departing','now','future')").run();
    await deleteMember(env, "departing");
    expect(raw.prepare("SELECT id,created_by FROM member_group_grants ORDER BY id").all()).toEqual([
      { id: "contact", created_by: "deleted-account" }, { id: "other", created_by: "deleted-account" },
    ]);
    expect(raw.prepare("SELECT code_hash,created_by FROM member_invites").all()).toEqual([{ code_hash: "unclaimed", created_by: "deleted-account" }]);
  });

  it("keeps shared organizational posts and recordings while removing author metadata", async () => {
    const { env, raw } = setup();
    raw.prepare("INSERT INTO member_group_posts(id,group_id,kind,title,body,published_at,author_email,updated_at) VALUES('post','usa','announcement','Shared notice','Shared body','now','member:departing','now')").run();
    raw.prepare("INSERT INTO group_recordings(id,group_id,title,media_key,content_type,byte_size,created_by,created_at) VALUES('recording','usa','Shared recording','shared-key','audio/mpeg',123,'departing','now')").run();
    raw.prepare("INSERT INTO group_live_history(session_id,group_id,kind,title,started_at,started_by,ended_at,ended_by,attendees) VALUES('old','usa','zikr','Shared session','now','departing','now','member:departing',2)").run();
    raw.prepare("INSERT INTO daily_media(id,slot,status,source,created_by,created_at,updated_at,published_by) VALUES('daily','quote','published','upload','member:departing','now','now','member:departing')").run();
    raw.prepare("INSERT INTO audit_log(actor_email,action,entity_type,entity_id,before_json,created_at) VALUES('member:departing','approve','reporting-link','masked','private snapshot','now')").run();
    await deleteMember(env, "departing");
    expect(raw.prepare("SELECT body,author_email FROM member_group_posts WHERE id='post'").get()).toEqual({ body: "Shared body", author_email: "deleted-account" });
    expect(raw.prepare("SELECT media_key,created_by FROM group_recordings").get()).toEqual({ media_key: "shared-key", created_by: "deleted-account" });
    expect(raw.prepare("SELECT started_by,ended_by,attendees FROM group_live_history").get()).toEqual({ started_by: null, ended_by: null, attendees: 2 });
    expect(raw.prepare("SELECT created_by,published_by FROM daily_media").get()).toEqual({ created_by: null, published_by: null });
    expect(raw.prepare("SELECT id FROM audit_log").all()).toEqual([]);
  });

  it("is idempotent and cannot delete another account on retry", async () => {
    const { env, raw } = setup();
    await deleteMember(env, "departing");
    expect((await deleteMember(env, "departing")).status).toBe(204);
    expect(raw.prepare("SELECT id FROM members").all()).toEqual([{ id: "remaining" }]);
  });
});
