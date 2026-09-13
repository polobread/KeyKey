#pragma once

struct ca_context;

namespace keykey::linux_ime::fcitx5_adapter {

class ErrorSound {
public:
    ErrorSound() noexcept;
    ~ErrorSound();

    ErrorSound(const ErrorSound &) = delete;
    ErrorSound &operator=(const ErrorSound &) = delete;

    void play() const noexcept;

private:
    ca_context *context_ = nullptr;
};

} // namespace keykey::linux_ime::fcitx5_adapter
