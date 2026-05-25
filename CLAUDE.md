# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Environment

This is a TensorFlow 1.15 / Python 3.7 codebase. The pinned scientific stack (numpy <1.17, pandas 0.25, scipy 1.3, h5py 2.10) is fragile, do not casually upgrade.

Steve uses `pixi` to manage the environment. `pixi.toml` pins the full upstream stack plus `bcftools` and `pyarrow` for VCF preprocessing. Run Python or CLI commands through pixi:

    pixi run tensorsignatures --help    # or: pixi run ts ...
    pixi run python -m pytest tests/
    pixi run python -m pytest tests/test_tensorsignatures.py::TestTensorsignatures::test_command_line_interface

`tensorsignatures` is installed editable via pixi pypi-dependencies, so source edits take effect without reinstall.

## Common commands

- `make lint` runs `flake8 tensorsignatures tests`
- `make test` runs unit tests (prefer `pixi run python -m pytest` directly)
- `make docs` regenerates Sphinx API docs under `docs/`

## CLI architecture

Entry point: `tensorsignatures.cli:main` (registered in `setup.py` as `tensorsignatures`). Subcommands in `tensorsignatures/cli.py`:

- `prep <in.h5> <ts.h5>`, adds trinucleotide normalization to the input HDF5.
- `train <ts.h5> <out.pkl> <rank> ...`, de novo decomposition (GPU recommended).
- `refit <ts.h5> <out.pkl>`, fits exposures of pre-defined PCAWG signatures (`data/pcawg.pkl`) to new data, fast, no GPU needed.
- `boot`, bootstrap CIs for inferred parameters.
- `write`, aggregates per-run pickles into a single HDF5 (multiprocessing).
- `data`, synthesizes simulated input data.

All CLI argument names live as string constants in `tensorsignatures/config.py` (e.g. `RANK`, `SEED`, `INIT`, `OBJECTIVE`); the CLI imports them with `from tensorsignatures.config import *`. When adding or renaming options, edit `config.py` as well.

## Module layout

- `tensorsignatures/tensorsignatures.py`, core TF1 model. `TensorSignature` is the de novo extractor, `TensorSignatureRefit` is the refit variant. Uses a custom `@define_scope` decorator (memoized properties wrapped in `tf.variable_scope`) so each property builds its part of the graph exactly once.
- `tensorsignatures/bootstrap.py`, `TensorSignatureBootstrap` for percentile-based confidence intervals.
- `tensorsignatures/data.py`, `TensorSignatureData` simulator/fixture builder, also wraps trained model HDF5s for downstream inspection.
- `tensorsignatures/util.py`, `Initialization`, `load_dump`, `prepare_data` (used by `prep`).
- `tensorsignatures/writer.py`, HDF5 aggregation of pickled run dumps.
- `tensorsignatures/plot.py`, matplotlib visualizations of signatures and exposures.
- `tensorsignatures/data/`, shipped reference data: `pcawg.pkl` (reference signatures for `refit`), `norm.h5` (trinucleotide counts), `sim_sig.txt`, `other.txt`.

## Input data shape

The model expects an HDF5 containing an SNV count tensor of shape `(3, 3, t1+1, ..., tl+1, p, n)`, where dims 0/1 are transcription/replication state, middle `t_i` dims are arbitrary genomic states, `p` is SNV channels, `n` is samples, plus an `other` matrix of shape `(q, n)` for non-SNV mutation types. Trinucleotide normalization (added by `prep`) lives in the same HDF5.

## VCF preprocessing

Producing the input HDF5 from VCFs is done by the separate `sagar87/tensorsignatures-data` docker image (R 3.4 + `VariantAnnotation` + `rhdf5`), not by this repo. `scripts/merge_breast50_vcfs.sh` is a Steve-specific helper that merges HMF PURPLE SNV + indel VCFs into the 8-column PASS-only format `processVcf.R` (inside that docker image) expects. Run as `pixi run bash scripts/merge_breast50_vcfs.sh`.

## Conventions to preserve

- Keep TF 1.x APIs (`tf.variable_scope`, `tf.placeholder`, sessions). Do not migrate to TF 2.x style.
- Python 3.7 syntax only.
- Click 7.x (not 8.x) decorator style.
