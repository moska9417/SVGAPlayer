#ifndef SVGAPLAYER_NAPI_H
#define SVGAPLAYER_NAPI_H

#include <napi/native_api.h>

namespace svgaplayer {

napi_value ParseAsync(napi_env env, napi_callback_info info);

} // namespace svgaplayer

#endif // SVGAPLAYER_NAPI_H
