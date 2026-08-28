#include <string>

#include <google/protobuf/stubs/common.h>
#include <napi/native_api.h>

#include "svga_napi.h"

namespace {

napi_value ProtobufVersion(napi_env env, napi_callback_info info)
{
    (void)info;
    const std::string version =
        google::protobuf::internal::VersionString(GOOGLE_PROTOBUF_VERSION);

    napi_value result = nullptr;
    napi_create_string_utf8(env, version.c_str(), version.size(), &result);
    return result;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"protobufVersion", nullptr, ProtobufVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"parse", nullptr, svgaplayer::ParseAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

} // namespace

static napi_module g_svgaModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "svgaplayer",
    .nm_priv = nullptr,
    .reserved = {nullptr, nullptr, nullptr, nullptr},
};

extern "C" __attribute__((constructor)) void RegisterSvgaplayerModule()
{
    napi_module_register(&g_svgaModule);
}
