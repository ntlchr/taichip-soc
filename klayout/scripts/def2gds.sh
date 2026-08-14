#! /bin/bash
# KLayout batch mode for converting def to gds
# Based on https://github.com/pulp-platform/croc/blob/main/klayout/run_finishing.sh

SCRIPT_DIR=$(realpath $(dirname "${BASH_SOURCE[0]}"))
KLAYOUT_DIR=$(dirname $SCRIPT_DIR)
ROOT_DIR=$(dirname $KLAYOUT_DIR)

TOP_DESIGN=${TOP_DESIGN:-"croc_chip"}
PROJ_NAME=${PROJ_NAME:-"taichip_soc"}

export PDK="ihp-sg13cmos5l"
export PDK_DIR="${ROOT_DIR}/ihp13/sg13cmos5l"
PDK_DIR_LEF_TECH="${PDK_DIR}/libs.ref/sg13cmos5l_stdcell/lef"
PDK_DIR_LEF_CELLS="${PDK_DIR}/libs.ref/sg13cmos5l_stdcell/lef"
PDK_DIR_LEF_SRAMS="${PDK_DIR}/libs.ref/sg13cmos5l_sram/lef"
PDK_DIR_LEF_IOS="${PDK_DIR}/libs.ref/sg13cmos5l_io/lef"
PDK_DIR_LEF_BOND="${ROOT_DIR}/ihp13/bondpad/lef"

PDK_DIR_GDS_CELLS="${PDK_DIR}/libs.ref/sg13cmos5l_stdcell/gds"
PDK_DIR_GDS_SRAMS="${PDK_DIR}/libs.ref/sg13cmos5l_sram/gds"
PDK_DIR_GDS_IOS="${PDK_DIR}/libs.ref/sg13cmos5l_io/gds"
PDK_DIR_GDS_BOND="${ROOT_DIR}/ihp13/bondpad/gds"

export KLAYOUT_PATH="${PDK_DIR}/libs.tech/klayout"

lef_files="$(find "$PDK_DIR_LEF_CELLS" -name 'sg13cmos5l_stdcell.lef' -exec realpath {} \;) \
     $(find "$PDK_DIR_LEF_TECH" -name 'sg13cmos5l_tech.lef' -exec realpath {} \;) \
     $(find "$PDK_DIR_LEF_SRAMS" -name 'RM_IHPSG13*.lef' -exec realpath {} \;) \
     $(find "$PDK_DIR_LEF_IOS" -name 'sg13cmos5l_io.lef' -exec realpath {} \;) \
     $(find "$PDK_DIR_LEF_BOND" -name '*.lef' -exec realpath {} \;)"

gds_files="$(find "$PDK_DIR_GDS_CELLS" -name 'sg13cmos5l_stdcell.gds' -exec realpath {} \;) \
     $(find "$PDK_DIR_GDS_SRAMS" -name 'RM_IHPSG13*.gds' -exec realpath {} \;) \
     $(find "$PDK_DIR_GDS_IOS" -name 'sg13cmos5l_io.gds' -exec realpath {} \;) \
     $(find "$PDK_DIR_GDS_BOND" -name '*.gds' -exec realpath {} \;)"

cd ${KLAYOUT_DIR}
mkdir -p out
klayout -zz \
	-rd gds_allow_empty=True \
	-rd design_name=${TOP_DESIGN} \
	-rd in_def=../openroad/out/${PROJ_NAME}.def \
	-rd layer_map=${KLAYOUT_PATH}/tech/sg13cmos5l.map \
	-rd lef_files=$lef_files \
	-rd gds_files=$gds_files \
	-rd out_file=out/${PROJ_NAME}.gds.gz \
	-rm scripts/def2stream.py
