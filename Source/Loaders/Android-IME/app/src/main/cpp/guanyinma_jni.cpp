/* Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 * JNI only transports bytes, candidate policy and owned C ABI handles.
 * No input-method algorithm or Android-specific core policy lives here.
 */
#include <jni.h>
#include "guanyinma.h"
#include <cstdint>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
jbyteArray bytes(JNIEnv* env, const uint8_t* value, size_t length) {
    if (length > static_cast<size_t>(std::numeric_limits<jsize>::max()))
        throw std::runtime_error("Guanyinma UTF-8 result is too large for Java");
    jbyteArray result = env->NewByteArray(static_cast<jsize>(length));
    if (result && length)
        env->SetByteArrayRegion(result, 0, static_cast<jsize>(length),
                               reinterpret_cast<const jbyte*>(value));
    return result;
}

jstring text(JNIEnv* env, jclass bridge, const uint8_t* value, size_t length) {
    jbyteArray input = bytes(env, value, length);
    if (!input) return nullptr;
    jmethodID decode = env->GetStaticMethodID(bridge, "decodeUtf8", "([B)Ljava/lang/String;");
    jstring result = decode ? static_cast<jstring>(env->CallStaticObjectMethod(bridge, decode, input)) : nullptr;
    const bool failed = env->ExceptionCheck();
    env->DeleteLocalRef(input);
    return failed ? nullptr : result;
}

void fail(JNIEnv* env, jclass bridge, const std::string& message, jthrowable cause = nullptr) {
    if (env->ExceptionCheck()) return;
    jstring description = text(env, bridge,
        reinterpret_cast<const uint8_t*>(message.data()), message.size());
    if (!description) return;
    jclass type = env->FindClass("java/lang/RuntimeException");
    if (type) {
        jmethodID constructor = env->GetMethodID(type, "<init>", "(Ljava/lang/String;Ljava/lang/Throwable;)V");
        if (constructor) {
            jthrowable error = static_cast<jthrowable>(env->NewObject(type, constructor, description, cause));
            const bool failed = env->ExceptionCheck();
            if (error && !failed) env->Throw(error);
            if (error) env->DeleteLocalRef(error);
        }
        env->DeleteLocalRef(type);
    }
    env->DeleteLocalRef(description);
}

std::string coreError() {
    size_t required = 0;
    if (guanyinma_last_error(nullptr, 0, &required) != GUANYINMA_BUFFER_TOO_SMALL || !required)
        return "Guanyinma C ABI operation failed";
    std::vector<uint8_t> value(required);
    if (guanyinma_last_error(value.data(), value.size(), &required) != GUANYINMA_OK)
        return "Guanyinma C ABI error could not be copied";
    return std::string(reinterpret_cast<const char*>(value.data()), required - 1);
}

std::vector<uint8_t> inputBytes(JNIEnv* env, jbyteArray value) {
    if (!value) throw std::runtime_error("Guanyinma requires UTF-8 input bytes");
    const jsize size = env->GetArrayLength(value);
    std::vector<uint8_t> result(static_cast<size_t>(size));
    if (size) env->GetByteArrayRegion(value, 0, size, reinterpret_cast<jbyte*>(result.data()));
    return result;
}

struct Session {
    JavaVM* vm = nullptr;
    jobject glyph = nullptr;
    jclass bridge = nullptr;
    jmethodID predicate = nullptr;
    jthrowable callbackCause = nullptr;
    GuanyinmaSession* core = nullptr;
    std::recursive_mutex mutex;
    bool busy = false;
    bool callbackFailed = false;

    void cleanup(JNIEnv* env) {
        if (core) guanyinma_session_close(&core);
        if (env) {
            if (glyph) env->DeleteGlobalRef(glyph);
            if (bridge) env->DeleteGlobalRef(bridge);
            if (callbackCause) env->DeleteGlobalRef(callbackCause);
        }
        glyph = nullptr; bridge = nullptr; callbackCause = nullptr;
    }
    ~Session() {
        void* raw = nullptr;
        if (vm) vm->GetEnv(&raw, JNI_VERSION_1_6);
        cleanup(static_cast<JNIEnv*>(raw));
    }
    void callbackFailure(JNIEnv* env) {
        callbackFailed = true;
        if (env->ExceptionCheck()) {
            jthrowable cause = env->ExceptionOccurred();
            env->ExceptionClear();
            if (!callbackCause) callbackCause = static_cast<jthrowable>(env->NewGlobalRef(cause));
            env->DeleteLocalRef(cause);
            // A VM allocation failure must not leave an exception pending across
            // the Rust callback boundary either. The operation fails below.
            if (env->ExceptionCheck()) env->ExceptionClear();
        }
    }
};

int32_t GUANYINMA_CALL acceptCandidate(void* context, const uint8_t* value, size_t length) {
    Session* session = static_cast<Session*>(context);
    if (!session->glyph) return 1;
    if (session->callbackFailed) return 0;
    void* raw = nullptr;
    if (session->vm->GetEnv(&raw, JNI_VERSION_1_6) != JNI_OK) {
        session->callbackFailed = true;
        return 0;
    }
    JNIEnv* env = static_cast<JNIEnv*>(raw);
    try {
        jstring candidate = text(env, session->bridge, value, length);
        if (!candidate || env->ExceptionCheck()) { session->callbackFailure(env); return 0; }
        jboolean accepted = env->CallBooleanMethod(session->glyph, session->predicate, candidate);
        const bool failed = env->ExceptionCheck();
        env->DeleteLocalRef(candidate);
        if (failed) { session->callbackFailure(env); return 0; }
        return accepted == JNI_TRUE ? 1 : 0;
    } catch (...) {
        session->callbackFailure(env);
        return 0;
    }
}

std::mutex registryMutex;
std::map<jlong, std::shared_ptr<Session>> registry;
jlong nextToken = 1;

std::shared_ptr<Session> find(jlong token) {
    std::lock_guard<std::mutex> lock(registryMutex);
    const auto found = registry.find(token);
    if (token <= 0 || found == registry.end())
        throw std::runtime_error("Guanyinma session handle is closed or invalid");
    return found->second;
}

struct Operation {
    Session& session;
    std::unique_lock<std::recursive_mutex> lock;
    explicit Operation(Session& value) : session(value), lock(value.mutex) {
        if (!session.core) throw std::runtime_error("Guanyinma session is closed");
        if (session.busy) throw std::runtime_error("Guanyinma callbacks must not reenter their session");
        if (session.callbackFailed) throw std::runtime_error("Guanyinma glyph callback failed; close this session");
        session.busy = true;
    }
    ~Operation() { session.busy = false; }
};

struct Result {
    GuanyinmaResult* value = nullptr;
    ~Result() { if (value) guanyinma_result_close(&value); }
};

jbyteArray resultBytes(JNIEnv* env, GuanyinmaResult* result) {
    size_t required = 0;
    if (guanyinma_result_json(result, nullptr, 0, &required) != GUANYINMA_BUFFER_TOO_SMALL || !required)
        throw std::runtime_error(coreError());
    std::vector<uint8_t> output(required);
    if (guanyinma_result_json(result, output.data(), output.size(), &required) != GUANYINMA_OK)
        throw std::runtime_error(coreError());
    return bytes(env, output.data(), required - 1);
}
} // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_tw_chichi77_keykey_android_GuanyinmaNative_nativeOpen(
    JNIEnv* env, jclass bridge, jbyteArray model, jbyteArray config, jobject glyph) {
    try {
        auto session = std::make_shared<Session>();
        if (env->GetJavaVM(&session->vm) != JNI_OK) throw std::runtime_error("Java VM is unavailable");
        session->bridge = static_cast<jclass>(env->NewGlobalRef(bridge));
        if (!session->bridge) return 0;
        if (glyph) {
            session->glyph = env->NewGlobalRef(glyph);
            jclass type = env->GetObjectClass(glyph);
            if (!type || !session->glyph) return 0;
            session->predicate = env->GetMethodID(type, "test", "(Ljava/lang/Object;)Z");
            env->DeleteLocalRef(type);
            if (!session->predicate) return 0;
        }
        const auto path = inputBytes(env, model);
        const auto options = inputBytes(env, config);
        if (env->ExceptionCheck()) return 0;
        session->busy = true;
        const int32_t status = guanyinma_session_open_with_candidate_filter(path.data(), path.size(),
            options.data(), options.size(), glyph ? acceptCandidate : nullptr, session.get(), &session->core);
        session->busy = false;
        if (session->callbackFailed) {
            fail(env, bridge, "Guanyinma glyph callback failed; session was not opened", session->callbackCause);
            return 0;
        }
        if (status != GUANYINMA_OK) throw std::runtime_error(coreError());
        std::lock_guard<std::mutex> lock(registryMutex);
        if (nextToken == std::numeric_limits<jlong>::max())
            throw std::runtime_error("Guanyinma session token space is exhausted");
        const jlong token = nextToken++;
        registry.emplace(token, session);
        return token;
    } catch (const std::exception& error) { fail(env, bridge, error.what()); }
      catch (...) { fail(env, bridge, "Guanyinma native allocation failed"); }
    return 0;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_tw_chichi77_keykey_android_GuanyinmaNative_nativeRead(
    JNIEnv* env, jclass bridge, jlong token, jint operation, jbyteArray input) {
    try {
        auto session = find(token);
        Operation active(*session);
        Result result;
        int32_t status;
        if (operation == 0) {
            const auto value = inputBytes(env, input);
            if (env->ExceptionCheck()) return nullptr;
            status = guanyinma_session_apply(session->core, value.data(), value.size(), &result.value);
        } else if (operation == 1) {
            status = guanyinma_session_snapshot(session->core, &result.value);
        } else if (operation == 2) {
            status = guanyinma_session_user_data(session->core, &result.value);
        } else throw std::runtime_error("Unknown Guanyinma JNI read operation");
        if (session->callbackFailed) {
            fail(env, bridge, "Guanyinma glyph callback failed; close this session", session->callbackCause);
            return nullptr;
        }
        if (status != GUANYINMA_OK) throw std::runtime_error(coreError());
        return resultBytes(env, result.value);
    } catch (const std::exception& error) { fail(env, bridge, error.what()); }
      catch (...) { fail(env, bridge, "Guanyinma native allocation failed"); }
    return nullptr;
}

extern "C" JNIEXPORT void JNICALL
Java_tw_chichi77_keykey_android_GuanyinmaNative_nativeClose(JNIEnv* env, jclass bridge, jlong token) {
    try {
        std::shared_ptr<Session> session;
        {
            std::lock_guard<std::mutex> lock(registryMutex);
            const auto found = registry.find(token);
            if (found == registry.end()) return; // AutoCloseable close is idempotent.
            session = found->second;
        }
        std::lock_guard<std::recursive_mutex> active(session->mutex);
        if (session->busy) throw std::runtime_error("Guanyinma callbacks must not close their session");
        {
            std::lock_guard<std::mutex> lock(registryMutex);
            registry.erase(token);
        }
        session->cleanup(env);
    } catch (const std::exception& error) { fail(env, bridge, error.what()); }
      catch (...) { fail(env, bridge, "Guanyinma session close failed"); }
}
