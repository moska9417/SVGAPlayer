#include "svga_parser.h"

#include <algorithm>
#include <climits>
#include <utility>

#include <zlib.h>

namespace svgaplayer {
namespace {

constexpr std::size_t MAX_COMPRESSED_SIZE = 64U * 1024U * 1024U;
constexpr std::size_t MAX_INFLATED_SIZE = 256U * 1024U * 1024U;
constexpr std::size_t INFLATE_CHUNK_SIZE = 64U * 1024U;

ParseResult Error(ParseErrorCode code, std::string message)
{
    ParseResult result;
    result.errorCode = code;
    result.errorMessage = std::move(message);
    return result;
}

bool IsZip(const std::vector<std::uint8_t>& data)
{
    return data.size() >= 4 && data[0] == 'P' && data[1] == 'K' && data[2] == 0x03 && data[3] == 0x04;
}

ParseResult Inflate(const std::vector<std::uint8_t>& compressedData, std::vector<std::uint8_t>& output)
{
    z_stream stream = {};
    stream.next_in = const_cast<Bytef*>(reinterpret_cast<const Bytef*>(compressedData.data()));
    stream.avail_in = static_cast<uInt>(compressedData.size());

    const int initResult = inflateInit(&stream);
    if (initResult != Z_OK) {
        return Error(ParseErrorCode::INFLATE_INIT_FAILED,
                     "zlib inflateInit failed with code " + std::to_string(initResult));
    }

    int inflateResult = Z_OK;
    while (inflateResult != Z_STREAM_END) {
        if (output.size() >= MAX_INFLATED_SIZE) {
            inflateEnd(&stream);
            return Error(ParseErrorCode::OUTPUT_TOO_LARGE,
                         "inflated SVGA data exceeds 256 MiB");
        }

        const std::size_t oldSize = output.size();
        const std::size_t availableSize = std::min(INFLATE_CHUNK_SIZE, MAX_INFLATED_SIZE - oldSize);
        output.resize(oldSize + availableSize);
        stream.next_out = reinterpret_cast<Bytef*>(output.data() + oldSize);
        stream.avail_out = static_cast<uInt>(availableSize);

        inflateResult = inflate(&stream, Z_NO_FLUSH);
        const std::size_t producedSize = availableSize - stream.avail_out;
        output.resize(oldSize + producedSize);

        if (inflateResult != Z_OK && inflateResult != Z_STREAM_END) {
            const std::string zlibMessage = stream.msg == nullptr ? "" : std::string(": ") + stream.msg;
            inflateEnd(&stream);
            return Error(ParseErrorCode::INFLATE_FAILED,
                         "zlib inflate failed with code " + std::to_string(inflateResult) + zlibMessage);
        }

        if (inflateResult == Z_OK && producedSize == 0 && stream.avail_in == 0) {
            inflateEnd(&stream);
            return Error(ParseErrorCode::INFLATE_FAILED,
                         "zlib stream ended before Z_STREAM_END");
        }
    }

    inflateEnd(&stream);
    ParseResult result;
    result.inflatedSize = output.size();
    return result;
}

} // namespace

const char* ParseErrorCodeName(ParseErrorCode code)
{
    switch (code) {
        case ParseErrorCode::NONE:
            return "SVGA_OK";
        case ParseErrorCode::EMPTY_INPUT:
            return "SVGA_EMPTY_INPUT";
        case ParseErrorCode::INPUT_TOO_LARGE:
            return "SVGA_INPUT_TOO_LARGE";
        case ParseErrorCode::UNSUPPORTED_FORMAT:
            return "SVGA_UNSUPPORTED_FORMAT";
        case ParseErrorCode::INFLATE_INIT_FAILED:
            return "SVGA_INFLATE_INIT_FAILED";
        case ParseErrorCode::INFLATE_FAILED:
            return "SVGA_INFLATE_FAILED";
        case ParseErrorCode::OUTPUT_TOO_LARGE:
            return "SVGA_OUTPUT_TOO_LARGE";
        case ParseErrorCode::PROTOBUF_FAILED:
            return "SVGA_PROTOBUF_FAILED";
        case ParseErrorCode::OUT_OF_MEMORY:
            return "SVGA_OUT_OF_MEMORY";
        case ParseErrorCode::INTERNAL_FAILED:
            return "SVGA_INTERNAL_FAILED";
    }
    return "SVGA_UNKNOWN_ERROR";
}

ParseResult Parse(const std::vector<std::uint8_t>& compressedData)
{
    if (compressedData.empty()) {
        return Error(ParseErrorCode::EMPTY_INPUT, "SVGA input is empty");
    }
    if (compressedData.size() > MAX_COMPRESSED_SIZE) {
        return Error(ParseErrorCode::INPUT_TOO_LARGE,
                     "compressed SVGA data exceeds 64 MiB");
    }
    if (IsZip(compressedData)) {
        return Error(ParseErrorCode::UNSUPPORTED_FORMAT,
                     "SVGA 1.x ZIP format is not supported yet");
    }

    std::vector<std::uint8_t> protobufData;
    ParseResult inflateResult = Inflate(compressedData, protobufData);
    if (inflateResult.errorCode != ParseErrorCode::NONE) {
        return inflateResult;
    }
    if (protobufData.size() > static_cast<std::size_t>(INT_MAX)) {
        return Error(ParseErrorCode::OUTPUT_TOO_LARGE,
                     "protobuf payload exceeds parser size limit");
    }

    auto movie = std::make_unique<com::opensource::svga::MovieEntity>();
    if (!movie->ParseFromArray(protobufData.data(), static_cast<int>(protobufData.size()))) {
        return Error(ParseErrorCode::PROTOBUF_FAILED,
                     "SVGA protobuf MovieEntity parsing failed");
    }

    ParseResult result;
    result.movie = std::move(movie);
    result.inflatedSize = protobufData.size();
    return result;
}

} // namespace svgaplayer
