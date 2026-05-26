#!/usr/bin/env bash
#SBATCH --job-name=tensorsig-train
#SBATCH --partition=gpu-common
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --output=logs/train_%A_%a.out
#SBATCH --error=logs/train_%A_%a.err
#SBATCH --array=0-79

# De novo TensorSignatures training on /cwork/sr110/hmf_tensorsig_discovery/.
# Sweep ranks x seeds: 8 ranks (10, 12, 14, 16, 18, 20, 22, 25) x 10 seeds = 80 jobs.
#
# Array index decomposition:
#   rank_idx  = SLURM_ARRAY_TASK_ID / 10
#   seed_idx  = SLURM_ARRAY_TASK_ID % 10
#
# Assumes:
#   - pixi installed on DCC ($HOME/.pixi/bin/pixi) with GPU env feature
#   - repo at $HOME/tensorsignatures with pixi.lock checked in
#   - tensor at /cwork/sr110/hmf_tensorsig_discovery/hmf_all.tsdata.h5
#   - output dir /cwork/sr110/hmf_tensorsig_discovery/runs/ pre-created

set -euo pipefail
mkdir -p logs runs

REPO="${REPO:-$HOME/tensorsignatures}"
WORK="${WORK:-/cwork/sr110/hmf_tensorsig_discovery}"
TSDATA="${TSDATA:-$WORK/hmf_all.tsdata.h5}"

RANKS=(10 12 14 16 18 20 22 25)
N_RANKS=${#RANKS[@]}
SEEDS_PER_RANK=10

idx=${SLURM_ARRAY_TASK_ID}
rank=${RANKS[$((idx / SEEDS_PER_RANK))]}
seed=$((idx % SEEDS_PER_RANK))
out="$WORK/runs/rank${rank}_seed${seed}.pkl"

export PATH="$HOME/.pixi/bin:$PATH"
cd "$REPO"

# Use the GPU feature of the pixi env (defined as [feature.gpu] in pixi.toml).
# If that env doesn't exist on DCC yet, fall back to the default and let CUDA
# fail loudly. Either way, `tensorsignatures train` self-detects GPU presence.
pixi run --environment gpu --manifest-path "$REPO/pixi.toml" \
    tensorsignatures --verbose train \
        "$TSDATA" "$out" "$rank" \
        -k 50 -n -ep 50000 \
        -i $seed -j "rank${rank}_seed${seed}" \
        -ds 1000 -ls 1000 \
        -se $((seed * 1000 + 1))

echo "done: rank=$rank seed=$seed -> $out"
