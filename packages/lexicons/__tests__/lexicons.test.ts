import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const schemaPath = join(import.meta.dir, "..", "at.skej.schedule.json");
const socialMarkdownFixturePath = join(
  import.meta.dir,
  "..",
  "..",
  "..",
  "test-fixtures",
  "social-markdown.json"
);
const permissionLexicons = [
  "at.skej.team",
  "at.skej.team.member",
  "at.skej.team.group",
  "at.skej.team.brandGrant",
  "at.skej.brand",
];
const xrpcLexicons = [
  "at.skej.actor.getSession",
  "at.skej.auth.logout",
  "at.skej.account.list",
  "at.skej.team.list",
  "at.skej.team.get",
  "at.skej.team.create",
  "at.skej.team.update",
  "at.skej.team.transferOwner",
  "at.skej.team.listMembers",
  "at.skej.team.putMember",
  "at.skej.team.listGroups",
  "at.skej.team.putGroup",
  "at.skej.team.listBrandGrants",
  "at.skej.team.putBrandGrant",
  "at.skej.team.listBrands",
  "at.skej.team.putBrand",
  "at.skej.brand.getProfile",
  "at.skej.brand.updateProfile",
  "at.skej.schedule.list",
  "at.skej.schedule.create",
  "at.skej.schedule.update",
  "at.skej.schedule.cancel",
  "at.skej.schedule.retry",
  "at.skej.schedule.duplicate",
  "at.skej.schedule.publishNow",
  "at.skej.schedule.recordView",
  "at.skej.preview.createLink",
  "at.skej.audit.list",
  "at.skej.dev.seed",
] as const;

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

  it("declares backward-compatible social Markdown and thread publication fields", () => {
    const schema = JSON.parse(readFileSync(schemaPath, "utf8")) as {
      defs: {
        main: {
          record: {
            required: string[];
            properties: {
              publishRkey: { type: string };
              publishedUri: { format: string };
              publishedCid: { type: string };
              publishedPosts: {
                maxLength: number;
                items: { ref: string };
              };
            };
          };
        };
        postPlan: {
          required: string[];
          properties: {
            text: { maxGraphemes: number };
            source: { ref: string };
            publishRkey: { minLength: number };
          };
        };
        postSource: {
          required: string[];
          properties: {
            format: { enum: string[] };
            text: { maxLength: number };
          };
        };
        dependency: {
          properties: {
            relationship: { enum: string[] };
            parentPublishedCid: { format: string };
          };
        };
        publishedPost: {
          required: string[];
          properties: {
            rkey: { minLength: number };
            uri: { format: string };
            cid: { format: string };
          };
        };
      };
    };

    expect(schema.defs.postPlan.required).toEqual(["text"]);
    expect(schema.defs.postPlan.properties.text.maxGraphemes).toBe(300);
    expect(schema.defs.postPlan.properties.source.ref).toBe("#postSource");
    expect(schema.defs.postPlan.properties.publishRkey.minLength).toBe(1);
    expect(schema.defs.postSource.required).toEqual(["format", "text"]);
    expect(schema.defs.postSource.properties.format.enum).toEqual(["markdown"]);
    expect(schema.defs.dependency.properties.relationship.enum).toEqual([
      "after",
      "reply",
      "quote",
    ]);
    expect(schema.defs.dependency.properties.parentPublishedCid.format).toBe("cid");
    expect(schema.defs.publishedPost.required).toEqual(["rkey", "uri", "cid"]);
    expect(schema.defs.main.record.properties.publishedPosts.items.ref).toBe(
      "#publishedPost"
    );

    for (const field of ["source", "publishRkey"] as const) {
      expect(schema.defs.postPlan.required).not.toContain(field);
    }
    expect(schema.defs.main.record.required).not.toContain("publishedPosts");
    expect(schema.defs.main.record.properties.publishRkey.type).toBe("string");
    expect(schema.defs.main.record.properties.publishedUri.format).toBe("at-uri");
    expect(schema.defs.main.record.properties.publishedCid.type).toBe("string");
  });
});

describe("social Markdown golden corpus", () => {
  it("defines unique portable cases and projection boundaries", () => {
    const fixture = JSON.parse(
      readFileSync(socialMarkdownFixturePath, "utf8")
    ) as {
      profile: string;
      cases: Array<{
        name: string;
        source: string;
        text: string;
        graphemeCount?: number;
        valid?: boolean;
        facets: Array<{
          byteStart: number;
          byteEnd: number;
          type: "link" | "tag";
          value: string;
        }>;
      }>;
    };

    expect(fixture.profile).toBe("skej.social-markdown.v1");
    expect(new Set(fixture.cases.map((entry) => entry.name)).size).toBe(
      fixture.cases.length
    );
    expect(fixture.cases.find((entry) => entry.name === "structural-cues-and-crlf")?.text)
      .toStartWith("› ");

    const boundaries = fixture.cases.filter(
      (entry) => entry.graphemeCount !== undefined
    );
    expect(boundaries.map((entry) => [entry.graphemeCount, entry.valid])).toEqual([
      [300, true],
      [301, false],
    ]);
    for (const entry of fixture.cases) {
      for (const facet of entry.facets) {
        expect(facet.byteStart).toBeLessThan(facet.byteEnd);
        expect(["link", "tag"]).toContain(facet.type);
      }
    }
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

describe("Skej XRPC lexicons", () => {
  for (const id of xrpcLexicons) {
    it(`${id} declares a query or procedure contract`, () => {
      const schema = JSON.parse(
        readFileSync(join(import.meta.dir, "..", `${id}.json`), "utf8")
      ) as {
        lexicon?: number;
        id?: string;
        defs?: {
          main?: {
            type?: string;
            output?: { encoding?: string; schema?: unknown };
            input?: { encoding?: string; schema?: unknown };
            parameters?: unknown;
          };
        };
      };

      expect(schema.lexicon).toBe(1);
      expect(schema.id).toBe(id);
      expect(["query", "procedure"]).toContain(schema.defs?.main?.type);
      expect(schema.defs?.main?.output?.encoding).toBe("application/json");
      expect(schema.defs?.main?.output?.schema).toBeTruthy();
      if (schema.defs?.main?.type === "query") {
        expect(schema.defs.main.parameters).toBeTruthy();
      } else {
        expect(schema.defs?.main?.input?.encoding).toBe("application/json");
        expect(schema.defs?.main?.input?.schema).toBeTruthy();
      }
    });
  }
});
