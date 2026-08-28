// Compatibility configuration for the prebuilt protobuf.hnp Abseil ABI.
//
// The HNP static libraries expose std::string_view symbols, while the packaged
// absl/base/options.h selects Abseil's custom string_view implementation. Keep
// all packaged options unchanged except ABSL_OPTION_USE_STD_STRING_VIEW.

#ifndef ABSL_BASE_OPTIONS_H_
#define ABSL_BASE_OPTIONS_H_

#define ABSL_OPTION_USE_STD_STRING_VIEW 1
#define ABSL_OPTION_USE_STD_ORDERING 0
#define ABSL_OPTION_USE_INLINE_NAMESPACE 1
#define ABSL_OPTION_INLINE_NAMESPACE_NAME lts_20250512
#define ABSL_OPTION_HARDENED 0

#endif // ABSL_BASE_OPTIONS_H_
