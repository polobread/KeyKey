#pragma once
#include <Windows.h>
#include <mutex>

namespace KeyKey::WindowsTsf {

// Explicitly retired outside DllMain. Registration can be retried after a
// failure or a successful DllCanUnloadNow that did not actually unload us.
class WindowClass final {
public:
    bool ensure(const WNDCLASSEXW& definition) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (registered_) return true;
        if (!RegisterClassExW(&definition)) {
            if (GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
            WNDCLASSEXW existing{sizeof(existing)};
            if (!GetClassInfoExW(definition.hInstance, definition.lpszClassName, &existing) ||
                existing.hInstance != definition.hInstance ||
                existing.lpfnWndProc != definition.lpfnWndProc) return false;
        }
        name_ = definition.lpszClassName;
        module_ = definition.hInstance;
        registered_ = true;
        return true;
    }

    bool retire() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!registered_) return true;
        if (!UnregisterClassW(name_, module_) && GetLastError() != ERROR_CLASS_DOES_NOT_EXIST)
            return false; // Includes a surviving HWND: keep its callback loaded.
        registered_ = false;
        return true;
    }

private:
    std::mutex mutex_;
    const wchar_t* name_ = nullptr;
    HINSTANCE module_ = nullptr;
    bool registered_ = false;
};

} // namespace KeyKey::WindowsTsf
