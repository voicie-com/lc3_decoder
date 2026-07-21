/* Unity build: pulls every vendored source in this directory into one
   translation unit so the compiler command line stays well under
   cmd.exe's command-length limit (see hook/build.dart -- this repo
   vendors dozens of small .c files per library). Each #include below
   is an unmodified vendored source file, compiled exactly as before;
   only the number of separate cl.exe/clang arguments changes. */
#include "apply_sine_window_FLP.c"
#include "autocorrelation_FLP.c"
#include "burg_modified_FLP.c"
#include "bwexpander_FLP.c"
#include "corrMatrix_FLP.c"
#include "encode_frame_FLP.c"
#include "energy_FLP.c"
#include "find_LPC_FLP.c"
#include "find_LTP_FLP.c"
#include "find_pitch_lags_FLP.c"
#include "find_pred_coefs_FLP.c"
#include "inner_product_FLP.c"
#include "k2a_FLP.c"
#include "LPC_analysis_filter_FLP.c"
#include "LPC_inv_pred_gain_FLP.c"
#include "LTP_analysis_filter_FLP.c"
#include "LTP_scale_ctrl_FLP.c"
#include "noise_shape_analysis_FLP.c"
#include "pitch_analysis_core_FLP.c"
#include "process_gains_FLP.c"
#include "regularize_correlations_FLP.c"
#include "residual_energy_FLP.c"
#include "scale_copy_vector_FLP.c"
#include "scale_vector_FLP.c"
#include "schur_FLP.c"
#include "sort_FLP.c"
#include "warped_autocorrelation_FLP.c"
#include "wrappers_FLP.c"
