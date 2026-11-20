import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));

function readJson(root, relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function filesUnder(root, relativeDir, suffix) {
  const directory = path.join(root, relativeDir);
  if (!fs.existsSync(directory)) return [];
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const relative = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) result.push(...filesUnder(root, relative, suffix));
    else if (entry.name.endsWith(suffix)) result.push(relative);
  }
  return result;
}

function packageKey(packageRecord) {
  return packageRecord.group
    ? `${packageRecord.group}:${packageRecord.name}`
    : packageRecord.package;
}

function declaredWindowsPackages(root) {
  const result = [];
  for (const relativePath of filesUnder(root, "platforms/windows", ".csproj")) {
    const text = fs.readFileSync(path.join(root, relativePath), "utf8");
    const pattern = /<PackageReference\b([^>]*)>/g;
    for (const match of text.matchAll(pattern)) {
      const attributes = Object.fromEntries(
        [...match[1].matchAll(/([A-Za-z][A-Za-z0-9]*)\s*=\s*"([^"]*)"/g)]
          .map((attribute) => [attribute[1], attribute[2]]),
      );
      if (!attributes.Include) continue;
      if (!attributes.Version || attributes.Version.includes("$(")) {
        result.push({ source: relativePath, coordinate: attributes.Include, error: "missing explicit Version" });
      } else {
        result.push({ source: relativePath, coordinate: attributes.Include, version: attributes.Version });
      }
    }
  }
  return result;
}

function declaredAndroidPackages(root) {
  const result = [];
  for (const relativePath of filesUnder(root, "platforms/android", ".gradle.kts")) {
    const text = fs.readFileSync(path.join(root, relativePath), "utf8");
    const pattern = /(?:implementation|testImplementation|androidTestImplementation|debugImplementation|compileOnly|runtimeOnly)\(\s*(?:platform\(\s*)?"([^"]+)"/g;
    const matches = [...text.matchAll(pattern)];
    for (const match of text.matchAll(/platform\(\s*"([^"]+)"/g)) matches.push(match);
    for (const match of matches) {
      const parts = match[1].split(":");
      if (parts.length === 3) {
        result.push({ source: relativePath, coordinate: `${parts[0]}:${parts[1]}`, version: parts[2] });
      } else if (parts.length === 2) {
        result.push({ source: relativePath, coordinate: `${parts[0]}:${parts[1]}` });
      }
    }
  }
  return result;
}

function declaredPlugins(root) {
  const text = fs.readFileSync(path.join(root, "platforms/android/build.gradle.kts"), "utf8");
  const result = [];
  const pattern = /id\("([^"]+)"\)\s+version\s+"([^"]+)"/g;
  for (const match of text.matchAll(pattern)) {
    result.push({ id: match[1], version: match[2] });
  }
  return result;
}

function validateReviewMarkers(inventory, errors) {
  for (const record of inventory.packages ?? []) {
    const license = record.license;
    if (!license || typeof license !== "object") {
      errors.push(`${inventory.platform}: ${packageKey(record)} has no license record`);
      continue;
    }
    if (license.review_required) {
      if (!String(license.id ?? "").startsWith("LicenseRef-")) {
        errors.push(`${inventory.platform}: ${packageKey(record)} review item lacks LicenseRef-*`);
      }
      if (!license.source_url || !license.reason) {
        errors.push(`${inventory.platform}: ${packageKey(record)} review item lacks source_url/reason`);
      }
    } else if (!license.spdx) {
      errors.push(`${inventory.platform}: ${packageKey(record)} has no observed SPDX identifier`);
    }
  }
}

export function validateRoot(root) {
  const errors = [];
  const manifest = readJson(root, "source-license-manifest.json");
  const inventoryPaths = manifest.platform_inventories ?? [];
  const inventories = inventoryPaths.map((relativePath) => readJson(root, relativePath));
  const byPlatform = new Map(inventories.map((inventory) => [inventory.platform, inventory]));

  if (manifest.runtime_dependencies?.length !== 0) {
    errors.push("portable runtime_dependencies must remain standard-library-only");
  }
  for (const inventory of inventories) {
    if (!Array.isArray(inventory.packages)) errors.push(`${inventory.platform}: packages is not an array`);
    validateReviewMarkers(inventory, errors);
    if (inventory.review_required === undefined) {
      errors.push(`${inventory.platform}: missing review_required summary`);
    }
  }

  const windows = byPlatform.get("windows");
  const android = byPlatform.get("android");
  const windowsPackages = new Map((windows?.packages ?? []).map((record) => [`${record.package}@${record.version}`, record]));
  const androidPackages = new Map((android?.packages ?? []).map((record) => [`${record.group}:${record.name}@${record.version}`, record]));

  for (const declared of declaredWindowsPackages(root)) {
    if (declared.error) {
      errors.push(`windows: ${declared.error} for ${declared.coordinate} (${declared.source})`);
      continue;
    }
    if (!windowsPackages.has(`${declared.coordinate}@${declared.version}`)) {
      errors.push(`windows: unlisted or drifted ${declared.coordinate}@${declared.version} (${declared.source})`);
    }
  }
  for (const declared of declaredAndroidPackages(root)) {
    const listed = declared.version
      ? androidPackages.has(`${declared.coordinate}@${declared.version}`)
      : [...androidPackages.keys()].some((key) => key.startsWith(`${declared.coordinate}@`));
    if (!listed) {
      const suffix = declared.version ? `@${declared.version}` : " (BOM-managed version)";
      errors.push(`android: unlisted or drifted ${declared.coordinate}${suffix} (${declared.source})`);
    }
  }

  const plugins = new Map((android?.tooling?.plugins ?? []).map((plugin) => [`${plugin.id}@${plugin.version}`, plugin]));
  for (const declared of declaredPlugins(root)) {
    if (!plugins.has(`${declared.id}@${declared.version}`)) {
      errors.push(`android: unlisted or drifted plugin ${declared.id}@${declared.version}`);
    }
  }

  const wrapper = android?.tooling?.gradle_wrapper;
  if (!wrapper?.path || !wrapper.sha256) {
    errors.push("android: missing Gradle wrapper hash");
  } else {
    const wrapperPath = path.join(root, wrapper.path);
    if (!fs.existsSync(wrapperPath)) {
      errors.push(`android: missing wrapper ${wrapper.path}`);
    } else {
      const actual = crypto.createHash("sha256").update(fs.readFileSync(wrapperPath)).digest("hex");
      if (actual !== wrapper.sha256) errors.push(`android: Gradle wrapper hash drift (${wrapper.path})`);
    }
  }

  return errors;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.join(scriptDir, "check-dependencies.mjs")) {
  const root = path.resolve(process.argv[2] ?? path.join(scriptDir, ".."));
  const errors = validateRoot(root);
  if (errors.length) {
    console.error(errors.map((error) => `dependency-check: ${error}`).join("\n"));
    process.exitCode = 1;
  } else {
    console.log("dependency-check: pass");
  }
}
