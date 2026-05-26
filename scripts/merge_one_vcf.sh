#!/usr/bin/env bash
# Per-sample worker for merge_vcfs_parallel.sh. Emits a clean PASS-only
# 8-column VCF derived ONLY from the HMF PURPLE somatic VCF (which already
# contains SNVs + indels + MNVs in valid VCF format). The earlier
# .annotated.indel.vcf.gz files are NOT used: they are a custom
# annotated-TSV variant of the same indels and would double-count.
#
# Usage: merge_one_vcf.sh <SAMPLE_ID>
# Required env: VCF_SRC, OUT_DIR. Skips if output already exists.
set -euo pipefail

sid="$1"
snv="$VCF_SRC/$sid.purple.somatic.vcf.gz"
out="$OUT_DIR/$sid.vcf"
tmp="$out.tmp.$$"

if [[ -f "$out.gz" && -f "$out.gz.tbi" ]]; then
    echo "skip $sid (already done)"
    exit 0
fi

[[ -f "$snv" ]] || { echo "MISSING SNV: $snv" >&2; exit 1; }

{
    cat <<'EOF'
##fileformat=VCFv4.2
##reference=GRCh37
##INFO=<ID=.,Number=0,Type=Flag,Description="placeholder">
##FILTER=<ID=PASS,Description="All filters passed">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO
EOF
    bcftools view -f PASS -H "$snv" \
        | awk -v OFS='\t' '{print $1,$2,".",$4,$5,".","PASS","."}'
} > "$tmp"

(head -n 5 "$tmp"; tail -n +6 "$tmp" | sort -k1,1V -k2,2n) > "$out"
rm "$tmp"
bgzip -f "$out"
tabix -p vcf -f "$out.gz"

n_rec=$(bcftools view -H "$out.gz" | wc -l)
echo "done $sid: $n_rec records"
