# build-box

A generic, blind build machine on GitHub Actions. A project that must stay private uses it to build
without giving it anything readable: the source goes in as an encrypted archive, the result comes out
encrypted, and the public log only says whether it worked. This repository holds only the workflow and the
client script.

## Using it from a project

1. Put a `build.sh` at the root of the folder to build. It runs on the chosen machine with:
   - `$OUT`: put the results here (they come back to you, with `build.log`);
   - `$CACHE`: kept between runs when you give a cache name (toolchains, dependencies, object files).
   Write its own output freely: it all goes into `build.log`, never into the public log.
2. Keep the password in a file the project ignores (for example `.tools/box-password`). It must be the same
   as the secret `BOX_PASSWORD` of this repository.
3. From Git Bash (Windows), Linux or macOS, with `gh` logged in and 7-Zip installed:

```bash
bash box.sh path/to/folder path/to/password-file path/to/result --runner ubuntu-latest --setup "java android" --cache my-project-android
```

Options: `--runner` (any GitHub-hosted runner label: `ubuntu-latest`, `ubuntu-24.04`, `ubuntu-24.04-arm`,
`windows-latest`, `windows-2025`, `macos-latest`, `macos-15`...), `--setup` (`java`, `android`, `node`,
`python`, with `--java`, `--node`, `--python` for the versions), `--cache NAME`, `--timeout MINUTES`,
`--cache-save success|always|never`, `--repo OWNER/NAME` for another copy of the machine.

## Keeping state between builds (`$CACHE`)

`build.sh` gets `$CACHE`, a folder that survives from one build to the next when you pass `--cache NAME`.
Put there whatever is slow to get again: downloaded toolchains and SDKs, dependencies, object files, a
build tree. A typical `build.sh`:

```bash
mkdir -p "$CACHE/deps" "$CACHE/build"
[ -d "$CACHE/deps/sdk" ] || download_sdk_into "$CACHE/deps/sdk"   # only the first time
ln -sfn "$CACHE/build" build                                       # incremental: object files kept
make -C build && cp build/app "$OUT/"
```

- **Restore**: before `build.sh` runs, the newest saved copy for the same name, operating system and
  architecture is put back in `$CACHE` (a Linux and a Windows build of the same name keep separate copies).
  The first build of a name starts with an empty folder.
- **Save**: `--cache-save success` (default) saves `$CACHE` only when `build.sh` succeeded, `always` also
  when it failed (useful for long builds: the part already done is not lost), `never` only reads it.
- **Start again from empty**: use another name (`--cache NAME-v2`).
- Paths: `$CACHE` is the same absolute path on every build of the same runner, so build trees that remember
  absolute paths (CMake, Gradle) can live there, or be linked from the source folder as above.
- Limits (GitHub's): 10 GB of caches per repository; the oldest are dropped first, and a copy unused for
  7 days goes. Each save is a new copy, so a cache of a few hundred MB costs that much per build until old
  copies are dropped.

`build.sh` always runs in bash, also on Windows (Git Bash of the runner). The standard runners are free on
a public repository; larger runners are not.

## What is public and what is not

| Public | Encrypted or private |
|---|---|
| this workflow and `box.sh` | the source and data (7z, AES-256, file names encrypted) |
| that a build ran, on which runner, how long, ok or failed | `build.log`, every compiler message |
| an opaque job id and an opaque cache key | the results |
| | the password (repository secret, only the workflow reads it) |

The cache (`$CACHE`) is stored by GitHub unencrypted, but it can only be read by runs of this repository,
which only its owner can start. Put in it only what can be rebuilt (toolchains, dependencies, objects).

Details, rules for changing the workflow, and how to start a copy for another account: [AGENTS.md](AGENTS.md).
