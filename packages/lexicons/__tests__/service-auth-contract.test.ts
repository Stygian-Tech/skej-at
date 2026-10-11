import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..", "..", "..");
const read = (path: string) => readFileSync(join(root, path), "utf8");
const routes = [
  ["GET", "at.skej.actor.getSession"],
  ["GET", "at.skej.schedule.list"],
  ["POST", "at.skej.schedule.create"],
  ["POST", "at.skej.schedule.update"],
  ["POST", "at.skej.schedule.cancel"],
] as const;
const docs = read("docs/api/service-auth.md");

describe("external scheduling service-auth contracts", () => {
  test("documents exactly the gateway's narrow method and route boundary", () => {
    const middleware = read("services/skej-api/Sources/SkejGateway/ServiceAuth/ServiceAuthRouteMiddleware.swift");
    const runtime = [...middleware.matchAll(/\(\.(get|post), "\/xrpc\/(at\.skej\.[^"]+)"\)/g)].map(match => [match[1]!.toUpperCase(), match[2]!]);
    expect(runtime).toEqual(routes.map(route => [...route]));
    const documented = [...docs.matchAll(/^\| (GET|POST) \| `\/xrpc\/([^`]+)`/gm)].map(match => [match[1], match[2]]);
    expect(documented).toEqual(runtime);
  });
  test("preserves canonical request schemas and declares service-auth recovery errors", () => {
    for (const [method, nsid] of routes) {
      const schema = JSON.parse(read(`packages/lexicons/${nsid}.json`)).defs.main;
      expect(schema.type).toBe(method === "GET" ? "query" : "procedure");
      expect(schema.errors.map((error: { name: string }) => error.name)).toEqual(expect.arrayContaining(["InvalidServiceAuth", "ActorMismatch", "AccountNeedsReauth", "account_needs_reauth"]));
      if (method === "POST") expect(schema.input.schema.properties.accountDid.format).toBe("did");
      if (nsid.endsWith(".update") || nsid.endsWith(".cancel")) {
        expect(schema.input.schema.required).toContain("rkey");
        expect(schema.errors.map((error: { name: string }) => error.name)).toContain("ScheduleNotEditable");
      }
    }
  });
  test("documents published DID discovery and network configuration without replacing OAuth metadata", () => {
    const router = read("services/skej-api/Sources/SkejGateway/Routes/AppRouter.swift");
    const identity = read("services/skej-api/Sources/SkejGateway/ServiceAuth/SkejServiceIdentity.swift");
    const network = read("services/skej-api/Sources/SkejGateway/Config/SkejATProtoNetwork.swift");
    expect(/router\.get\("\/?\.well-known\/did\.json"\)/.test(router)).toBe(true);
    expect(identity).toContain('"SkejScheduler"');
    expect(network).toContain('"#skej_scheduler"');
    for (const name of ["SKEJ_CORS_ORIGINS", "SKEJ_API_ORIGIN", "SKEJ_DID_WEB_ORIGINS", "SKEJ_LOCAL_PLC_ORIGIN", "SKEJ_LOCAL_HANDLE_RESOLVER_ORIGIN", "SKEJ_LOCAL_PDS_ORIGINS", "SKEJ_LOCAL_DID_WEB_ORIGINS"]) { expect(network).toContain(name); expect(docs).toContain(name); }
    expect(docs).toContain("SKEJ_PUBLIC_ORIGIN");
  });
});
