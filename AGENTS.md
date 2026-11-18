# AGENTS.md

Guide for anyone (human or AI agent) changing this repository or using it from another project.

## What this is

A blind build machine: `.github/workflows/box.yml` plus the client `box.sh`. Private projects of the same owner build here
without giving the public repository anything readable; this repository never names them. It exists because Actions minutes are free on public repositories.

## How a build goes

1. `box.sh` packs the folder into `in-<job>.7z` with 7-Zip: AES-256 and `-mhe=on`, so the file names are
   encrypted too. The password is the content of a local file; it is the repository secret `BOX_PASSWORD`.
2. It attaches the archive to the release `inbox`, then starts the workflow with `gh workflow run`. The run
   is found again by its title, `box <job>` (`run-name`).
3. The workflow, on the runner the input `runner` names: prepares the toolchains asked for in `setup`,
   restores `~/cache` (`actions/cache/restore`: the newest copy whose key starts with the opaque cache name
   plus OS and architecture), downloads the archive and
   deletes it from `inbox`, opens it in `$RUNNER_TEMP/src`, runs `bash ./build.sh` there with `OUT` and
   `CACHE` set and all its output written to `$OUT/build.log`, then encrypts `$OUT` the same way into
   `out-<job>.7z` on the release `outbox` (before that, `actions/cache/save` stores `~/cache` under the key
   `<cache>-<os>-<arch>-<run id>` when `cache_save` says so: `success`, `always` or `never`), deletes its working folders and fails if the build failed.
4. `box.sh` waits, downloads and deletes `out-<job>.7z`, opens it into the result folder and, if the build
   failed, prints the end of `build.log`.

## Rules (keep them when changing anything)

- **Nothing readable reaches the public log or the releases.** Every command that could print a file name,
  a path inside the archive or tool output is silenced (`> /dev/null 2>&1`), and `build.sh` writes only to
  `build.log`, which travels encrypted. Check a run's public log after every change to the workflow.
- **Inputs reach the shell only through `env:`**, never as `${{ inputs.x }}` inside `run:` (script injection).
  `job` is checked to be letters, digits and dashes.
- **Names are opaque.** The job id is random and the cache key is a hash of the password and the cache name,
  because both are visible publicly. Never put a project name in them.
- **The workflow only runs on `workflow_dispatch`**: only people with write access can start it. Never add
  `pull_request` or `push` triggers: a fork's pull request must not be able to run with the secret.
- **Inputs are deleted** from `inbox` as soon as they are downloaded, results from `outbox` as soon as the
  client has them. The releases stay empty between builds.
- `build.sh` always runs in bash (`defaults.run.shell`), also on Windows runners.
- 7-Zip: `7z` on the Linux and Windows images; on macOS `7zz` (installed with Homebrew when missing).

## Adding a toolchain

Add a token to the `setup` description and a step `if: contains(inputs.setup, '<token>')` using the official
setup action, with its version as another input with a default. Anything a project needs only for itself is
better installed by its own `build.sh` into `$CACHE`.

## A copy for another account

Create a public repository with these files, two releases named `inbox` and `outbox`, and the secret:

```bash
gh repo create OWNER/build-box --public --source . --push
gh release create inbox -R OWNER/build-box --notes "encrypted inputs"
gh release create outbox -R OWNER/build-box --notes "encrypted results"
gh secret set BOX_PASSWORD -R OWNER/build-box < password-file
```

Then use `box.sh ... --repo OWNER/build-box`.

## Known limits

- The cache is stored by GitHub unencrypted (readable only by runs of this repository). Keep only
  rebuildable things in it.
- One archive is at most 2 GB (release asset limit).
- The public log still shows the runner, the toolchains prepared, the timing and ok or failed.
