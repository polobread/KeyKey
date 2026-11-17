/* Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 * JNI transports bytes, candidate policy, owned C ABI handles and keyboard geometry.
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
// Android passes integer pixels. Pack two nonnegative Java ints without
// allocating a JNI object on every keyboard draw or drag.
jlong packKeyboardEdges(const GuanyinmaKeyboardEdges& edges) {
    constexpr auto maxPixel = std::numeric_limits<jint>::max();
    if (!(edges.top >= 0 && edges.top <= maxPixel && edges.bottom >= 0 && edges.bottom <= maxPixel))
        throw std::runtime_error("Guanyinma returned keyboard edges outside Java pixel range");
    return (static_cast<jlong>(edges.top) << 32) | static_cast<jlong>(edges.bottom);
}

jdouble keyboardScalarResult(JNIEnv* env, jclass bridge, int32_t status, double result) {
    try {
        if (status != GUANYINMA_OK) throw std::runtime_error(coreError());
        return result;
    } catch (const std::exception& error) { fail(env, bridge, error.what()); }
    return 0;
}
} // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_tw_chichi77_keykey_android_GuanyinmaNative_nativeDragKeyboardEdge(
    JNIEnv* env, jclass bridge, jint top, jint bottom, jint edge, jint delta,
    jint minimumContent, jint maximumContent, jint maximumTop, jint maximumGap) {
    try {
        GuanyinmaKeyboardEdges result{};
        if (guanyinma_keyboard_drag_edge(top, bottom, static_cast<uint32_t>(edge), delta,
                minimumContent, maximumContent, maximumTop, maximumGap, &result) != GUANYINMA_OK)
            throw std::runtime_error(coreError());
        return packKeyboardEdges(result);
    } catch (const std::exception& error) { fail(env, bridge, error.what()); }
    return 0;
}

extern "C" JNIEXPORT jlong JNICALL
Java_tw_chichi77_keykey_android_GuanyinmaNative_nativeFitKeyboardHeight(
    JNIEnv* env, jclass bridge, jint desiredContent, jint desiredGap, jint windowHeight,
    jint systemSpace, jint minimumContent) {
    try {
        GuanyinmaKeyboardEdges result{};
        if (guanyinma_keyboard_fit_height(desiredContent, desiredGap, windowHeight, systemSpace,
                minimumContent, &result) != GUANYINMA_OK)
            throw std::runtime_error(coreError());
        return packKeyboardEdges(result);
    } catch (const std::exception& error) { fail(env, bridge, error.what()); }
    return 0;
}

extern "C" JNIEXPORT jdouble JNICALL
Java_tw_chichi77_keykey_android_GuanyinmaNative_nativeKeyboardKeycapScale(
    JNIEnv* env, jclass bridge, jdouble areaRatio) {
    double result{};
    const int32_t status = guanyinma_keyboard_keycap_scale(areaRatio, &result);
    return keyboardScalarResult(env, bridge, status, result);
}

extern "C" JNIEXPORT jdouble JNICALL
Java_tw_chichi77_keykey_android_GuanyinmaNative_nativeKeyboardFontSize(
    JNIEnv* env, jclass bridge, jint level, jdouble regularFit, jdouble largestFit) {
    double result{};
    const int32_t status = guanyinma_keyboard_font_size(static_cast<uint32_t>(level),
        regularFit, largestFit, &result);
    return keyboardScalarResult(env, bridge, status, result);
}

extern "C" JNIEXPORT jdouble JNICALL
Java_tw_chichi77_keykey_android_GuanyinmaNative_nativeKeyboardStripScale(
    JNIEnv* env, jclass bridge, jint level) {
    double result{};
    const int32_t status = guanyinma_keyboard_strip_scale(static_cast<uint32_t>(level), &result);
    return keyboardScalarResult(env, bridge, status, result);
}

extern "C" JNIEXPORT jfloatArray JNICALL
Java_tw_chichi77_keykey_android_GuanyinmaNative_nativeKeyboardRowLayout(
    JNIEnv* env, jclass bridge, jdouble leadingUnits, jdouble totalUnits, jint splitIndex,
    jdouble splitGap, jdoubleArray weights) {
    try {
        if (!weights) throw std::runtime_error("Guanyinma keyboard row requires key weights");
        const jsize count = env->GetArrayLength(weights);
        if (!count || count > std::numeric_limits<jsize>::max() / 2)
            throw std::runtime_error("Guanyinma keyboard row has an invalid number of keys");
        std::vector<double> widths(static_cast<size_t>(count));
        env->GetDoubleArrayRegion(weights, 0, count, widths.data());
        if (env->ExceptionCheck()) return nullptr;
        std::vector<GuanyinmaKeyboardSlot> slots(widths.size());
        // Android maps normalized coordinates to pixels when painting and hit-testing.
        if (guanyinma_keyboard_row_layout(1, 0, leadingUnits, totalUnits,
                static_cast<size_t>(splitIndex), splitGap, widths.data(), widths.size(),
                slots.data()) != GUANYINMA_OK)
            throw std::runtime_error(coreError());
        const jsize edgeCount = count * 2;
        std::vector<jfloat> edges(static_cast<size_t>(edgeCount));
        for (size_t index = 0; index < slots.size(); ++index) {
            edges[index * 2] = static_cast<jfloat>(slots[index].left);
            edges[index * 2 + 1] = static_cast<jfloat>(slots[index].right);
        }
        jfloatArray result = env->NewFloatArray(edgeCount);
        if (result) env->SetFloatArrayRegion(result, 0, edgeCount, edges.data());
        return result;
    } catch (const std::exception& error) { fail(env, bridge, error.what()); }
    return nullptr;
}

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
