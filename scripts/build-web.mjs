import { spawnSync } from "node:child_process";
import { cp, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const env = {
  ...process.env,
  CI: "true",
  FLUTTER_SUPPRESS_ANALYTICS: "true",
};

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    env,
    shell: process.platform === "win32",
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

let flutterCommand = "flutter";
if (process.env.VERCEL) {
  const sdkPath = path.join(os.tmpdir(), "flutter-sdk");
  if (!existsSync(path.join(sdkPath, "bin", "flutter"))) {
    run("git", [
      "clone",
      "--depth",
      "1",
      "--branch",
      "stable",
      "https://github.com/flutter/flutter.git",
      sdkPath,
    ]);
  }
  flutterCommand = path.join(
    sdkPath,
    "bin",
    process.platform === "win32" ? "flutter.bat" : "flutter",
  );
}

run(flutterCommand, ["pub", "get"]);
run(flutterCommand, [
  "build",
  "web",
  "--release",
  "--base-href",
  "/flutter/",
]);

const flutterOutput = path.join(root, "build", "web");
const publicOutput = path.join(root, "public", "flutter");
await mkdir(publicOutput, { recursive: true });
await cp(flutterOutput, publicOutput, { recursive: true, force: true });

const nextCommand = path.join(
  root,
  "node_modules",
  ".bin",
  process.platform === "win32" ? "next.cmd" : "next",
);
run(nextCommand, ["build"]);
