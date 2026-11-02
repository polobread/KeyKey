// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#include "keykey/linux_ime/candidate_font_support.h"

#include <pango/pangoft2.h>

#include <limits>
#include <stdexcept>
#include <unordered_map>

namespace keykey::linux_ime {

class CandidateFontSupport::Impl {
public:
    Impl() {
        map = pango_ft2_font_map_new();
        if (!map) throw std::runtime_error("Cannot create native font map");
        context = pango_font_map_create_context(map);
        if (!context) {
            g_object_unref(map);
            throw std::runtime_error("Cannot create native font context");
        }
        pango_context_set_language(context, pango_language_from_string("zh-tw"));
        auto *description = pango_font_description_from_string("sans-serif 12");
        pango_context_set_font_description(context, description);
        pango_font_description_free(description);
        layout = pango_layout_new(context);
        if (!layout) {
            g_object_unref(context);
            g_object_unref(map);
            throw std::runtime_error("Cannot create native font layout");
        }
        pango_layout_set_single_paragraph_mode(layout, true);
        // Fail construction when there is no usable system font at all.
        pango_layout_set_text(layout, "A", 1);
        if (pango_layout_get_unknown_glyphs_count(layout) != 0) {
            g_object_unref(layout);
            g_object_unref(context);
            g_object_unref(map);
            throw std::runtime_error("No usable native font for candidate filtering");
        }
    }
    ~Impl() {
        g_object_unref(layout);
        g_object_unref(context);
        g_object_unref(map);
    }

    bool accepts(const std::string &text) const {
        if (text.empty()) return true;
        const auto found = cache.find(text);
        if (found != cache.end()) return found->second;
        if (text.size() > static_cast<std::size_t>(std::numeric_limits<int>::max()) ||
            !g_utf8_validate(text.data(), static_cast<gssize>(text.size()), nullptr)) {
            return false;
        }
        pango_layout_set_text(layout, text.data(), static_cast<int>(text.size()));
        const bool accepted = pango_layout_get_unknown_glyphs_count(layout) == 0;
        // A bounded process-memory cache, never included in user archives.
        if (cache.size() >= 4096) cache.clear();
        cache.emplace(text, accepted);
        return accepted;
    }

    PangoFontMap *map = nullptr;
    PangoContext *context = nullptr;
    PangoLayout *layout = nullptr;
    mutable std::unordered_map<std::string, bool> cache;
};

CandidateFontSupport::CandidateFontSupport() : impl_(std::make_unique<Impl>()) {}
CandidateFontSupport::~CandidateFontSupport() = default;
bool CandidateFontSupport::accepts(const std::string &text) const {
    return impl_->accepts(text);
}

} // namespace keykey::linux_ime
