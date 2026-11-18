# build-box

A generic, blind build machine. An encrypted archive goes in, an encrypted result comes out; this repository
holds only the workflow that runs it.

1. Upload `in-<job>.7z` (7z, AES-256, file names encrypted) to the release `inbox`. It must contain `build.sh`
   at its root; the script gets `$OUT` (put the results there) and `$CACHE` (kept between runs when a cache
   key is given).
2. Run the `box` workflow with `job=<job>`, optionally `setup` (`java`, `android`) and `cache`.
3. Download `out-<job>.7z` from the release `outbox`: the results plus `build.log`, encrypted the same way.

The password is the repository secret `BOX_PASSWORD`. The public log says only whether the build worked.
