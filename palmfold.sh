#!/bin/bash
# palmfold
#
# Structural alignment and scoring against
# a reference set of palmprint structures
#
VERSION='0.2.0'
#
set -eu

# Usage
function usage {
  echo "palmfold v $VERSION"
  echo ""
  echo "Usage: ./palmfold.sh -p <path_to_palmprint> -d <path_to_test_pdb> -o <output_dir> [OPTIONS]"
  echo ""
  echo "    -h    Show this help/usage message"
  echo ""
  echo "    Required Fields"
  echo "    -o    Output files path (created if DNE)"
  echo ""
  echo "    Reference Palmprint and Test Structures"
  echo "    -p    Palmprint Reference Path (pdb) [./pol]"
  echo "            must contain palmprint/*.pdb & rdrp.model.list file"
  echo "    -d    Predicted Fold PDB-file Path [./pdb]"
  echo ""
  echo "    TMalign Parameters"
  echo "    -s    TMalign Cut-off threshold for inclusion [0.5]"
  echo ""
  echo "ex: ./palmfold.sh -p ./pol -d ./pdb -o test_run"
  false
  exit 1
}

# Default parameters
PALMPRINTS="./pol"
PDBS="./pdb"
OUTNAME='' # unset
CUTOFF="0.5"

while getopts p:d:o:s:h FLAG; do
  case $FLAG in
    p)
      PALMPRINTS=$OPTARG
      ;;
    d)
      PDBS=$OPTARG
      ;;
    o)
      OUTNAME=$OPTARG
      ;;
    s)
      CUTOFF=$OPTARG
      ;;
    h)  #show help ----------
      usage
      ;;
    \?) #unrecognized option - show help
      echo "Input parameter not recognized"
      usage
      ;;
  esac
done
shift $((OPTIND-1))

# Check Required
if [ -z "$OUTNAME" ]; then
    echo "Output directory name not set (-o)"
    false
    exit 1
fi

# Initialize workspace
mkdir -p $OUTNAME
mkdir -p $OUTNAME/pdb_realign
mkdir -p $OUTNAME/tmfa
mkdir -p $OUTNAME/fa
mkdir -p $OUTNAME/fa/pp
mkdir -p $OUTNAME/fa/rc

# tmp directory
mkdir -p $OUTNAME/tmp

# Initialize TMalign header output
echo -e 'PDBchain1\tPDBchain2\tTM1\tTM2\tRMSD\tID1\tID2\tIDali\tL1\tL2\tLali' >> $OUTNAME/$OUTNAME.tm

# Run TMalign against Reference Palmprints
# =========================================================
for pdbz in $(ls $PDBS/); do

  # If PDB is gz compressed, decompress in place
  GZ='FALSE'
  if [[ $pdbz == *.gz ]]; then
    GZ='TRUE'
    gzip -d $PDBS/$pdbz
  fi

  pdb=$(echo $pdbz | sed 's/.gz//g' -)  


  # Input PDB File
  #echo $pdb

  # Iterate through reference palmprint
  for pp in $(ls $PALMPRINTS/palmprint/); do

    TMalign -outfmt 2 \
      $PDBS/$pdb \
      $PALMPRINTS/palmprint/$pp \
      >> $OUTNAME/tmp/pdb_raw.tm
  done

  # Clean-up TM output
  grep '.pdb' $OUTNAME/tmp/pdb_raw.tm \
   | sed 's/\.pdb//g' - \
   | sed "s,$PDBS/,,g" - \
   | sed "s,$PALMPRINTS/palmprint/,,g" - \
   > $OUTNAME/tmp/pdb_clean.tm

  rm $OUTNAME/tmp/pdb_raw.tm

  # Append TMalign CSV to output file
  cat $OUTNAME/tmp/pdb_clean.tm >> $OUTNAME/$OUTNAME.tm

  # Isolate Maximum RdRP TMalign Score
  maxRdRP=$(grep -f pol/rdrp.model.list $OUTNAME/tmp/pdb_clean.tm \
    | cut -f 2,4 | sort -k 2 -nr -| head -n1)

    maxRdRP_model=$(echo $maxRdRP | cut -d' ' -f 1)
    maxRdRP_score=$(echo $maxRdRP | cut -d' ' -f 2)

  # Isolate Maximum XdXP TMalign Score (NOT RdRP)
  maxXdXP=$(grep -v -f pol/rdrp.model.list $OUTNAME/tmp/pdb_clean.tm \
    | cut -f 2,4 | sort -k 2 -nr -| head -n1)

    maxXdXP_model=$(echo $maxXdXP | cut -d' ' -f 1)
    maxXdXP_score=$(echo $maxXdXP | cut -d' ' -f 2)

  # Use bc to compare floats
  # Does maxRdRP_score pass CUTOFF value
  if [ 1 -eq "$(echo "$maxRdRP_score >= $CUTOFF" | bc)" ]; then
    
    # A significant RdRP match is present
    # Does maxRdRP surpass maxXdXP

    if [ 1 -eq "$(echo "$maxRdRP_score >= $maxXdXP_score" | bc)" ]; then
      # RdRP Hit is significant and surpasses XdXP

      # Generate Fasta and Re-Align PDB output
      # against TOP HIT only
      
      TMalign -outfmt 1 \
      $PDBS/$pdb \
      $PALMPRINTS/palmprint/$maxRdRP_model.pdb \
      -o $OUTNAME/tmp/realign \
      > $OUTNAME/tmfa/$pdb.fa

      mv $OUTNAME/tmp/realign.pdb $OUTNAME/pdb_realign/$pdb

      # PROCESS TM FASTA FILE TO ISOLATE
      # PALMPRINT AND RDRPCORE
      # python3 palmgrab.py -i <input.tm.fa> -p <palmprint.fa> -r <rdrpcore.fa>
      python3 palmgrab.py $OUTNAME/tmfa/$pdb.fa \
                          $pdb.pp.fa \
                          $pdb.rc.fa

      mv $pdb.pp.fa $OUTNAME/fa/pp/
      mv $pdb.rc.fa $OUTNAME/fa/rc/

      echo -e "$pdb\t$maxRdRP_model\t$maxRdRP_score\t$maxXdXP_model\t$maxXdXP_score"

    fi
  fi

  # Recompress, if needed
  if [[ "$GZ" = 'TRUE' ]]; then
    gzip $PDBS/$pdb
  fi

done

# Create merged fasta outputs
cat $OUTNAME/fa/pp/* > $OUTNAME/palmprints.fa
cat $OUTNAME/fa/rc/* > $OUTNAME/rdrpcores.fa

# Clean-up temporary directory
#rm -rf $OUTNAME/tmp
