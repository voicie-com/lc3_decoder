#ifndef LC3_DECODER_BUILD_CONFIG_H
#define LC3_DECODER_BUILD_CONFIG_H

/* Force-included (see hook/build.dart) into every source file this asset
   compiles. The vendored libraries below are normally configured by
   autotools/CMake, which we don't run; none of them are told
   HAVE_CONFIG_H, so they never look for a generated config.h and instead
   rely purely on the compiler defines a real config.h would have carried.
   Centralizing those defines in one forced header -- rather than passing
   them as compiler -D flags -- sidesteps quoting a string-valued macro
   (PACKAGE_VERSION) through each toolchain's own argv handling. */

/* libopus: non-fixed-point (float) codec path, stack allocation via
   alloca() rather than C99 VLAs (portable across MSVC/clang/gcc). */
#define OPUS_BUILD
#define USE_ALLOCA

/* On Windows, both OPUS_EXPORT and OPE_EXPORT below only expand to
   __declspec(dllexport) when DLL_EXPORT is also defined; without it every
   opus/opusenc symbol stays unexported from the DLL we build (liblc3's own
   LC3_EXPORT isn't gated like this, which is why the original lc3-only
   build never needed this define). No effect on non-Windows targets, where
   the *_BUILD defines above are what control default visibility instead. */
#define DLL_EXPORT
/* opus_defines.h guards OPUS_EXPORT on `_WIN32` (MSVC always defines this),
   but opusenc.h guards OPE_EXPORT on plain `WIN32` -- not auto-defined by
   cl.exe -- so without this, every ope_* symbol silently stays unexported
   even with DLL_EXPORT set. */
#ifdef _WIN32
#ifndef WIN32
#define WIN32
#endif
#endif

/* libopusenc */
#define OPE_BUILD
/* Renames the vendored speex resampler's symbols so they can't collide with
   a real libspeexdsp if one is ever linked into the same process. */
#define RANDOM_PREFIX libopusenc
/* Builds the resampler as a standalone unit instead of pulling in a system
   speex/speexdsp_types.h. */
#define OUTSIDE_SPEEX
#define RESAMPLE_FULL_SINC_TABLE 1
#define PACKAGE_NAME "libopusenc"
#define PACKAGE_VERSION "0.3"

#endif
