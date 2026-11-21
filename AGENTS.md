# Claude FM menu bar

## Pull requests

A PR that changes anything visual includes evidence of how it looks: screenshots, a screen recording, or rendered images in the PR body. This covers the menu bar icon, the app icon, menus, and any window. When it changes something that already exists, show before and after.

- **Menu bar icon:** run `./scripts/render-menubar-icon.sh`. It draws the icon through every player state with the app's own code, on light and dark menu bars, into `docs/menubar-icon.gif` and `docs/menubar-icon.png`. Commit both.
- **App icon:** run `./scripts/render-icon.sh`, and update `docs/icon.png` with a picture of the compiled icon.
- **Menus and windows:** take a screenshot.

To show a committed image in the PR body, link it at the branch's commit, for example `https://raw.githubusercontent.com/lubelski/claude-fm-menubar/<sha>/docs/menubar-icon.gif`. GitHub's API can't attach images to a PR any other way.

Screen capture from an agent session often returns only the desktop wallpaper, with no menu bar items, because the terminal lacks Screen Recording permission. That's why the render scripts exist. If you couldn't see a change on screen, say so in the PR.
