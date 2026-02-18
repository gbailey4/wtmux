Update the WTMux Stable build from main and install it to ~/Applications.

Before running the script, commit and push all unstaged/uncommitted changes on main:
1. Stage all changes (`git add` the relevant files)
2. Create a commit with an appropriate message
3. Push to the remote

Then run the script at `scripts/update-stable.sh` from the repo root. This will:
1. Merge main into the stable worktree at ~/Development/wt-easy-stable
2. Regenerate the Xcode project with xcodegen
3. Build the WTMux-Stable scheme in Release mode
4. Copy Stable.app to ~/Applications

If the stable worktree doesn't exist yet, create it first:
```
git worktree add ~/Development/wt-easy-stable stable
```
