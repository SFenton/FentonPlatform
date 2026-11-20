import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { validateRoot } from "./check-dependencies.mjs";

const temporaryRoots = [];

test.after(() => {
  for (const root of temporaryRoots) {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "fenton-dependency-check-"));
  temporaryRoots.push(root);
  fs.mkdirSync(path.join(root, "platforms/windows"), { recursive: true });
  fs.mkdirSync(path.join(root, "platforms/android/gradle/wrapper"), { recursive: true });
  fs.mkdirSync(path.join(root, "integrations/dependencies"), { recursive: true });
  fs.writeFileSync(path.join(root, "platforms/android/gradle/wrapper/gradle-wrapper.jar"), "fixture");
  const wrapperHash = crypto.createHash("sha256").update("fixture").digest("hex");
  fs.writeFileSync(path.join(root, "source-license-manifest.json"), JSON.stringify({
    runtime_dependencies: [],
    platform_inventories: ["integrations/dependencies/windows.json", "integrations/dependencies/native.json"],
  }));
  const license = { spdx: "MIT", review_required: false, source_url: "https://licenses.nuget.org/MIT" };
  fs.writeFileSync(path.join(root, "integrations/dependencies/windows.json"), JSON.stringify({
    platform: "windows",
    packages: [{ package: "Fixture.Package", version: "1.0.0", license }],
    review_required: false,
  }));
  fs.writeFileSync(path.join(root, "integrations/dependencies/native.json"), JSON.stringify({
    platform: "android",
    packages: [{ group: "fixture", name: "library", version: "1.0.0", license }],
    tooling: {
      gradle_wrapper: {
        path: "platforms/android/gradle/wrapper/gradle-wrapper.jar",
        sha256: wrapperHash,
      },
      plugins: [{ id: "com.android.application", version: "1.0.0" }],
    },
    review_required: false,
  }));
  fs.writeFileSync(
    path.join(root, "platforms/windows/Fixture.csproj"),
    '<Project><ItemGroup><PackageReference Version="1.0.0" Include="Fixture.Package" /></ItemGroup></Project>',
  );
  fs.writeFileSync(
    path.join(root, "platforms/android/build.gradle.kts"),
    'plugins { id("com.android.application") version "1.0.0" }\ndependencies { implementation("fixture:library") }',
  );
  return root;
}

test("accepts reordered XML attributes and BOM-managed dependencies", () => {
  assert.deepEqual(validateRoot(fixture()), []);
});

test("rejects a new unlisted dependency", () => {
  const root = fixture();
  fs.writeFileSync(
    path.join(root, "platforms/windows/Fixture.csproj"),
    '<Project><ItemGroup><PackageReference Include="Fixture.New" Version="1.0.0" /></ItemGroup></Project>',
  );
  assert.ok(validateRoot(root).some((error) => error.includes("unlisted or drifted Fixture.New@1.0.0")));
});

test("rejects exact-version drift", () => {
  const root = fixture();
  fs.writeFileSync(
    path.join(root, "platforms/android/build.gradle.kts"),
    'plugins { id("com.android.application") version "1.0.0" }\ndependencies { implementation("fixture:library:2.0.0") }',
  );
  assert.ok(validateRoot(root).some((error) => error.includes("unlisted or drifted fixture:library@2.0.0")));
});

test("rejects missing or central XML versions", () => {
  const root = fixture();
  fs.writeFileSync(
    path.join(root, "platforms/windows/Fixture.csproj"),
    '<Project><ItemGroup><PackageReference Include="Fixture.Package" /><PackageReference Include="Fixture.Other"><Version>1.0.0</Version></PackageReference></ItemGroup></Project>',
  );
  const errors = validateRoot(root);
  assert.equal(errors.filter((error) => error.includes("missing explicit Version")).length, 2);
});
