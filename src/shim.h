#ifndef LC3_DECODER_SHIM_H
#define LC3_DECODER_SHIM_H

#include "opusenc.h"

/* Same pattern liblc3's own LC3_EXPORT uses: unconditionally exported on
   Windows (no DLL_EXPORT-style opt-in gate to worry about), default ELF/
   Mach-O visibility elsewhere. Without this, MSVC builds an import library
   with no shim_* entries at all -- dart:ffi's DynamicLibrary.lookup would
   fail to find them even though the .dll compiled and linked cleanly. */
#ifdef _WIN32
#define SHIM_EXPORT __declspec(dllexport)
#else
#define SHIM_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ope_encoder_ctl (like the underlying opus_encoder_ctl) is a variadic C
   function: dart:ffi has no general way to call one. Each wrapper below
   resolves one fixed-arity call to it in C, so ffigen can bind a normal
   function signature on the Dart side. */

SHIM_EXPORT int shim_ope_encoder_ctl_set_application(OggOpusEnc *enc, opus_int32 application);
SHIM_EXPORT int shim_ope_encoder_ctl_set_bitrate(OggOpusEnc *enc, opus_int32 bitrate);
SHIM_EXPORT int shim_ope_encoder_ctl_set_signal(OggOpusEnc *enc, opus_int32 signal);
SHIM_EXPORT int shim_ope_encoder_ctl_set_vbr(OggOpusEnc *enc, opus_int32 vbr);

#ifdef __cplusplus
}
#endif

#endif
