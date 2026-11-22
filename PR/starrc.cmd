***0629 version for starrc traft

************************************************************************
*** StarRC RC extraction command file
***
*** Temporary limitation:
*** The available extraction grid is 1p9m_6X1Z1U, while the current
*** PR/GDS/Calibre flow is intended for 1p9m_6X2Z0U.  The generated
*** SPEF can be used for flow bring-up and reference PT analysis, but
*** it must not be treated as a process-matched signoff extraction.
************************************************************************

*** User settings

*** Top-level design name.  It must match "DESIGN riscv" in the DEF.
BLOCK: riscv

*** Final routed DEF.  It must correspond to the same PR run as riscv.vg.
TOP_DEF_FILE: /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/data/riscv.def

*** Technology LEF followed by the SRAM macro LEF.
LEF_FILE: /home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_9lmT2.lef
LEF_FILE: /home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/LEF/ts1n65lpll2048x64m8_220a_5m.lef

*** StarRC extraction grid.  This is the available 6X1Z1U grid and is
*** intentionally retained only as a temporary substitute for 6X2Z0U.
TCAD_GRD_FILE: /home/library/tsmc65lp/pdk_new/CCI/online/1p9m_6X1Z1U/starrcxt.nxtgrd

*** Map DEF/LEF routing-layer names to StarRC conducting-layer names.
MAPPING_FILE: /home/project/cp_training_backend1/users/cpu26/target/PT_test/starrc_flow/def_starrc.map

*** SPEF output consumed by PrimeTime.  Keep this path on one physical line.
NETLIST_FILE: /home/project/cp_training_backend1/users/cpu26/target/PT_test/starrc_flow/riscv_core_typical.spef

*** Maximum local CPU count available to StarRC.
NUM_CORES: 32

*** Settings inherited from the existing teaching flow.
CASE_SENSITIVE: YES

*** Optional distributed-processing setting; commented out by the leading ***.
***STARRC_DP_STRING: list localhost:16

*** Run a single extraction corner.
SIMULTANEOUS_MULTI_CORNER: NO

*** StarRC extraction mode used by the original flow.
MODE: 400

*** Do not discard capacitances.
IGNORE_CAPACITANCE: NONE

*** Skip extraction inside all leaf cells/macros and extract top-level
*** interconnect.  Internal cell timing/parasitics are represented by .db.
SKIP_CELLS: *

*** Keep coupling capacitance instead of converting it all to ground capacitance.
COUPLE_TO_GROUND: NO

*** Generate Standard Parasitic Exchange Format for PrimeTime.
NETLIST_FORMAT: SPEF

*** Text summary generated after extraction.
SUMMARY_FILE: starrc.sum

*** Intermediate StarRC database directory, relative to starrc_flow.
STAR_DIRECTORY: ../starrc_work

*** Preserve the original flow's reduction policy.
REDUCTION: NO_EXTRA_LOOPS

*** Extract every top-level net.
NETS: *

*** Extract both resistance and capacitance.
EXTRACTION: RC
