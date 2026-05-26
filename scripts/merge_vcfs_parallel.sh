#!/usr/bin/env bash
# Parallel wrapper around merge_one_vcf.sh. xargs -P fans out the per-sample
# work over multiple cores. I/O-bound (MEGA-fuse read + local write), so
# we don't need many parallel workers to saturate the disk.
#
# Run via:
#   SAMPLE_IDS=~/MEGA/hmf_all/hmf_all_ids.txt \
#   OUT_DIR=~/MEGA/hmf_all/vcf \
#   NPAR=8 \
#     pixi run bash scripts/merge_vcfs_parallel.sh
set -euo pipefail

SAMPLE_IDS="${SAMPLE_IDS:?set SAMPLE_IDS}"
export VCF_SRC="${VCF_SRC:-$HOME/MEGA/important_mut_sig_data/fmh-unfiltered_vcfs}"
export OUT_DIR="${OUT_DIR:?set OUT_DIR}"
NPAR="${NPAR:-8}"

mkdir -p "$OUT_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
worker="$SCRIPT_DIR/merge_one_vcf.sh"
[[ -x "$worker" ]] || chmod +x "$worker"

total=$(wc -l < "$SAMPLE_IDS")
echo "starting parallel merge: $total samples, $NPAR workers, out=$OUT_DIR"
date

# `xargs -P N` runs N workers in parallel. We export env vars the worker needs.
xargs -P "$NPAR" -n 1 -I {} bash "$worker" {} < "$SAMPLE_IDS"

date
echo "done. $(ls "$OUT_DIR"/*.vcf.gz 2>/dev/null | wc -l) output VCFs in $OUT_DIR"
