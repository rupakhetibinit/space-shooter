# GitHub Pages releases

The workflow in `.github/workflows/pages.yml` validates, tests and builds the game on pushes to `master`, pull requests targeting `master`, manual CI runs, and version-tag pushes. **Only a pushed tag starting with `v` deploys the site.**

The production site URL will be https://rupakhetibinit.github.io/space-shooter/ after the first successful release deployment.

## One-time GitHub setup

1. Open https://github.com/rupakhetibinit/space-shooter/settings/pages .
2. Under **Build and deployment > Source**, select **GitHub Actions**.
3. Ensure GitHub Actions are enabled for the repository. The workflow uses the standard `GITHUB_TOKEN`; no API key or custom deployment secret is required.
4. If the `github-pages` environment restricts deployment branches/tags, allow tags matching `v*` under **Settings > Environments > github-pages**. Tags must be permitted; a default-branch-only environment rule will block tag deployments.

Enabling Pages and changing deployment-ref rules require repository administration access. Configure these once before the first tagged deployment.

## Publish a release

From the repository folder, after committing and pushing the desired changes:

```powershell
git tag -a v0.1.0 -m "First web release"
git push origin v0.1.0
```

Use a new version for the next release, for example `v0.1.1`. A local tag does not trigger GitHub Actions until pushed. Tag the commit containing the workflow and all required game sources/assets.

The workflow builds the tagged commit, runs the gameplay/config/behavior tests, and packages the public site. Deployment only proceeds after the build passes. Branch and PR builds produce downloadable artifacts without changing the live site. Re-running a successful tag workflow redeploys that tagged version; retagging or force pushes are unnecessary.

Follow runs at https://github.com/rupakhetibinit/space-shooter/actions . If a tag run fails because Pages was not enabled yet, complete the one-time setup and rerun that workflow.

## Reproducible toolchain

- Official Odin release: `dev-2026-11`.
- Emscripten SDK: `4.0.10`.
- Build runner: `windows-latest`, using the same PowerShell build/validation/test scripts as the local project.
- Deploy runner: `ubuntu-latest`, using GitHub's official Pages artifact/deploy actions.

The build downloads Odin from its official release archive and installs Emscripten through its official setup action. Build jobs have read-only repository contents permission. Only the tag deployment job receives `pages: write` and `id-token: write`.

## Local equivalent

```powershell
./test-game.ps1
./build-web.ps1 -Emsdk "C:/path/to/emsdk"
./package-web.ps1
python -m http.server 8000 --bind 127.0.0.1 --directory build/pages
```

`package-web.ps1` copies an explicit allowlist of fifteen public files, including separate player and `/editor/` WebAssembly bundles, campaign examples, creator/behavior guides and `.nojekyll`. Intermediate object files, native executables, local editor saves and SDKs are excluded. The source folder and build output are never uploaded wholesale.

## Git authentication

If local pushes fail, restore your normal GitHub authentication, for example with `gh auth login` followed by `gh auth setup-git`, or use your existing preferred Git credentials. Do not store a token in this repository.

Official references:

- https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages
- https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site
- https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax

The workflow checks the compiled export tables before packaging: creator/import/export APIs must be absent from the player build and present in the creator build. Both release bundles must omit QA controls.
