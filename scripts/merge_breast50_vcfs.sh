#!/usr/bin/env bash
# Build one clean minimal VCF per sample combining HMF PURPLE SNVs + annotated
# indels, PASS-only, 8 mandatory columns. Output ready for processVcf.R.
#
# Run inside the pixi env so bcftools is on PATH:
#   pixi run bash scripts/merge_breast50_vcfs.sh
set -euo pipefail

SAMPLE_IDS="${SAMPLE_IDS:-/tmp/breast50_ids.txt}"
VCF_SRC="${VCF_SRC:-$HOME/MEGA/important_mut_sig_data/fmh-unfiltered_vcfs}"
OUT_DIR="${OUT_DIR:-$HOME/MEGA/test_50_breast_ca_extended/vcf}"

mkdir -p "$OUT_DIR"

vcf_header() {
    cat <<'EOF'
##fileformat=VCFv4.2
##reference=GRCh37
##INFO=<ID=.,Number=0,Type=Flag,Description="placeholder">
##FILTER=<ID=PASS,Description="All filters passed">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO
EOF
}

n_samples=$(wc -l < "$SAMPLE_IDS")
i=0
while read -r sid; do
    i=$((i+1))
    snv="$VCF_SRC/$sid.purple.somatic.vcf.gz"
    ind="$VCF_SRC/$sid.annotated.indel.vcf.gz"
    out="$OUT_DIR/$sid.vcf"
    tmp="$out.tmp"

    [[ -f "$snv" ]] || { echo "missing SNV: $snv" >&2; exit 1; }
    [[ -f "$ind" ]] || { echo "missing indel: $ind" >&2; exit 1; }

    vcf_header > "$tmp"

    # SNVs: standard VCF, take PASS only, drop INFO/FORMAT cols.
    bcftools view -f PASS -H "$snv" \
        | awk -v OFS='\t' '{print $1,$2,".",$4,$5,".","PASS","."}' \
        >> "$tmp"

    # Indels: file lacks ## headers and the column-name line lacks a leading "#".
    # Skip until the CHROM header line, then keep PASS rows; drop the annotation tail.
    zcat "$ind" \
        | awk -v OFS='\t' 'BEGIN{seen=0}
            seen==0 && $1=="CHROM" {seen=1; next}
            seen==1 && $7=="PASS" {print $1,$2,".",$4,$5,".","PASS","."}' \
        >> "$tmp"

    # Sort by chrom+pos, bgzip, index.
    (head -n 5 "$tmp"; tail -n +6 "$tmp" | sort -k1,1V -k2,2n) > "$out"
    rm "$tmp"
    bgzip -f "$out"
    tabix -p vcf -f "$out.gz"

    n_rec=$(bcftools view -H "$out.gz" | wc -l)
    printf '[%3d/%d] %s: %d records\n' "$i" "$n_samples" "$sid" "$n_rec"
done < "$SAMPLE_IDS"

echo "done: $OUT_DIR"
ls "$OUT_DIR" | head
