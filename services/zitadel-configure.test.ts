import { deepStrictEqual, rejects } from "node:assert/strict";
import {
  convergeSamlApps,
  type DesiredState,
  type ProjectSpec,
  type SamlAppClient,
  ZitadelClient,
} from "./zitadel-configure.ts";

type Call = [method: string, ...args: unknown[]];

class FakeClient implements SamlAppClient {
  readonly calls: Call[] = [];

  constructor(
    private readonly existingApps: Record<string, string>,
    private readonly failingApps: Set<string> = new Set(),
  ) {}

  searchProjects(name: string) {
    return Promise.resolve([{ id: `project-${name}`, name }]);
  }

  getProject(id: string) {
    return Promise.resolve({ name: id, projectRoleAssertion: true });
  }

  updateProject(id: string) {
    this.calls.push(["updateProject", id]);
    return Promise.resolve();
  }

  createProject(name: string) {
    this.calls.push(["createProject", name]);
    return Promise.resolve(`project-${name}`);
  }

  searchApps(_projectId: string, name: string) {
    if (this.failingApps.has(name)) return Promise.reject(new Error(`${name} is down`));
    const id = this.existingApps[name];
    return Promise.resolve(id === undefined ? [] : [{ id, name }]);
  }

  createSAMLApp(projectId: string, app: { name: string; metadataUrl: string }) {
    this.calls.push(["createSAMLApp", projectId, app]);
    return Promise.resolve();
  }

  updateSAMLAppConfig(projectId: string, appId: string, config: { metadataUrl: string }) {
    this.calls.push(["updateSAMLAppConfig", projectId, appId, config]);
    return Promise.resolve();
  }
}

function project(samlApps: string[]): ProjectSpec {
  return {
    apps: {},
    samlApps: Object.fromEntries(samlApps.map((name) => [name, { metadataUrl: `https://${name}/metadata` }])),
    roles: {},
    userGrants: {},
  };
}

function spec(projects: Record<string, string[]>): Pick<DesiredState, "projects"> {
  return { projects: Object.fromEntries(Object.entries(projects).map(([name, apps]) => [name, project(apps)])) };
}

Deno.test("updates a registered SAML app and creates a missing one", async () => {
  const client = new FakeClient({ cms: "app-1" });
  await convergeSamlApps(client, spec({ site: ["cms", "app"] }));
  deepStrictEqual(client.calls, [
    ["updateSAMLAppConfig", "project-site", "app-1", { metadataUrl: "https://cms/metadata" }],
    ["createSAMLApp", "project-site", { name: "app", metadataUrl: "https://app/metadata" }],
  ]);
});

Deno.test("skips a project without SAML apps", async () => {
  const client = new FakeClient({});
  await convergeSamlApps(client, spec({ other: [] }));
  deepStrictEqual(client.calls, []);
});

Deno.test("tries every SAML app and names exactly the failed ones", async () => {
  const client = new FakeClient({}, new Set(["cms", "admin"]));
  await rejects(
    convergeSamlApps(client, spec({ site: ["cms", "app"], tools: ["admin"] })),
    { message: "SAML apps not converged: cms in site, admin in tools" },
  );
  deepStrictEqual(client.calls, [
    ["createSAMLApp", "project-site", { name: "app", metadataUrl: "https://app/metadata" }],
  ]);
});

Deno.test("treats an update without changes as converged", async () => {
  const fetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(new Response('{"code":9,"message":"No changes"}', { status: 400 }));
  try {
    const client = new ZitadelClient("http://zitadel", "token");
    await client.updateSAMLAppConfig("project", "app", { metadataUrl: "https://cms/metadata" });
  } finally {
    globalThis.fetch = fetch;
  }
});
