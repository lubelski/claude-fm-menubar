# Claude FM menu bar

## Pull requests

A PR that changes anything visual includes evidence of how it looks: screenshots, a screen recording, or rendered images in the PR body. This covers the menu bar icon, the app icon, menus, and any window. When it changes something that already exists, show before and after.

- Menu bar icon
  - Run `./scripts/render-menubar-icon.sh`.
  - It draws the icon through every player state with the app's own code, on light and dark menu bars, into `docs/menubar-icon.gif` and `docs/menubar-icon.png`.
  - Commit both.
- Menu player
  - Run `./scripts/render-menu-player.sh`.
  - It draws the player at the top of the menu in every state, on light and dark, into `docs/menu-player.png`.
  - Commit it.
- App icon
  - Run `./scripts/render-icon.sh`.
  - Update `docs/icon.png` with a picture of the compiled icon.
- Menus and windows
  - Take a screenshot.

Put screenshots, recordings, and rendered images on the pull request with `gh`'s `--attach <file>` flag. It works on `gh pr create`, `gh pr edit`, and `gh pr comment`. The flag uploads the file and appends it to the body. Repeat it to attach several files.

- Alt text follows the path after `#`, as in `--attach './menu.png#The menu in dark mode'`.
- A reference to the file already in the body, such as `![The menu](./menu.png)`, is rewritten to point at the upload.

The rendered images in `docs/` are documentation assets that the README shows and describes. Keep committing them so they stay current. To show one in the PR body, attach the file with `--attach`. Do not link the raw file on GitHub.

Screen capture from an agent session often returns only the desktop wallpaper, with no menu bar items, because the terminal lacks Screen Recording permission. That's why the render scripts exist. If you couldn't see a change on screen, say so in the PR.
