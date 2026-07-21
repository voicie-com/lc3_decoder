/* Unity build: pulls every vendored source in this directory into one
   translation unit so the compiler command line stays well under
   cmd.exe's command-length limit (see hook/build.dart -- this repo
   vendors dozens of small .c files per library). Each #include below
   is an unmodified vendored source file, compiled exactly as before;
   only the number of separate cl.exe/clang arguments changes. */
#include "analysis.c"
#include "extensions.c"
#include "mapping_matrix.c"
#include "mlp.c"
#include "mlp_data.c"
#include "opus.c"
#include "opus_decoder.c"
#include "opus_encoder.c"
#include "opus_multistream.c"
#include "opus_multistream_decoder.c"
#include "opus_multistream_encoder.c"
#include "opus_projection_decoder.c"
#include "opus_projection_encoder.c"
#include "repacketizer.c"
