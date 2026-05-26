#!/usr/bin/env bash
#SBATCH --job-name=tensorsig-refit
#SBATCH --partition=common
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=logs/refit_%j.out
#SBATCH --error=logs/refit_%j.err

# DCC TensorSignatures refit on /cwork/sr110/test-breast-xplus/.
# Assumes:
#   - pixi installed on DCC ($HOME/.pixi/bin/pixi)
#   - tensorsignatures repo rsynced to ~/tensorsignatures with pixi.lock
#   - apptainer SIF at /cwork/sr110/test-breast-xplus/tensorsig-data.sif
#   - de-identified per-sample merged VCFs already in
#     /cwork/sr110/test-breast-xplus/vcf/<sample>.vcf.gz

set -euo pipefail
mkdir -p logs

REPO="${REPO:-$HOME/tensorsignatures}"
WORK="${WORK:-/cwork/sr110/test-breast-xplus}"
SIF="${SIF:-$WORK/tensorsig-data.sif}"

export PATH="$HOME/.pixi/bin:$PATH"

cd "$REPO"
pixi install --locked   # replay env from pixi.lock

# 1. Upstream R preprocessing (in apptainer; samtools/R 3.4 bundled)
cd "$WORK/vcf"
apptainer exec --bind "$PWD:/usr/src/app/mount" "$SIF" \
    Rscript /usr/src/app/processVcf.R $(ls *.vcf.gz) breast50.h5

# 2 + 3. prep + refit (pixi env on bare metal)
cd "$WORK"
pixi run --manifest-path "$REPO/pixi.toml" tensorsignatures prep \
    vcf/breast50.h5 vcf/breast50.tsdata.h5
pixi run --manifest-path "$REPO/pixi.toml" tensorsignatures --verbose refit \
    vcf/breast50.tsdata.h5 out/breast50.refit.pkl -n -ep 5000 -ds 500

# 4. Sanity-check plot
pixi run --manifest-path "$REPO/pixi.toml" python \
    "$REPO/scripts/sanity_check_refit.py" out/breast50.refit.pkl
echo "done — see out/breast50.refit.exposures.png"
