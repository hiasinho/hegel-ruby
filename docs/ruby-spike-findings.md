# Ruby spike findings: Checkpoint 1

This document records Checkpoint 1 only. Checkpoint 2 (arrays, the broken-sort property, and fresh-process replay) has not been started.

## Pinned environment

The spike was run on:

- Linux x86_64
- CRuby 3.4.10
- Bundler 4.0.20
- `ffi` 1.17.4
- `libhegel` 0.44.0, upstream tag `libhegel-v0.44.0` (`09c6c0b9aa82f20b4f522ef45b646948f2e793bc`)

The binding was checked against the release's `hegel.h` and its `hegel-c/examples/failing.c`. The release assets are:

| Asset | URL | SHA-256 |
| --- | --- | --- |
| `hegel.h` | `https://github.com/hegeldev/hegel-rust/releases/download/libhegel-v0.44.0/hegel.h` | `a324eca375a51f0b46b41db6017c6d4f000324c3a6d3ee2563a17a11df4a6944` |
| `libhegel-linux-amd64.so` | `https://github.com/hegeldev/hegel-rust/releases/download/libhegel-v0.44.0/libhegel-linux-amd64.so` | `c2baf69815c3cb7ebbcc690f6d721e21056ce278651d26e9e8c5ba795e2ce48c` |

Those values match the `.sha256` sidecars and digests published on the upstream release. `spike/script/fetch-libhegel` embeds them, downloads to the ignored `spike/vendor/libhegel-v0.44.0/` directory, and refuses non-Linux or non-amd64 hosts. Runtime code never downloads native files.

## Setup and run

From the repository root:

```sh
cd spike
gem install --user-install bundler -v 4.0.20
ruby "$(ruby -e 'print Gem.user_dir')/bin/bundle" install
./script/fetch-libhegel
ruby "$(ruby -e 'print Gem.user_dir')/bin/bundle" exec ruby failing_integer.rb
```

The explicit Bundler path avoids a development-machine `mise` shim which does not have a default Ruby selected. On an ordinary Ruby installation, `bundle install` and `bundle exec ruby failing_integer.rb` are equivalent. If the library is stored elsewhere, set `HEGEL_LIBRARY_PATH` to the shared library before running the demo.

## Captured result

With the pinned seed from upstream's example, the command printed:

```text
libhegel version: 0.44.0
shrunk failing integer: 5
failure origin: n >= 5
reproduction blob: AAEAAAAACgEAAAAF
```

The upstream property says that every integer in `[0, 100]` is less than 5. The demo asserts upstream's expected minimal counterexample, 5. It also decodes the returned blob through `hegel_test_case_from_blob`, drives the same integer draw, and confirms that the replay still fails with the same origin. The exact blob is version-specific.

## Division of work

Ruby configures the run, repeatedly invokes the integer draw, evaluates `n < 5`, classifies each case, checks native result codes, copies the failure origin/blob, verifies the final replay, prints the report, and explicitly frees every owned native handle.

`libhegel` chooses the integers, schedules test cases, detects the interesting case, searches and shrinks its choice sequence to 5, and returns the minimal reproduction blob.

## Assessment

FFI was sufficient for this demonstration. The direct binding is small, and explicit draws make the Ruby/native boundary easy to see. The awkward parts are the number of out-pointers and the need to pair every opaque handle with an explicit destructor while preserving Hegel's completion protocol.

This checkpoint validates one synchronous integer path only. It does not validate arrays/spans, user-block exception cleanup, assumptions, callbacks, concurrency, database persistence, broad leak safety, other Ruby implementations, other operating systems, or packaging. The next planned experiment remains Checkpoint 2; none of that work is included here.
