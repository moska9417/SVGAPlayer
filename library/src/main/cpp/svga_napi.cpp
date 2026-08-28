#include "svga_napi.h"

#include <cstdint>
#include <cstring>
#include <exception>
#include <new>
#include <string>
#include <utility>
#include <vector>

#include "svga_parser.h"

namespace svgaplayer {
namespace {

namespace proto = com::opensource::svga;

constexpr std::size_t MAX_COMPRESSED_SIZE = 64U * 1024U * 1024U;

struct AsyncParseContext {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<std::uint8_t> input;
    ParseResult result;
};

napi_value CreateObject(napi_env env)
{
    napi_value value = nullptr;
    return napi_create_object(env, &value) == napi_ok ? value : nullptr;
}

napi_value CreateString(napi_env env, const std::string& text)
{
    napi_value value = nullptr;
    return napi_create_string_utf8(env, text.data(), text.size(), &value) == napi_ok ? value : nullptr;
}

napi_value CreateInt32(napi_env env, std::int32_t number)
{
    napi_value value = nullptr;
    return napi_create_int32(env, number, &value) == napi_ok ? value : nullptr;
}

napi_value CreateDouble(napi_env env, double number)
{
    napi_value value = nullptr;
    return napi_create_double(env, number, &value) == napi_ok ? value : nullptr;
}

bool SetValue(napi_env env, napi_value object, const char* name, napi_value value)
{
    return object != nullptr && value != nullptr && napi_set_named_property(env, object, name, value) == napi_ok;
}

bool SetString(napi_env env, napi_value object, const char* name, const std::string& text)
{
    return SetValue(env, object, name, CreateString(env, text));
}

bool SetInt32(napi_env env, napi_value object, const char* name, std::int32_t number)
{
    return SetValue(env, object, name, CreateInt32(env, number));
}

bool SetDouble(napi_env env, napi_value object, const char* name, double number)
{
    return SetValue(env, object, name, CreateDouble(env, number));
}

napi_value CreateColor(napi_env env, const proto::ShapeEntity_ShapeStyle_RGBAColor& color)
{
    napi_value object = CreateObject(env);
    if (!SetDouble(env, object, "r", color.r()) ||
        !SetDouble(env, object, "g", color.g()) ||
        !SetDouble(env, object, "b", color.b()) ||
        !SetDouble(env, object, "a", color.a())) {
        return nullptr;
    }
    return object;
}

napi_value CreateLayout(napi_env env, const proto::Layout& layout)
{
    napi_value object = CreateObject(env);
    if (!SetDouble(env, object, "x", layout.x()) ||
        !SetDouble(env, object, "y", layout.y()) ||
        !SetDouble(env, object, "width", layout.width()) ||
        !SetDouble(env, object, "height", layout.height())) {
        return nullptr;
    }
    return object;
}

napi_value CreateTransform(napi_env env, const proto::Transform& transform)
{
    napi_value object = CreateObject(env);
    if (!SetDouble(env, object, "a", transform.a()) ||
        !SetDouble(env, object, "b", transform.b()) ||
        !SetDouble(env, object, "c", transform.c()) ||
        !SetDouble(env, object, "d", transform.d()) ||
        !SetDouble(env, object, "tx", transform.tx()) ||
        !SetDouble(env, object, "ty", transform.ty())) {
        return nullptr;
    }
    return object;
}

napi_value CreateShapeStyle(napi_env env, const proto::ShapeEntity_ShapeStyle& style)
{
    napi_value object = CreateObject(env);
    if (object == nullptr) {
        return nullptr;
    }
    if (style.has_fill() && !SetValue(env, object, "fill", CreateColor(env, style.fill()))) {
        return nullptr;
    }
    if (style.has_stroke() && !SetValue(env, object, "stroke", CreateColor(env, style.stroke()))) {
        return nullptr;
    }
    if (!SetDouble(env, object, "strokeWidth", style.strokewidth()) ||
        !SetInt32(env, object, "lineCap", static_cast<std::int32_t>(style.linecap())) ||
        !SetInt32(env, object, "lineJoin", static_cast<std::int32_t>(style.linejoin())) ||
        !SetDouble(env, object, "miterLimit", style.miterlimit()) ||
        !SetDouble(env, object, "lineDashI", style.linedashi()) ||
        !SetDouble(env, object, "lineDashII", style.linedashii()) ||
        !SetDouble(env, object, "lineDashIII", style.linedashiii())) {
        return nullptr;
    }
    return object;
}

napi_value CreateShapeArgs(napi_env env, const proto::ShapeEntity_ShapeArgs& args)
{
    napi_value object = CreateObject(env);
    return SetString(env, object, "d", args.d()) ? object : nullptr;
}

napi_value CreateRectArgs(napi_env env, const proto::ShapeEntity_RectArgs& args)
{
    napi_value object = CreateObject(env);
    if (!SetDouble(env, object, "x", args.x()) ||
        !SetDouble(env, object, "y", args.y()) ||
        !SetDouble(env, object, "width", args.width()) ||
        !SetDouble(env, object, "height", args.height()) ||
        !SetDouble(env, object, "cornerRadius", args.cornerradius())) {
        return nullptr;
    }
    return object;
}

napi_value CreateEllipseArgs(napi_env env, const proto::ShapeEntity_EllipseArgs& args)
{
    napi_value object = CreateObject(env);
    if (!SetDouble(env, object, "x", args.x()) ||
        !SetDouble(env, object, "y", args.y()) ||
        !SetDouble(env, object, "radiusX", args.radiusx()) ||
        !SetDouble(env, object, "radiusY", args.radiusy())) {
        return nullptr;
    }
    return object;
}

napi_value CreateShape(napi_env env, const proto::ShapeEntity& shape)
{
    napi_value object = CreateObject(env);
    if (!SetInt32(env, object, "type", static_cast<std::int32_t>(shape.type()))) {
        return nullptr;
    }

    switch (shape.args_case()) {
        case proto::ShapeEntity::kShape:
            if (!SetValue(env, object, "shape", CreateShapeArgs(env, shape.shape()))) {
                return nullptr;
            }
            break;
        case proto::ShapeEntity::kRect:
            if (!SetValue(env, object, "rect", CreateRectArgs(env, shape.rect()))) {
                return nullptr;
            }
            break;
        case proto::ShapeEntity::kEllipse:
            if (!SetValue(env, object, "ellipse", CreateEllipseArgs(env, shape.ellipse()))) {
                return nullptr;
            }
            break;
        case proto::ShapeEntity::ARGS_NOT_SET:
            break;
    }

    if (shape.has_styles() && !SetValue(env, object, "styles", CreateShapeStyle(env, shape.styles()))) {
        return nullptr;
    }
    if (shape.has_transform() &&
        !SetValue(env, object, "transform", CreateTransform(env, shape.transform()))) {
        return nullptr;
    }
    return object;
}

napi_value CreateShapes(napi_env env, const proto::FrameEntity& frame)
{
    napi_value array = nullptr;
    if (napi_create_array_with_length(env, static_cast<std::size_t>(frame.shapes_size()), &array) != napi_ok) {
        return nullptr;
    }
    for (int index = 0; index < frame.shapes_size(); ++index) {
        napi_value shape = CreateShape(env, frame.shapes(index));
        if (shape == nullptr || napi_set_element(env, array, static_cast<std::uint32_t>(index), shape) != napi_ok) {
            return nullptr;
        }
    }
    return array;
}

napi_value CreateFrame(napi_env env, const proto::FrameEntity& frame)
{
    napi_value object = CreateObject(env);
    if (!SetDouble(env, object, "alpha", frame.alpha())) {
        return nullptr;
    }
    if (frame.has_layout() && !SetValue(env, object, "layout", CreateLayout(env, frame.layout()))) {
        return nullptr;
    }
    if (frame.has_transform() &&
        !SetValue(env, object, "transform", CreateTransform(env, frame.transform()))) {
        return nullptr;
    }
    if (!frame.clippath().empty() && !SetString(env, object, "clipPath", frame.clippath())) {
        return nullptr;
    }
    if (frame.shapes_size() > 0 && !SetValue(env, object, "shapes", CreateShapes(env, frame))) {
        return nullptr;
    }
    return object;
}

napi_value CreateFrames(napi_env env, const proto::SpriteEntity& sprite)
{
    napi_value array = nullptr;
    if (napi_create_array_with_length(env, static_cast<std::size_t>(sprite.frames_size()), &array) != napi_ok) {
        return nullptr;
    }
    for (int index = 0; index < sprite.frames_size(); ++index) {
        napi_value frame = CreateFrame(env, sprite.frames(index));
        if (frame == nullptr || napi_set_element(env, array, static_cast<std::uint32_t>(index), frame) != napi_ok) {
            return nullptr;
        }
    }
    return array;
}

napi_value CreateSprite(napi_env env, const proto::SpriteEntity& sprite)
{
    napi_value object = CreateObject(env);
    if (!SetString(env, object, "imageKey", sprite.imagekey()) ||
        !SetValue(env, object, "frames", CreateFrames(env, sprite))) {
        return nullptr;
    }
    if (!sprite.mattekey().empty() && !SetString(env, object, "matteKey", sprite.mattekey())) {
        return nullptr;
    }
    return object;
}

napi_value CreateSprites(napi_env env, const proto::MovieEntity& movie)
{
    napi_value array = nullptr;
    if (napi_create_array_with_length(env, static_cast<std::size_t>(movie.sprites_size()), &array) != napi_ok) {
        return nullptr;
    }
    for (int index = 0; index < movie.sprites_size(); ++index) {
        napi_value sprite = CreateSprite(env, movie.sprites(index));
        if (sprite == nullptr || napi_set_element(env, array, static_cast<std::uint32_t>(index), sprite) != napi_ok) {
            return nullptr;
        }
    }
    return array;
}

napi_value CreateAudio(napi_env env, const proto::AudioEntity& audio)
{
    napi_value object = CreateObject(env);
    if (!SetString(env, object, "audioKey", audio.audiokey()) ||
        !SetInt32(env, object, "startFrame", audio.startframe()) ||
        !SetInt32(env, object, "endFrame", audio.endframe()) ||
        !SetInt32(env, object, "startTime", audio.starttime()) ||
        !SetInt32(env, object, "totalTime", audio.totaltime())) {
        return nullptr;
    }
    return object;
}

napi_value CreateAudios(napi_env env, const proto::MovieEntity& movie)
{
    napi_value array = nullptr;
    if (napi_create_array_with_length(env, static_cast<std::size_t>(movie.audios_size()), &array) != napi_ok) {
        return nullptr;
    }
    for (int index = 0; index < movie.audios_size(); ++index) {
        napi_value audio = CreateAudio(env, movie.audios(index));
        if (audio == nullptr || napi_set_element(env, array, static_cast<std::uint32_t>(index), audio) != napi_ok) {
            return nullptr;
        }
    }
    return array;
}

napi_value CreateImage(napi_env env, const std::string& key, const std::string& bytes)
{
    napi_value data = nullptr;
    void* destination = nullptr;
    if (napi_create_arraybuffer(env, bytes.size(), &destination, &data) != napi_ok) {
        return nullptr;
    }
    if (!bytes.empty()) {
        std::memcpy(destination, bytes.data(), bytes.size());
    }

    napi_value object = CreateObject(env);
    if (!SetString(env, object, "key", key) || !SetValue(env, object, "data", data)) {
        return nullptr;
    }
    return object;
}

napi_value CreateImages(napi_env env, const proto::MovieEntity& movie)
{
    napi_value array = nullptr;
    if (napi_create_array_with_length(env, static_cast<std::size_t>(movie.images_size()), &array) != napi_ok) {
        return nullptr;
    }

    std::uint32_t index = 0;
    for (const auto& entry : movie.images()) {
        napi_value image = CreateImage(env, entry.first, entry.second);
        if (image == nullptr || napi_set_element(env, array, index, image) != napi_ok) {
            return nullptr;
        }
        ++index;
    }
    return array;
}

napi_value CreateParams(napi_env env, const proto::MovieParams& params)
{
    napi_value object = CreateObject(env);
    if (!SetDouble(env, object, "viewBoxWidth", params.viewboxwidth()) ||
        !SetDouble(env, object, "viewBoxHeight", params.viewboxheight()) ||
        !SetInt32(env, object, "fps", params.fps()) ||
        !SetInt32(env, object, "frames", params.frames())) {
        return nullptr;
    }
    return object;
}

napi_value CreateMovie(napi_env env, const proto::MovieEntity& movie)
{
    napi_value object = CreateObject(env);
    if (!SetString(env, object, "version", movie.version())) {
        return nullptr;
    }
    if (movie.has_params() && !SetValue(env, object, "params", CreateParams(env, movie.params()))) {
        return nullptr;
    }
    if (!SetValue(env, object, "images", CreateImages(env, movie)) ||
        !SetValue(env, object, "sprites", CreateSprites(env, movie)) ||
        !SetValue(env, object, "audios", CreateAudios(env, movie))) {
        return nullptr;
    }
    return object;
}

napi_value CreateError(napi_env env, const char* code, const std::string& message)
{
    napi_value codeValue = CreateString(env, code);
    napi_value messageValue = CreateString(env, message);
    napi_value error = nullptr;
    if (codeValue == nullptr || messageValue == nullptr ||
        napi_create_error(env, codeValue, messageValue, &error) != napi_ok) {
        return nullptr;
    }
    SetValue(env, error, "code", codeValue);
    return error;
}

void Reject(napi_env env, napi_deferred deferred, const char* code, const std::string& message)
{
    napi_value error = CreateError(env, code, message);
    if (error == nullptr) {
        napi_get_undefined(env, &error);
    }
    napi_reject_deferred(env, deferred, error);
}

void ExecuteParse(napi_env env, void* data)
{
    (void)env;
    auto* context = static_cast<AsyncParseContext*>(data);
    try {
        context->result = Parse(context->input);
    } catch (const std::bad_alloc&) {
        context->result.errorCode = ParseErrorCode::OUT_OF_MEMORY;
        context->result.errorMessage = "Insufficient memory while parsing SVGA data";
    } catch (const std::exception& error) {
        context->result.errorCode = ParseErrorCode::INTERNAL_FAILED;
        context->result.errorMessage = std::string("Unexpected SVGA parser failure: ") + error.what();
    } catch (...) {
        context->result.errorCode = ParseErrorCode::INTERNAL_FAILED;
        context->result.errorMessage = "Unexpected SVGA parser failure";
    }
    std::vector<std::uint8_t>().swap(context->input);
}

void CompleteParse(napi_env env, napi_status status, void* data)
{
    auto* context = static_cast<AsyncParseContext*>(data);
    if (status == napi_cancelled) {
        Reject(env, context->deferred, "SVGA_CANCELLED", "SVGA parse work was cancelled");
    } else if (status != napi_ok) {
        Reject(env, context->deferred, "SVGA_ASYNC_FAILED", "SVGA parse work failed");
    } else if (!context->result.IsSuccess()) {
        Reject(env,
               context->deferred,
               ParseErrorCodeName(context->result.errorCode),
               context->result.errorMessage);
    } else {
        napi_value movie = CreateMovie(env, *context->result.movie);
        if (movie == nullptr) {
            Reject(env, context->deferred, "SVGA_MODEL_FAILED", "Failed to create ArkTS SVGA model");
        } else {
            napi_resolve_deferred(env, context->deferred, movie);
        }
    }

    napi_delete_async_work(env, context->work);
    delete context;
}

bool ReadInput(napi_env env, napi_value value, std::vector<std::uint8_t>& output, std::string& error)
{
    bool isTypedArray = false;
    if (napi_is_typedarray(env, value, &isTypedArray) != napi_ok || !isTypedArray) {
        error = "parse expects a Uint8Array";
        return false;
    }

    napi_typedarray_type type = napi_uint8_array;
    std::size_t length = 0;
    void* data = nullptr;
    napi_value arrayBuffer = nullptr;
    std::size_t byteOffset = 0;
    if (napi_get_typedarray_info(env, value, &type, &length, &data, &arrayBuffer, &byteOffset) != napi_ok ||
        type != napi_uint8_array) {
        error = "parse expects a Uint8Array";
        return false;
    }
    if (length > MAX_COMPRESSED_SIZE) {
        error = "compressed SVGA data exceeds 64 MiB";
        return false;
    }
    if (length > 0 && data == nullptr) {
        error = "Uint8Array data is unavailable";
        return false;
    }

    if (length > 0) {
        const auto* begin = static_cast<const std::uint8_t*>(data);
        output.assign(begin, begin + length);
    }
    return true;
}

} // namespace

napi_value ParseAsync(napi_env env, napi_callback_info info)
{
    std::size_t argumentCount = 1;
    napi_value arguments[1] = {nullptr};
    if (napi_get_cb_info(env, info, &argumentCount, arguments, nullptr, nullptr) != napi_ok) {
        return nullptr;
    }

    napi_deferred deferred = nullptr;
    napi_value promise = nullptr;
    if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
        return nullptr;
    }
    if (argumentCount < 1) {
        Reject(env, deferred, "SVGA_INVALID_ARGUMENT", "parse expects a Uint8Array");
        return promise;
    }

    auto* context = new AsyncParseContext();
    context->deferred = deferred;
    std::string inputError;
    if (!ReadInput(env, arguments[0], context->input, inputError)) {
        Reject(env, deferred, "SVGA_INVALID_ARGUMENT", inputError);
        delete context;
        return promise;
    }

    napi_value resourceName = CreateString(env, "SVGAPlayerParse");
    if (resourceName == nullptr ||
        napi_create_async_work(env,
                               nullptr,
                               resourceName,
                               ExecuteParse,
                               CompleteParse,
                               context,
                               &context->work) != napi_ok) {
        Reject(env, deferred, "SVGA_ASYNC_FAILED", "Failed to create SVGA parse work");
        delete context;
        return promise;
    }
    if (napi_queue_async_work(env, context->work) != napi_ok) {
        Reject(env, deferred, "SVGA_ASYNC_FAILED", "Failed to queue SVGA parse work");
        napi_delete_async_work(env, context->work);
        delete context;
        return promise;
    }
    return promise;
}

} // namespace svgaplayer
