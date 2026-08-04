import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const schemaPath = join(import.meta.dir, "..", "at.skej.schedule.json");
const permissionLexicons = [
  "at.skej.team",
  "at.skej.team.member",
  "at.skej.team.group",
  "at.skej.team.brandGrant",
  "at.skej.brand",
];

describe("at.skej.schedule lexicon", () => {
  it("parses as a v1 lexicon", () => {
    const schema = JSON.parse(readFileSync(schemaPath, "utf8")) as {
      lexicon?: number;
      id?: string;
      defs?: Record<string, unknown>;
    };

    expect(schema.lexicon).toBe(1);
    expect(schema.id).toBe("at.skej.schedule");
    expect(schema.defs?.main).toBeTruthy();
  });

  it("uses tid keys and requires scheduling fields", () => {
    const schema = JSON.parse(readFileSync(schemaPath, "utf8")) as {
      defs: {
        main: {
          key: string;
          record: {
            required: string[];
            properties: {
              title?: { maxGraphemes?: number };
              teamUri?: { format?: string };
              createdByDid?: { format?: string };
              approvedByDid?: { format?: string };
              approvedAt?: { format?: string };
              scheduledFor?: { description?: string };
              status: { enum: string[] };
              publishRkey: { type: string };
              posts: { minLength?: number };
            };
          };
        };
      };
    };

    expect(schema.defs.main.key).toBe("tid");
    expect(schema.defs.main.record.required).toEqual([
      "scheduledAt",
      "timezonePolicy",
      "createdAt",
      "updatedAt",
      "status",
      "recordType",
      "publishRkey",
      "retry",
      "posts",
    ]);
    expect(schema.defs.main.record.properties.status.enum).toContain("blocked");
    expect(schema.defs.main.record.properties.status.enum).toContain("canceled");
    expect(schema.defs.main.record.properties.title?.maxGraphemes).toBe(120);
    expect(schema.defs.main.record.properties.teamUri?.format).toBe("at-uri");
    expect(schema.defs.main.record.properties.createdByDid?.format).toBe("did");
    expect(schema.defs.main.record.properties.approvedByDid?.format).toBe("did");
    expect(schema.defs.main.record.properties.approvedAt?.format).toBe("datetime");
    expect(schema.defs.main.record.properties.publishRkey.type).toBe("string");
    expect(schema.defs.main.record.properties.scheduledFor?.description).toContain(
      "Deprecated"
    );
    expect(schema.defs.main.record.properties.posts.minLength).toBe(0);
  });
});

describe("Skej permission lexicons", () => {
  for (const id of permissionLexicons) {
    it(`${id} parses as a v1 record lexicon`, () => {
      const schema = JSON.parse(
        readFileSync(join(import.meta.dir, "..", `${id}.json`), "utf8")
      ) as {
        lexicon?: number;
        id?: string;
        defs?: { main?: { type?: string; key?: string; record?: unknown } };
      };

      expect(schema.lexicon).toBe(1);
      expect(schema.id).toBe(id);
      expect(schema.defs?.main?.type).toBe("record");
      expect(schema.defs?.main?.key).toBe("tid");
      expect(schema.defs?.main?.record).toBeTruthy();
    });
  }

  it("brand grants expose the beta capability set", () => {
    const schema = JSON.parse(
      readFileSync(join(import.meta.dir, "..", "at.skej.team.brandGrant.json"), "utf8")
    ) as {
      defs: {
        main: {
          record: {
            properties: {
              capabilities: { items: { enum: string[] } };
            };
          };
        };
      };
    };

    expect(schema.defs.main.record.properties.capabilities.items.enum).toEqual([
      "create",
      "approve",
      "manage",
    ]);
  });
});
