#include "shim.h"

int shim_ope_encoder_ctl_set_application(OggOpusEnc *enc, opus_int32 application) {
  return ope_encoder_ctl(enc, OPUS_SET_APPLICATION(application));
}

int shim_ope_encoder_ctl_set_bitrate(OggOpusEnc *enc, opus_int32 bitrate) {
  return ope_encoder_ctl(enc, OPUS_SET_BITRATE(bitrate));
}

int shim_ope_encoder_ctl_set_signal(OggOpusEnc *enc, opus_int32 signal) {
  return ope_encoder_ctl(enc, OPUS_SET_SIGNAL(signal));
}

int shim_ope_encoder_ctl_set_vbr(OggOpusEnc *enc, opus_int32 vbr) {
  return ope_encoder_ctl(enc, OPUS_SET_VBR(vbr));
}
