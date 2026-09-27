#include "error_sound.h"

#include <canberra.h>

namespace keykey::linux_ime::fcitx5_adapter {

ErrorSound::ErrorSound() noexcept {
    ca_context *context = nullptr;
    if (ca_context_create(&context) != CA_SUCCESS) {
        return;
    }
    context_ = context;
    ca_context_change_props(
        context_, CA_PROP_APPLICATION_NAME, "chichi77 KeyKey",
        CA_PROP_APPLICATION_ID, "io.github.polobread.inputmethod.chichi77",
        CA_PROP_APPLICATION_ICON_NAME, "input-keyboard", nullptr);
}

ErrorSound::~ErrorSound() {
    if (context_ != nullptr) {
        ca_context_destroy(context_);
    }
}

void ErrorSound::play() const noexcept {
    if (context_ == nullptr) {
        return;
    }
    ca_context_play(context_, 0, CA_PROP_EVENT_ID, "bell-window-system",
                    CA_PROP_EVENT_DESCRIPTION, "Typing error",
                    CA_PROP_CANBERRA_CACHE_CONTROL, "permanent", nullptr);
}

} // namespace keykey::linux_ime::fcitx5_adapter
