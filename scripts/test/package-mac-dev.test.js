import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);

test("Mac package script declares desktop capture permissions and stable local signing", async () => {
  const script = await readFile(path.join(root, "scripts/package-mac-dev.sh"), "utf8");

  assert.match(script, /NSAccessibilityUsageDescription/u);
  assert.match(script, /NSScreenCaptureUsageDescription/u);
  assert.match(script, /TACKET_CODESIGN_IDENTITY/u);
  assert.match(script, /DEVELOPER_ID_APPLICATION/u);
  assert.match(script, /--options runtime/u);
  assert.match(script, /--entitlements "\$ENTITLEMENTS_PATH"/u);
  assert.match(script, /codesign --force --deep --sign - "\$APP_DIR"/u);
});
