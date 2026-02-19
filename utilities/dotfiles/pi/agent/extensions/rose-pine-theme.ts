import { exec } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

const execAsync = promisify(exec);
const DARK_THEME = "rose-pine";
const LIGHT_THEME = "rose-pine-dawn";

async function isDarkMode(): Promise<boolean | null> {
  try {
    const { stdout } = await execAsync(
      "osascript -e 'tell application \"System Events\" to tell appearance preferences to return dark mode'",
    );
    const normalized = stdout.trim().toLowerCase();
    if (normalized === "true") return true;
    if (normalized === "false") return false;
    return null;
  } catch {
    return null;
  }
}

async function applyTheme(ctx: ExtensionContext, lastApplied?: string): Promise<string | undefined> {
  if (!ctx.hasUI) return lastApplied;
  const dark = await isDarkMode();
  const target = dark === null ? DARK_THEME : dark ? DARK_THEME : LIGHT_THEME;

  if (target === lastApplied) return lastApplied;

  const result = ctx.ui.setTheme(target);
  if (!result.success) {
    ctx.ui.notify(`Failed to set theme ${target}: ${result.error}`, "warning");
    return lastApplied;
  }
  return target;
}

export default function (pi: ExtensionAPI) {
  let interval: NodeJS.Timeout | null = null;
  let applied: string | undefined;

  pi.on("session_start", async (_event, ctx) => {
    applied = await applyTheme(ctx, applied);

    interval = setInterval(async () => {
      applied = await applyTheme(ctx, applied);
    }, 2500);
  });

  pi.on("session_shutdown", () => {
    if (interval) {
      clearInterval(interval);
      interval = null;
    }
  });
}
