# Native world-clock backend

`aarch64/supernotch-clock` and `x86_64/supernotch-clock` are built from
`plugins/clock/rust/` in this repository, package version 0.0.2. The source is
licensed under the repository's MIT `LICENSE`; see `CHECKSUMS.sha256` for the
exact packaged artifacts. Rebuild with `cargo build --release --locked` on the
corresponding Arch Linux architecture.

The backend reads the host's IANA timezone database and `zone.tab`; timezone
records are not bundled. Its Rust dependencies are pinned in `Cargo.lock`:

- `fs2` 0.4.3 — MIT or Apache-2.0.
- `jiff` 0.2.37 — Unlicense or MIT.
- `serde_json` 1.0.151 — MIT or Apache-2.0.

Their transitive crates and exact versions are listed in `Cargo.lock`. License
identifiers and upstream source locations are available in each crate's
`Cargo.toml` from crates.io. The binary uses only system `libc` and `libgcc_s`
at runtime; no private shared libraries are bundled.
