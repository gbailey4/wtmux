#!/usr/bin/env python3
"""WTMux MCP server for Claude Code on remote machines.

Implements the Model Context Protocol (JSON-RPC 2.0 over stdin/stdout)
with three tools: analyze_project, configure_project, get_project_config.

Zero external dependencies. Requires Python 3.6+.
"""

__version__ = "1.0.0"

import json
import os
import re
import subprocess
import sys

# ---------------------------------------------------------------------------
# MCP Protocol
# ---------------------------------------------------------------------------

SERVER_NAME = "wtmux"
SERVER_VERSION = __version__

SERVER_INSTRUCTIONS = """\
WTMux project configuration server. Use these tools to set up projects \
for the WTMux git worktree manager.

## Workflow

Follow this conversational flow — never skip straight to configure_project:

1. **Analyze** — Call `analyze_project` with the repo path. This scans for \
env files, package manager, scripts, and default branch.

2. **Present & Ask** — Show the analysis results to the user, grouped clearly:
   - **Env files** found on disk (ask if any should be removed or if others are missing)
   - **Package manager** and setup command (ask if correct)
   - **Runners** grouped by category:
     - `devServer` scripts are suggested as **default** runners (autoStart: true)
     - `build`, `test`, `lint`, and `other` scripts are shown but NOT automatically \
       included as runners — ask the user which (if any) they want added as optional runners
     - Not every script needs to be a runner. Let the user decide.
   - **Default branch** (ask if correct)
   - **Terminal start command** (ask if they want one, e.g. `claude`)

3. **Refine** — Iterate on user feedback: add/remove runners, change default \
vs optional, adjust ports, add custom runners not in package.json, etc.

4. **Configure** — Once the user confirms, call `configure_project` with the \
finalized settings.

## Rules

- The `analyze_project` results are authoritative for env files — NEVER guess \
env files by checking git remote, git ls-files, .gitignore, or any other means.
- ALWAYS present findings to the user before calling `configure_project`. \
Never configure without user review.
- If the project already has a `.wtmux/config.json` (returned in the analysis \
as `existingConfig`), show what's currently configured and ask what they'd like \
to change rather than starting from scratch."""

TOOL_DEFINITIONS = [
    {
        "name": "analyze_project",
        "description": (
            "Scan a git repository to detect its project structure: env files, "
            "package manager, scripts (with categories), and default branch. "
            "Returns a structured analysis to present to the user before configuring."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "repoPath": {
                    "type": "string",
                    "description": "Absolute path to the git repository root",
                },
            },
            "required": ["repoPath"],
        },
    },
    {
        "name": "configure_project",
        "description": (
            "Configure a project for WTMux by writing .wtmux/config.json "
            "and importing it into the app. Provide setup commands (e.g. npm install), "
            "run configurations (dev servers, watchers), env files to copy between "
            "worktrees, and an optional terminal start command. The project will "
            "automatically appear in WTMux's sidebar."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "repoPath": {
                    "type": "string",
                    "description": "Absolute path to the git repository root",
                },
                "envFilesToCopy": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": (
                        "Relative paths to env files to copy to new worktrees (e.g. .env, .env.local). "
                        "IMPORTANT: Only include files that actually exist on the local filesystem. "
                        "Do NOT check git remote, git ls-files, or .gitignore to guess env file names. "
                        "If you haven't confirmed a file exists locally, do not include it."
                    ),
                },
                "setupCommands": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Commands to run when setting up a new worktree (e.g. npm install, bundle install)",
                },
                "runConfigurations": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "Display name for this runner (e.g. 'Dev Server', 'Tailwind')",
                            },
                            "command": {
                                "type": "string",
                                "description": "Shell command to run (e.g. 'npm run dev', 'cargo watch')",
                            },
                            "port": {
                                "type": "integer",
                                "description": "Port number this service listens on, if any",
                            },
                            "autoStart": {
                                "type": "boolean",
                                "description": (
                                    "Whether this is a default runner (included in Start Default and "
                                    "auto-launched when the runner panel opens). Optional runners (false) "
                                    "must be started individually."
                                ),
                            },
                            "order": {
                                "type": "integer",
                                "description": "Sort order for display (lower numbers appear first)",
                            },
                        },
                        "required": ["name", "command"],
                    },
                    "description": "Dev server and process runner configurations",
                },
                "terminalStartCommand": {
                    "type": "string",
                    "description": "Command to run when opening a new terminal in a worktree",
                },
                "startClaudeInTerminals": {
                    "type": "boolean",
                    "description": (
                        "If true, automatically start Claude Code in new terminal tabs. "
                        "Sets terminalStartCommand to 'claude'."
                    ),
                },
                "projectName": {
                    "type": "string",
                    "description": "Display name for the project (defaults to repo directory name)",
                },
                "defaultBranch": {
                    "type": "string",
                    "description": "Default branch name (defaults to 'main')",
                },
                "worktreeBasePath": {
                    "type": "string",
                    "description": "Directory where worktrees will be created (defaults to '<repoPath>-worktrees')",
                },
            },
            "required": ["repoPath"],
        },
    },
    {
        "name": "get_project_config",
        "description": (
            "Read the current .wtmux/config.json for a project. Returns the "
            "configuration if it exists, or a message indicating the project is not "
            "yet configured."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "repoPath": {
                    "type": "string",
                    "description": "Absolute path to the git repository root",
                },
            },
            "required": ["repoPath"],
        },
    },
]


def send_response(obj):
    """Write a JSON-RPC response to stdout."""
    line = json.dumps(obj, separators=(",", ":"))
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def error_result(text):
    """Return an MCP tool error result."""
    return {"content": [{"type": "text", "text": text}], "isError": True}


def text_result(text):
    """Return an MCP tool success result."""
    return {"content": [{"type": "text", "text": text}]}


# ---------------------------------------------------------------------------
# Env File Scanner
# ---------------------------------------------------------------------------

SKIP_DIRS = {
    "node_modules", ".git", "vendor", ".build",
    "DerivedData", ".svn", ".hg", "Pods", "Carthage",
    ".swiftpm", "build", "dist", ".next", ".nuxt",
}
MAX_DEPTH = 5


def is_env_file(name):
    """Check if a filename matches env file patterns."""
    return name.startswith(".env") or name.endswith(".env")


def scan_env_files(repo_path):
    """Recursively scan for env files, returning paths relative to repo root."""
    results = []
    repo_path = os.path.abspath(repo_path)

    def scan_dir(dirpath, depth):
        if depth > MAX_DEPTH:
            return
        try:
            entries = os.listdir(dirpath)
        except OSError:
            return
        for name in entries:
            full = os.path.join(dirpath, name)
            if os.path.isdir(full):
                if name not in SKIP_DIRS and not name.startswith("."):
                    scan_dir(full, depth + 1)
            elif os.path.isfile(full) and is_env_file(name):
                rel = os.path.relpath(full, repo_path)
                if rel not in results:
                    results.append(rel)

    scan_dir(repo_path, 0)
    results.sort()
    return results


# ---------------------------------------------------------------------------
# Package Manager Detection
# ---------------------------------------------------------------------------

PACKAGE_MANAGER_CANDIDATES = [
    ("package.json", "bun.lockb", "bun", "bun install"),
    ("package.json", "bun.lock", "bun", "bun install"),
    ("package.json", "pnpm-lock.yaml", "pnpm", "pnpm install"),
    ("package.json", "yarn.lock", "yarn", "yarn install"),
    ("package.json", None, "npm", "npm install"),
    ("Gemfile", None, "bundler", "bundle install"),
    ("requirements.txt", None, "pip", "pip install -r requirements.txt"),
    ("pyproject.toml", None, "pip", "pip install -e ."),
    ("composer.json", None, "composer", "composer install"),
    ("Cargo.toml", None, "cargo", "cargo build"),
    ("go.mod", None, "go", "go mod download"),
    ("Package.swift", None, "swift", "swift package resolve"),
    ("Podfile", None, "cocoapods", "pod install"),
]


def detect_package_manager(repo_path):
    """Detect the project's package manager."""
    for manifest, lock_file, name, setup_cmd in PACKAGE_MANAGER_CANDIDATES:
        manifest_path = os.path.join(repo_path, manifest)
        if not os.path.isfile(manifest_path):
            continue
        if lock_file is not None:
            lock_path = os.path.join(repo_path, lock_file)
            if not os.path.isfile(lock_path):
                continue
            return {"name": name, "setupCommand": setup_cmd, "lockFile": lock_file}
        else:
            return {"name": name, "setupCommand": setup_cmd, "lockFile": None}
    return None


# ---------------------------------------------------------------------------
# Script Parsing
# ---------------------------------------------------------------------------

JS_MANAGERS = {"npm", "yarn", "pnpm", "bun"}

DEV_NAME_PATTERNS = ["dev", "start", "serve", "watch"]
DEV_CMD_PATTERNS = [
    "vite", "next dev", "nodemon", "webpack serve", "webpack-dev-server",
    "ts-node-dev", "tsx watch", "nuxt dev", "remix dev", "astro dev",
]
BUILD_PATTERNS = ["build", "compile", "bundle"]
TEST_PATTERNS = ["test", "e2e", "cypress", "vitest", "playwright"]
LINT_PATTERNS = ["lint", "format", "check", "prettier", "typecheck", "type-check"]

CATEGORY_ORDER = {"devServer": 0, "build": 1, "test": 2, "lint": 3, "other": 4}


def categorize_script(name, command):
    """Categorize a package.json script."""
    lower_name = name.lower()
    lower_cmd = command.lower()

    if any(p in lower_name for p in DEV_NAME_PATTERNS) or any(p in lower_cmd for p in DEV_CMD_PATTERNS):
        return "devServer"
    if any(p in lower_name for p in BUILD_PATTERNS):
        return "build"
    if any(p in lower_name for p in TEST_PATTERNS):
        return "test"
    if any(p in lower_name for p in LINT_PATTERNS):
        return "lint"
    return "other"


def parse_scripts(repo_path, package_manager):
    """Parse package.json scripts if applicable."""
    if not package_manager or package_manager["name"] not in JS_MANAGERS:
        return []

    pkg_path = os.path.join(repo_path, "package.json")
    try:
        with open(pkg_path, "r") as f:
            pkg = json.load(f)
    except (OSError, json.JSONDecodeError):
        return []

    scripts = pkg.get("scripts")
    if not isinstance(scripts, dict):
        return []

    pm_name = package_manager["name"]
    run_prefix = {
        "npm": "npm run",
        "yarn": "yarn",
        "pnpm": "pnpm run",
        "bun": "bun run",
    }.get(pm_name, "{} run".format(pm_name))

    result = []
    for name, command in scripts.items():
        category = categorize_script(name, command)
        result.append({
            "name": name,
            "command": command,
            "runCommand": "{} {}".format(run_prefix, name),
            "category": category,
        })

    result.sort(key=lambda s: (CATEGORY_ORDER.get(s["category"], 4), s["name"]))
    return result


# ---------------------------------------------------------------------------
# Default Branch Detection
# ---------------------------------------------------------------------------

def run_git(args, cwd):
    """Run a git command and return stdout or None on failure."""
    try:
        result = subprocess.run(
            ["git"] + args,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return None
        return result.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None


def detect_default_branch(repo_path):
    """Detect the default branch of a git repository."""
    output = run_git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], repo_path)
    if output:
        parts = output.split("/", 1)
        if len(parts) == 2:
            return parts[1]
        return output

    for name in ("main", "master"):
        if run_git(["rev-parse", "--verify", name], repo_path) is not None:
            return name

    return None


# ---------------------------------------------------------------------------
# Config Service
# ---------------------------------------------------------------------------

CONFIG_DIR = ".wtmux"
CONFIG_FILE = "config.json"


def read_config(repo_path):
    """Read .wtmux/config.json from a repo path."""
    config_path = os.path.join(repo_path, CONFIG_DIR, CONFIG_FILE)
    try:
        with open(config_path, "r") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def write_config(repo_path, config):
    """Write .wtmux/config.json into a repo path."""
    dir_path = os.path.join(repo_path, CONFIG_DIR)
    os.makedirs(dir_path, exist_ok=True)
    config_path = os.path.join(dir_path, CONFIG_FILE)
    tmp_path = config_path + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(config, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp_path, config_path)


def ensure_gitignore(repo_path):
    """Ensure .wtmux is in .gitignore. Returns True if newly added."""
    gitignore_path = os.path.join(repo_path, ".gitignore")
    contents = ""
    if os.path.isfile(gitignore_path):
        with open(gitignore_path, "r") as f:
            contents = f.read()

    lines = contents.split("\n")
    for line in lines:
        trimmed = line.strip()
        if trimmed in (".wtmux", ".wtmux/"):
            return False

    suffix = "" if contents.endswith("\n") else "\n"
    contents += suffix + ".wtmux\n"
    with open(gitignore_path, "w") as f:
        f.write(contents)
    return True


# ---------------------------------------------------------------------------
# Tool Handlers
# ---------------------------------------------------------------------------

def handle_analyze_project(arguments):
    """Handle the analyze_project tool call."""
    repo_path = (arguments or {}).get("repoPath")
    if not repo_path:
        return error_result("Missing required parameter: repoPath")
    if not repo_path.startswith("/"):
        return error_result("repoPath must be an absolute path")
    if not os.path.isdir(os.path.join(repo_path, ".git")):
        return error_result(
            "No .git directory found at {}. Is this a git repository?".format(repo_path)
        )

    project_name = os.path.basename(os.path.abspath(repo_path))
    env_files = scan_env_files(repo_path)
    pm = detect_package_manager(repo_path)
    scripts = parse_scripts(repo_path, pm)
    default_branch = detect_default_branch(repo_path)
    existing_config = read_config(repo_path)

    analysis = {
        "projectName": project_name,
        "envFiles": env_files,
        "packageManager": pm,
        "scripts": scripts,
        "defaultBranch": default_branch,
        "existingConfig": existing_config,
    }

    return text_result(json.dumps(analysis, indent=2, sort_keys=True))


def handle_configure_project(arguments):
    """Handle the configure_project tool call."""
    args = arguments or {}
    repo_path = args.get("repoPath")
    if not repo_path:
        return error_result("Missing required parameter: repoPath")
    if not repo_path.startswith("/"):
        return error_result("repoPath must be an absolute path")
    if not os.path.isdir(os.path.join(repo_path, ".git")):
        return error_result(
            "No .git directory found at {}. Is this a git repository?".format(repo_path)
        )

    env_files = args.get("envFilesToCopy", [])
    setup_commands = args.get("setupCommands", [])

    terminal_start_command = None
    if args.get("startClaudeInTerminals"):
        terminal_start_command = "claude"
    elif args.get("terminalStartCommand"):
        terminal_start_command = args["terminalStartCommand"]

    project_name = args.get("projectName")
    default_branch = args.get("defaultBranch")
    worktree_base_path = args.get("worktreeBasePath")

    run_configs = []
    for i, rc in enumerate(args.get("runConfigurations", [])):
        if not isinstance(rc, dict):
            continue
        name = rc.get("name")
        command = rc.get("command")
        if not name or not command:
            continue
        port = rc.get("port")
        if port is not None:
            if not isinstance(port, int) or port < 1 or port > 65535:
                return error_result(
                    "Invalid port {} for '{}'. Must be 1-65535.".format(port, name)
                )
        auto_start = rc.get("autoStart", False)
        order = rc.get("order", i)
        run_configs.append({
            "name": name,
            "command": command,
            "port": port,
            "autoStart": auto_start,
            "order": order,
        })

    config = {
        "envFilesToCopy": env_files,
        "setupCommands": setup_commands,
        "runConfigurations": run_configs,
    }
    if terminal_start_command is not None:
        config["terminalStartCommand"] = terminal_start_command
    if project_name is not None:
        config["projectName"] = project_name
    if default_branch is not None:
        config["defaultBranch"] = default_branch
    if worktree_base_path is not None:
        config["worktreeBasePath"] = worktree_base_path

    try:
        write_config(repo_path, config)
        gitignore_added = ensure_gitignore(repo_path)
    except OSError as e:
        return error_result("Failed to write config: {}".format(e))

    # Build summary
    lines = ["Configured {}:".format(repo_path)]
    if env_files:
        lines.append("- Env files: {}".format(", ".join(env_files)))
    if setup_commands:
        lines.append("- Setup commands: {}".format(len(setup_commands)))
        for cmd in setup_commands:
            lines.append("    {}".format(cmd))
    if run_configs:
        lines.append("- Run configurations: {}".format(len(run_configs)))
        for rc in run_configs:
            port_str = " (port {})".format(rc["port"]) if rc.get("port") else ""
            auto_str = " [default]" if rc.get("autoStart") else " [optional]"
            lines.append("    {}: {}{}{}".format(rc["name"], rc["command"], port_str, auto_str))
    if terminal_start_command:
        lines.append("- Terminal start command: {}".format(terminal_start_command))

    gitignore_note = (
        "Added .wtmux to .gitignore."
        if gitignore_added
        else ".wtmux was already in .gitignore."
    )
    lines.append("")
    lines.append(".wtmux/config.json written and project configured for WTMux. {}".format(gitignore_note))

    return text_result("\n".join(lines))


def handle_get_project_config(arguments):
    """Handle the get_project_config tool call."""
    repo_path = (arguments or {}).get("repoPath")
    if not repo_path:
        return error_result("Missing required parameter: repoPath")
    if not repo_path.startswith("/"):
        return error_result("repoPath must be an absolute path")

    config = read_config(repo_path)
    if config is None:
        return text_result(
            "No .wtmux/config.json found at {}. Project is not yet configured for WTMux.".format(
                repo_path
            )
        )

    return text_result(json.dumps(config, indent=2, sort_keys=True))


TOOL_HANDLERS = {
    "analyze_project": handle_analyze_project,
    "configure_project": handle_configure_project,
    "get_project_config": handle_get_project_config,
}


# ---------------------------------------------------------------------------
# JSON-RPC Server
# ---------------------------------------------------------------------------

def handle_request(msg):
    """Handle a single JSON-RPC request. Returns a response dict or None for notifications."""
    method = msg.get("method", "")
    params = msg.get("params", {})
    msg_id = msg.get("id")

    if method == "initialize":
        result = {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {
                "name": SERVER_NAME,
                "version": SERVER_VERSION,
            },
            "instructions": SERVER_INSTRUCTIONS,
        }
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    elif method == "notifications/initialized":
        # Notification — no response
        return None

    elif method == "tools/list":
        result = {"tools": TOOL_DEFINITIONS}
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    elif method == "tools/call":
        tool_name = params.get("name", "")
        arguments = params.get("arguments", {})
        handler = TOOL_HANDLERS.get(tool_name)
        if handler:
            result = handler(arguments)
        else:
            result = error_result("Unknown tool: {}".format(tool_name))
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    elif method == "ping":
        return {"jsonrpc": "2.0", "id": msg_id, "result": {}}

    elif msg_id is not None:
        # Unknown method with an id — return error
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "error": {"code": -32601, "message": "Method not found: {}".format(method)},
        }

    # Unknown notification — ignore
    return None


def main():
    """Run the MCP server, reading newline-delimited JSON from stdin."""
    if len(sys.argv) > 1 and sys.argv[1] == "--version":
        print("{} {}".format(SERVER_NAME, __version__))
        sys.exit(0)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        response = handle_request(msg)
        if response is not None:
            send_response(response)


if __name__ == "__main__":
    main()
