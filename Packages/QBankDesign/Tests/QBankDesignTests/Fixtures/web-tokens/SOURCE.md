# Web token fixtures

`colors.css`, `spacing.css` and `typography.css` are unmodified copies of the QBank web app's design tokens (`apps/web/src/styles/` in the private web repo, commit `2b7a429`). The tests resolve them the way a browser does and check every Swift token against them.

When the web tokens change, copy the new files here and run `swift test`: each failure names the token that drifted.
