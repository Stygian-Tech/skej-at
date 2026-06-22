import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const schemaPath = join(import.meta.dir, "..", "at.skej.schedule.json");

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
              posts: { minLength?: number };
            };
          };
        };
      };
    };

    expect(schema.defs.main.key).toBe("tid");
    expect(schema.defs.main.record.required).toEqual([
      "scheduledFor",
      "createdAt",
      "updatedAt",
      "status",
      "posts",
    ]);
    expect(schema.defs.main.record.properties.posts.minLength).toBe(1);
  });
});

