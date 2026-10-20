// Transient frontend mode. Startup preference is read once per IMK process.
#pragma once
struct IMKInputMode {
    bool english = false;
    bool initialized = false;
    void initialize(bool defaultEnglish) {
        if (!initialized) {
            english = defaultEnglish;
            initialized = true;
        }
    }
};
