#!/usr/bin/env bash
# Run the upstream sagar87/tensorsignatures-data Docker image (process.R)
# in parallel chunks against a directory of merged per-sample VCFs.
#
# IMPORTANT (re. process.R quirks): process.R prepends "mount/" to every
# argument and writes the output HDF5 to mount/<output_name>. So the VCF
# dir must be bind-mounted at /usr/src/app/mount, and the chunk HDF5 lands
# in VCF_DIR. We move it to OUT_DIR afterwards.
#
# Each R process holds ~2 GB Constants.RData GRanges. NPAR=4 is safe on 30 GB.
#
# Usage:
#   VCF_DIR=~/MEGA/hmf_all/vcf \
#   OUT_DIR=~/MEGA/hmf_all/chunks \
#   CHUNK_SIZE=100 NPAR=4 \
#     bash scripts/processVcf_parallel.sh
set -euo pipefail

VCF_DIR="${VCF_DIR:?set VCF_DIR}"
OUT_DIR="${OUT_DIR:?set OUT_DIR}"
CHUNK_SIZE="${CHUNK_SIZE:-100}"
NPAR="${NPAR:-4}"
IMAGE="${IMAGE:-docker.io/sagar87/tensorsignatures-data:latest}"
DOCKER="${DOCKER:-docker}"

mkdir -p "$OUT_DIR"

ls "$VCF_DIR"/*.vcf.gz | sed 's|.*/||' | sort > "$OUT_DIR/all_vcfs.txt"
total=$(wc -l < "$OUT_DIR/all_vcfs.txt")
rm -f "$OUT_DIR"/chunk_*.txt
split -d -a 3 -l "$CHUNK_SIZE" --additional-suffix=.txt \
      "$OUT_DIR/all_vcfs.txt" "$OUT_DIR/chunk_"
n_chunks=$(ls "$OUT_DIR"/chunk_*.txt | wc -l)
echo "$total VCFs -> $n_chunks chunks of $CHUNK_SIZE, $NPAR concurrent"
date

run_chunk() {
    local chunk_list="$1"
    local stem
    stem=$(basename "$chunk_list" .txt)
    local final_h5="$OUT_DIR/$stem.h5"
    local staging_h5="$VCF_DIR/$stem.h5"
    if [[ -f "$final_h5" ]]; then
        echo "skip $stem (exists)"
        return 0
    fi
    local files
    files=$(tr '\n' ' ' < "$chunk_list")
    echo "[$(date +%H:%M:%S)] start $stem ($(wc -l < "$chunk_list") files)"
    # process.R prepends mount/ to each arg, so we just pass basenames + stem.h5
    $DOCKER run --rm \
        -v "$VCF_DIR:/usr/src/app/mount" \
        "$IMAGE" \
        $files "$stem.h5" \
        > "$OUT_DIR/$stem.log" 2>&1
    if [[ ! -f "$staging_h5" ]]; then
        echo "FAILED $stem (no output, see $OUT_DIR/$stem.log)" >&2
        return 1
    fi
    mv "$staging_h5" "$final_h5"
    echo "[$(date +%H:%M:%S)] done  $stem"
}
export -f run_chunk
export OUT_DIR VCF_DIR DOCKER IMAGE

ls "$OUT_DIR"/chunk_*.txt | xargs -P "$NPAR" -n 1 -I {} bash -c 'run_chunk "$@"' _ {}

date
echo "all chunks done. h5 outputs:"
ls -lh "$OUT_DIR"/chunk_*.h5
