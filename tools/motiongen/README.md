# MotionGen normalizer status

`normalize_xlsx.mjs` is retained byte-for-byte as provenance for the 17 committed MotionGen
exports. Its SHA-256 is embedded in every receipt, and the original XLSX files were intentionally
discarded after normalization.

The script imports `@oai/artifact-tool`, which is supplied by an internal artifact runtime and is
not a public, locked project dependency. Consequently it is not reproducible from a clean clone
and is not an approved tool for new exports. Its JavaScript `toPrecision(17)` formatter can also
spell some values in the `1e-6` to `1e-4` range differently from the v1 contract's canonical
Python `%.17g` spelling, although none of the committed normalized files trigger that mismatch.

Do not edit the historical script: doing so would invalidate every receipt without making the
discarded source workbooks available for re-normalization. Before any MotionGen refresh:

1. Add a normalizer using a public XLSX parser with a committed lock file.
2. Serialize numbers with behavior tested against Python `format(value, '.17g')`, including the
   fixed/scientific-notation boundary.
3. Re-export all graphs from the retained models and generate new normalized CSV and receipts.
4. Run the complete MotionGen comparison and promotion workflow before replacing the fixtures.

The current fixtures remain auditable at their committed boundary: validators check each
normalized CSV hash, receipt fields, retained model identity, and the unchanged historical script
hash. They cannot prove a fresh XLSX-to-CSV re-normalization without obtaining new exports; that
limitation is deliberate and explicit rather than hidden behind an unavailable dependency.
