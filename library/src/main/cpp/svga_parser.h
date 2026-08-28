#ifndef SVGAPLAYER_PARSER_H
#define SVGAPLAYER_PARSER_H

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "generated/svga.pb.h"

namespace svgaplayer {

enum class ParseErrorCode {
    NONE = 0,
    EMPTY_INPUT,
    INPUT_TOO_LARGE,
    UNSUPPORTED_FORMAT,
    INFLATE_INIT_FAILED,
    INFLATE_FAILED,
    OUTPUT_TOO_LARGE,
    PROTOBUF_FAILED,
    OUT_OF_MEMORY,
    INTERNAL_FAILED,
};

struct ParseResult {
    ParseErrorCode errorCode = ParseErrorCode::NONE;
    std::string errorMessage;
    std::unique_ptr<com::opensource::svga::MovieEntity> movie;
    std::size_t inflatedSize = 0;

    bool IsSuccess() const
    {
        return errorCode == ParseErrorCode::NONE && movie != nullptr;
    }
};

const char* ParseErrorCodeName(ParseErrorCode code);
ParseResult Parse(const std::vector<std::uint8_t>& compressedData);

} // namespace svgaplayer

#endif // SVGAPLAYER_PARSER_H
