/* Standalone C consumer for Guanyinma model, session and user-data C ABI.
 * Copyright (c) 2026 Chui-Ping Cheng
 * SPDX-License-Identifier: MIT
 *
 * Usage: c_abi_smoke /absolute/path/to/KeyKey.db /scratch/user-data.db
 * The model stays read-only; writes use only the explicit disposable user store.
 * This executable does not initialize a frontend.
 */
#include "guanyinma.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <wchar.h>
#endif

static unsigned checks = 0;

static void print_last_error(void) {
    size_t required = 0;
    if (guanyinma_last_error(NULL, 0, &required) != GUANYINMA_BUFFER_TOO_SMALL ||
        required == 0) {
        return;
    }
    uint8_t *message = (uint8_t *)malloc(required);
    if (message == NULL) {
        return;
    }
    if (guanyinma_last_error(message, required, &required) == GUANYINMA_OK) {
        fprintf(stderr, "Guanyinma error: %s\n", (const char *)message);
    }
    free(message);
}

static void require_at(int condition, const char *expression, int line) {
    ++checks;
    if (!condition) {
        fprintf(stderr, "C ABI smoke failed at line %d: %s\n", line, expression);
        print_last_error();
        exit(EXIT_FAILURE);
    }
}

static void status_at(int32_t actual, int32_t expected,
                      const char *expression, int line) {
    ++checks;
    if (actual != expected) {
        fprintf(stderr,
                "C ABI smoke failed at line %d: %s returned %" PRId32
                ", expected %" PRId32 "\n",
                line, expression, actual, expected);
        print_last_error();
        exit(EXIT_FAILURE);
    }
}

#define REQUIRE(expression) require_at((expression), #expression, __LINE__)
#define STATUS(expression, expected) \
    status_at((expression), (expected), #expression, __LINE__)

static char *result_json(const GuanyinmaResult *result) {
    size_t required = 0;
    STATUS(guanyinma_result_json(result, NULL, 0, &required),
           GUANYINMA_BUFFER_TOO_SMALL);
    REQUIRE(required > 1);
    uint8_t *bytes = (uint8_t *)malloc(required);
    REQUIRE(bytes != NULL);
    const size_t capacity = required;
    memset(bytes, 0xa5, capacity);
    STATUS(guanyinma_result_json(result, bytes, capacity, &required),
           GUANYINMA_OK);
    REQUIRE(required == capacity);
    REQUIRE(bytes[capacity - 1] == 0);
    REQUIRE(strlen((const char *)bytes) + 1 == capacity);
    return (char *)bytes;
}

static GuanyinmaResult *query(GuanyinmaDatabase *database, uint32_t kind,
                             const char *key) {
    GuanyinmaResult *result = NULL;
    STATUS(guanyinma_database_query(database, kind, (const uint8_t *)key,
                                    strlen(key), &result),
           GUANYINMA_OK);
    REQUIRE(result != NULL);
    return result;
}

static size_t row_count(const GuanyinmaResult *result) {
    size_t count = SIZE_MAX;
    STATUS(guanyinma_result_row_count(result, &count), GUANYINMA_OK);
    return count;
}

static void close_result(GuanyinmaResult **result) {
    STATUS(guanyinma_result_close(result), GUANYINMA_OK);
    REQUIRE(*result == NULL);
    STATUS(guanyinma_result_close(result), GUANYINMA_OK);
}

static void check_complete_json_copy(GuanyinmaResult *result) {
    size_t required = 0;
    STATUS(guanyinma_result_json(result, NULL, 0, &required),
           GUANYINMA_BUFFER_TOO_SMALL);
    REQUIRE(required > 1);
    uint8_t *bytes = (uint8_t *)malloc(required);
    REQUIRE(bytes != NULL);
    memset(bytes, 0xa5, required);
    size_t observed = SIZE_MAX;
    STATUS(guanyinma_result_json(result, bytes, required - 1, &observed),
           GUANYINMA_BUFFER_TOO_SMALL);
    REQUIRE(observed == required);
    for (size_t index = 0; index < required; ++index) {
        REQUIRE(bytes[index] == 0xa5);
    }
    observed = SIZE_MAX;
    STATUS(guanyinma_result_json(result, NULL, 1, &observed),
           GUANYINMA_INVALID_ARGUMENT);
    STATUS(guanyinma_result_json(result, bytes, required, NULL),
           GUANYINMA_INVALID_ARGUMENT);
    free(bytes);
}

static void check_error_copy(void) {
    size_t required = 0;
    STATUS(guanyinma_last_error(NULL, 0, &required),
           GUANYINMA_BUFFER_TOO_SMALL);
    REQUIRE(required > 1);
    uint8_t *first = (uint8_t *)malloc(required);
    uint8_t *second = (uint8_t *)malloc(required);
    REQUIRE(first != NULL && second != NULL);
    const size_t capacity = required;
    STATUS(guanyinma_last_error(first, capacity, &required), GUANYINMA_OK);
    REQUIRE(required == capacity && first[capacity - 1] == 0);
    STATUS(guanyinma_last_error(second, capacity, &required), GUANYINMA_OK);
    REQUIRE(strcmp((const char *)first, (const char *)second) == 0);

    memset(second, 0xa5, capacity);
    STATUS(guanyinma_last_error(second, capacity - 1, &required),
           GUANYINMA_BUFFER_TOO_SMALL);
    REQUIRE(required == capacity);
    for (size_t index = 0; index < capacity; ++index) {
        REQUIRE(second[index] == 0xa5);
    }
    STATUS(guanyinma_last_error(second, capacity, &required), GUANYINMA_OK);
    REQUIRE(strcmp((const char *)first, (const char *)second) == 0);
    free(second);
    free(first);
}

static void check_invalid_inputs(GuanyinmaDatabase *database,
                                 const char *path) {
    GuanyinmaResult *result = NULL;
    const uint8_t invalid_utf8[] = {0xff};
    const uint8_t embedded_nul[] = {'a', 0, 'b'};

    STATUS(guanyinma_database_query(database, GUANYINMA_QUERY_CANGJIE,
                                    invalid_utf8, sizeof(invalid_utf8), &result),
           GUANYINMA_INVALID_UTF8);
    REQUIRE(result == NULL);
    check_error_copy();
    STATUS(guanyinma_database_query(database, GUANYINMA_QUERY_CANGJIE,
                                    embedded_nul, sizeof(embedded_nul), &result),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    STATUS(guanyinma_database_query(database, UINT32_MAX,
                                    (const uint8_t *)"a", 1, &result),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    STATUS(guanyinma_database_query(NULL, GUANYINMA_QUERY_CANGJIE,
                                    (const uint8_t *)"a", 1, &result),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    STATUS(guanyinma_database_query(database, GUANYINMA_QUERY_CANGJIE,
                                    NULL, 1, &result),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    STATUS(guanyinma_database_query(database, GUANYINMA_QUERY_CANGJIE,
                                    (const uint8_t *)"a", 1, NULL),
           GUANYINMA_INVALID_ARGUMENT);

    size_t count = SIZE_MAX;
    STATUS(guanyinma_result_row_count(NULL, &count),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(count == 0);
    size_t required = SIZE_MAX;
    STATUS(guanyinma_result_json(NULL, NULL, 0, &required),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(required == 0);
    STATUS(guanyinma_result_close(NULL), GUANYINMA_INVALID_ARGUMENT);
    STATUS(guanyinma_database_close(NULL), GUANYINMA_INVALID_ARGUMENT);

    GuanyinmaDatabase *other = NULL;
    STATUS(guanyinma_database_open(NULL, 0, &other),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(other == NULL);
    STATUS(guanyinma_database_open(invalid_utf8, sizeof(invalid_utf8), &other),
           GUANYINMA_INVALID_UTF8);
    REQUIRE(other == NULL);
    STATUS(guanyinma_database_open(embedded_nul, sizeof(embedded_nul), &other),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(other == NULL);
    STATUS(guanyinma_database_open((const uint8_t *)path, strlen(path), NULL),
           GUANYINMA_INVALID_ARGUMENT);
}


static GuanyinmaResult *session_apply(GuanyinmaSession *session,
                                      const char *operation) {
    GuanyinmaResult *result = NULL;
    STATUS(guanyinma_session_apply(session, (const uint8_t *)operation,
                                   strlen(operation), &result),
           GUANYINMA_OK);
    REQUIRE(result != NULL);
    return result;
}

static GuanyinmaResult *session_state(GuanyinmaSession *session) {
    GuanyinmaResult *result = NULL;
    STATUS(guanyinma_session_snapshot(session, &result), GUANYINMA_OK);
    REQUIRE(result != NULL);
    return result;
}

/* Only the fixed printable ASCII keys below are interpolated into JSON. */
static void session_type(GuanyinmaSession *session, const char *keys) {
    for (const char *key = keys; *key != '\0'; ++key) {
        REQUIRE(*key >= ' ' && *key < 127 && *key != '"' && *key != '\\');
        char operation[64];
        const int count = snprintf(operation, sizeof(operation),
            "{\"type\":\"character\",\"text\":\"%c\"}", *key);
        REQUIRE(count > 0 && (size_t)count < sizeof(operation));
        GuanyinmaResult *result = session_apply(session, operation);
        close_result(&result);
    }
}

static void check_sessions(const char *path) {
    GuanyinmaSession *session = NULL;
    GuanyinmaResult *result = NULL;
    const char *bad_config = "{\"profile\":\"unknown_profile\"}";
    STATUS(guanyinma_session_open((const uint8_t *)path, strlen(path),
                                   (const uint8_t *)bad_config,
                                   strlen(bad_config), &session),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(session == NULL);
    bad_config = "{\"unexpected\":true}";
    STATUS(guanyinma_session_open((const uint8_t *)path, strlen(path),
                                   (const uint8_t *)bad_config,
                                   strlen(bad_config), &session),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(session == NULL);
    STATUS(guanyinma_session_open((const uint8_t *)path, strlen(path),
                                   NULL, 1, &session),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(session == NULL);

    /* A NULL/empty configuration selects the documented defaults. */
    STATUS(guanyinma_session_open((const uint8_t *)path, strlen(path),
                                   NULL, 0, &session),
           GUANYINMA_OK);
    REQUIRE(session != NULL);
    session_type(session, "su3");
    result = session_state(session);
    REQUIRE(row_count(result) > 3);
    char *json = result_json(result);
    REQUIRE(strstr(json, "\"kind\":\"session\"") != NULL);
    REQUIRE(strstr(json, "\"method\":\"traditional\"") != NULL);
    REQUIRE(strstr(json, "\"candidates\":[\"你\",\"妳\",\"擬\",") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    char *before = json;
    close_result(&result);

    const char *invalid_operations[] = {
        "{invalid",
        "{\"type\":\"not_an_operation\"}",
        "{\"type\":\"key\",\"key\":\"space\",\"unexpected\":true}",
        "{\"type\":\"character\",\"text\":\"\\u0000\"}"
    };
    for (size_t index = 0;
         index < sizeof(invalid_operations) / sizeof(invalid_operations[0]);
         ++index) {
        result = (GuanyinmaResult *)(uintptr_t)1;
        STATUS(guanyinma_session_apply(session,
                                        (const uint8_t *)invalid_operations[index],
                                        strlen(invalid_operations[index]), &result),
               GUANYINMA_INVALID_ARGUMENT);
        REQUIRE(result == NULL);
    }
    const uint8_t invalid_utf8[] = {0xff};
    STATUS(guanyinma_session_apply(session, invalid_utf8,
                                    sizeof(invalid_utf8), &result),
           GUANYINMA_INVALID_UTF8);
    REQUIRE(result == NULL);
    STATUS(guanyinma_session_apply(session, NULL, 0, &result),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    result = session_state(session);
    json = result_json(result);
    REQUIRE(strcmp(json, before) == 0);
    free(before);
    free(json);
    close_result(&result);

    result = session_apply(session, "{\"type\":\"select\",\"index\":1}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"commit\":\"妳\"") != NULL);
    free(json);
    close_result(&result);
    result = session_state(session);
    REQUIRE(row_count(result) == 0);
    json = result_json(result);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);

    result = session_apply(session,
        "{\"type\":\"set_method\",\"method\":\"cangjie\"}");
    close_result(&result);
    session_type(session, "a");
    result = session_apply(session, "{\"type\":\"key\",\"key\":\"space\"}");
    REQUIRE(row_count(result) == 2);
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"日\",\"曰\"]") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"select\",\"index\":1}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"commit\":\"曰\"") != NULL);
    free(json);
    close_result(&result);

    result = session_apply(session,
        "{\"type\":\"set_method\",\"method\":\"simplex\"}");
    close_result(&result);
    session_type(session, "ab");
    result = session_state(session);
    REQUIRE(row_count(result) > 8);
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"明\",\"晞\",\"晴\",\"閒\",") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"key\",\"key\":\"page_down\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"page\":1") != NULL);
    free(json);
    close_result(&result);

    /* Results are independent, including after a stateful session is closed. */
    result = session_state(session);
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);
    REQUIRE(session == NULL);
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);
    REQUIRE(row_count(result) > 8);
    json = result_json(result);
    REQUIRE(strstr(json, "\"method\":\"simplex\"") != NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(NULL), GUANYINMA_INVALID_ARGUMENT);
    STATUS(guanyinma_session_snapshot(NULL, &result), GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
}


static GuanyinmaSession *open_session(const char *path, const char *config) {
    GuanyinmaSession *session = NULL;
    STATUS(guanyinma_session_open((const uint8_t *)path, strlen(path),
                                   (const uint8_t *)config, strlen(config),
                                   &session),
           GUANYINMA_OK);
    REQUIRE(session != NULL);
    return session;
}

static void expect_commit_and_close(GuanyinmaResult **result,
                                    const char *expected_fragment) {
    char *json = result_json(*result);
    REQUIRE(strstr(json, expected_fragment) != NULL);
    free(json);
    close_result(result);
}

typedef struct {
    const char *const *rejected;
    size_t rejected_count;
    size_t calls;
} CandidateFilterContext;

static int32_t GUANYINMA_CALL candidate_filter(
    void *opaque, const uint8_t *text, size_t text_length) {
    CandidateFilterContext *context = (CandidateFilterContext *)opaque;
    REQUIRE(context != NULL);
    REQUIRE(text != NULL);
    REQUIRE(text_length > 0);
    REQUIRE(memchr(text, 0, text_length) == NULL);
    ++context->calls;
    for (size_t i = 0; i < context->rejected_count; ++i) {
        const char *rejected = context->rejected[i];
        if (strlen(rejected) == text_length &&
            memcmp(rejected, text, text_length) == 0) {
            return 0;
        }
    }
    /* Verify that acceptance means nonzero, rather than exactly one. */
    return -7;
}

static GuanyinmaSession *open_filtered_session(
    const char *path, const char *config, CandidateFilterContext *context) {
    GuanyinmaSession *session = NULL;
    STATUS(guanyinma_session_open_with_candidate_filter(
        (const uint8_t *)path, strlen(path),
        (const uint8_t *)config, strlen(config),
        candidate_filter, context, &session), GUANYINMA_OK);
    REQUIRE(session != NULL);
    return session;
}

static void check_candidate_filters(const char *path) {
    const char *config =
        "{\"method\":\"cangjie\",\"cangjie\":{\"realtime\":true,\"prefix\":true}}";
    const char *const unsupported[] = {"𥫜", "\U000fd952", "𠆥"};
    CandidateFilterContext first = {unsupported, 3, 0};
    CandidateFilterContext all = {NULL, 0, 0};
    GuanyinmaSession *filtered = open_filtered_session(path, config, &first);
    GuanyinmaSession *unfiltered = open_filtered_session(path, config, &all);

    session_type(filtered, "hk");
    const size_t first_calls = first.calls;
    REQUIRE(first_calls > 0);
    session_type(unfiltered, "hk");
    REQUIRE(all.calls > 0);
    REQUIRE(first.calls == first_calls);
    GuanyinmaResult *result = session_state(filtered);
    REQUIRE(row_count(result) == 37); /* one exact plus 36 filtered extras */
    char *json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"夭\",\"喬\",") != NULL);
    REQUIRE(strstr(json, "\"displayed_candidates\":[\"夭\",\"喬\",") != NULL);
    REQUIRE(strstr(json, "𥫜") == NULL);
    REQUIRE(strstr(json, "\U000fd952") == NULL);
    REQUIRE(strstr(json, "𠆥") == NULL);
    free(json);
    close_result(&result);
    /* A physical number selects the same visible second candidate. */
    result = session_apply(filtered, "{\"type\":\"character\",\"text\":\"2\"}");
    expect_commit_and_close(&result, "\"commit\":\"喬\"");
    REQUIRE(all.calls > 0);
    result = session_state(unfiltered);
    REQUIRE(row_count(result) == 40);
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"夭\",\"𥫜\",\"\U000fd952\",\"𠆥\",\"喬\",") != NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&filtered), GUANYINMA_OK);
    STATUS(guanyinma_session_close(&unfiltered), GUANYINMA_OK);

    /* Filter before the bounded prefix choice, so lower-ranked extras refill. */
    const char *const refill_rejected[] = {
        "𥫜", "\U000fd952", "𠆥", "喬", "昋"
    };
    CandidateFilterContext refill = {refill_rejected, 5, 0};
    filtered = open_filtered_session(path, config, &refill);
    session_type(filtered, "hk");
    result = session_state(filtered);
    REQUIRE(row_count(result) == 37);
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"夭\",") != NULL);
    REQUIRE(strstr(json, "\"喬\"") == NULL);
    REQUIRE(strstr(json, "\"昋\"") == NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&filtered), GUANYINMA_OK);

    /* The additive entry point preserves every old-open default with NULL. */
    filtered = open_session(path, config);
    STATUS(guanyinma_session_open_with_candidate_filter(
        (const uint8_t *)path, strlen(path),
        (const uint8_t *)config, strlen(config),
        NULL, (void *)(uintptr_t)1, &unfiltered), GUANYINMA_OK);
    session_type(filtered, "hk");
    session_type(unfiltered, "hk");
    result = session_state(filtered);
    char *before = result_json(result);
    close_result(&result);
    result = session_state(unfiltered);
    json = result_json(result);
    REQUIRE(strcmp(before, json) == 0);
    free(before);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&filtered), GUANYINMA_OK);
    STATUS(guanyinma_session_close(&unfiltered), GUANYINMA_OK);

    /* Filtering also changes the single-candidate decision before auto-commit. */
    const char *const single_rejected[] = {"日"};
    CandidateFilterContext single = {single_rejected, 1, 0};
    filtered = open_filtered_session(path, "{\"method\":\"cangjie\"}", &single);
    session_type(filtered, "a");
    result = session_apply(filtered, "{\"type\":\"key\",\"key\":\"space\"}");
    expect_commit_and_close(&result, "\"commit\":\"曰\"");
    STATUS(guanyinma_session_close(&filtered), GUANYINMA_OK);

    /* The same callback ABI is honored by Traditional, Simplex and Smart. */
    const char *const other_rejected[] = {"你", "明", "是"};
    CandidateFilterContext other = {other_rejected, 3, 0};
    filtered = open_filtered_session(path, "{}", &other);
    session_type(filtered, "su3");
    result = session_state(filtered);
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"妳\",\"擬\",") != NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&filtered), GUANYINMA_OK);

    filtered = open_filtered_session(path, "{\"method\":\"simplex\"}", &other);
    session_type(filtered, "ab");
    result = session_state(filtered);
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"晞\",\"晴\",\"閒\",") != NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&filtered), GUANYINMA_OK);

    filtered = open_filtered_session(path, "{\"method\":\"smart\"}", &other);
    session_type(filtered, "g4");
    result = session_state(filtered);
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"事\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(filtered,
        "{\"type\":\"open_candidates\",\"index\":0}");
    REQUIRE(row_count(result) == 367);
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"事\",\"市\",\"式\",") != NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&filtered), GUANYINMA_OK);

    /* Validation fails before retaining or invoking a callback. */
    CandidateFilterContext unused = {NULL, 0, 0};
    filtered = (GuanyinmaSession *)(uintptr_t)1;
    STATUS(guanyinma_session_open_with_candidate_filter(
        NULL, 0, NULL, 0, candidate_filter, &unused, &filtered),
        GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(filtered == NULL && unused.calls == 0);
    const char *bad_config = "{\"candidate_filter\":true}";
    STATUS(guanyinma_session_open_with_candidate_filter(
        (const uint8_t *)path, strlen(path),
        (const uint8_t *)bad_config, strlen(bad_config),
        candidate_filter, &unused, &filtered), GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(filtered == NULL && unused.calls == 0);
    STATUS(guanyinma_session_open_with_candidate_filter(
        (const uint8_t *)path, strlen(path), NULL, 0,
        candidate_filter, &unused, NULL), GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(unused.calls == 0);
}

static void check_keyboard_contracts(const char *path) {
    GuanyinmaSession *session = NULL;
    const char *bad_config = "{\"behaviors\":{\"ignore_caps_lock_in_chinese\":\"true\"}}";
    STATUS(guanyinma_session_open((const uint8_t *)path, strlen(path),
                                   (const uint8_t *)bad_config,
                                   strlen(bad_config), &session),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(session == NULL);
    bad_config = "{\"ignore_caps_lock_in_chinese\":true}";
    STATUS(guanyinma_session_open((const uint8_t *)path, strlen(path),
                                   (const uint8_t *)bad_config,
                                   strlen(bad_config), &session),
           GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(session == NULL);

    /* The default preserves actual Caps Lock text instead of guessing case. */
    session = open_session(path, "{}");
    GuanyinmaResult *result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"S\",\"modifiers\":{\"caps_lock\":true}}");
    expect_commit_and_close(&result, "\"commit\":\"S\"");
    result = session_state(session);
    REQUIRE(row_count(result) == 0);
    char *json = result_json(result);
    REQUIRE(strstr(json, "\"phonetic\":\"\"") != NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);

    session = open_session(path, "{\"behaviors\":{\"ignore_caps_lock_in_chinese\":true}}");
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"S\",\"modifiers\":{\"caps_lock\":true}}");
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"U\",\"modifiers\":{\"caps_lock\":true}}");
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"3\",\"modifiers\":{\"caps_lock\":true}}");
    REQUIRE(row_count(result) > 3);
    json = result_json(result);
    REQUIRE(strstr(json, "\"phonetic\":\"ㄋㄧˇ\"") != NULL);
    REQUIRE(strstr(json, "\"candidates\":[\"你\",\"妳\",\"擬\",") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);

    /* One native gesture produces one toggle, preserving the current text. */
    result = session_apply(session, "{\"type\":\"toggle_english\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"english\":true") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"你\"") != NULL);
    REQUIRE(strstr(json, "\"phonetic\":\"\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"A\",\"modifiers\":{\"caps_lock\":true}}");
    expect_commit_and_close(&result, "\"commit\":\"A\"");
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"a\",\"modifiers\":{\"caps_lock\":true}}");
    expect_commit_and_close(&result, "\"commit\":\"a\"");
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"B\",\"modifiers\":{\"caps_lock\":true,\"shift\":true}}");
    expect_commit_and_close(&result, "\"commit\":\"B\"");
    result = session_apply(session, "{\"type\":\"toggle_english\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"english\":false") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"S\",\"modifiers\":{\"caps_lock\":true,\"shift\":true}}");
    expect_commit_and_close(&result, "\"commit\":\"S\"");
    result = session_state(session);
    REQUIRE(row_count(result) == 0);
    json = result_json(result);
    REQUIRE(strstr(json, "\"phonetic\":\"\"") != NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);

    session = open_session(path, "{}");
    /* Actual keypad shortcuts/releases must not enter the IME Ctrl map. */
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"1\",\"modifiers\":{\"keypad\":true,\"control\":true,\"num_lock\":true}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"handled\":false") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    REQUIRE(row_count(result) == 0);
    free(json);
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"1\",\"modifiers\":{\"keypad\":true,\"release\":true,\"num_lock\":true}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"handled\":false") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);

    /* Num Lock is global state, not proof that these are keypad keys. */
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"s\",\"modifiers\":{\"num_lock\":true}}");
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"u\",\"modifiers\":{\"num_lock\":true}}");
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"3\",\"modifiers\":{\"num_lock\":true}}");
    REQUIRE(row_count(result) > 3);
    json = result_json(result);
    REQUIRE(strstr(json, "\"phonetic\":\"ㄋㄧˇ\"") != NULL);
    REQUIRE(strstr(json, "\"composition\":\"你\"") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);

    /* The keypad digit is literal, retaining the visible candidate preview. */
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"1\",\"modifiers\":{\"keypad\":true,\"num_lock\":true}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"commit\":\"你1\"") != NULL);
    REQUIRE(strstr(json, "\"composition\":\"\"") != NULL);
    REQUIRE(strstr(json, "\"phonetic\":\"\"") != NULL);
    REQUIRE(row_count(result) == 0);
    free(json);
    close_result(&result);

    /* Keypad operators also remain literal while Num Lock is off. */
    session_type(session, "su3");
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"+\",\"modifiers\":{\"keypad\":true,\"num_lock\":false}}");
    expect_commit_and_close(&result, "\"commit\":\"你+\"");

    /* Behavior replacement keeps this composition and affects only new keys. */
    session_type(session, "su3");
    result = session_apply(session,
        "{\"type\":\"set_behaviors\",\"behaviors\":{\"literal_keypad\":false}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"你\"") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    REQUIRE(row_count(result) > 3);
    free(json);
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"1\",\"modifiers\":{\"keypad\":true,\"num_lock\":true}}");
    expect_commit_and_close(&result, "\"commit\":\"你\"");
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"1\",\"modifiers\":{\"keypad\":true,\"control\":true,\"num_lock\":true}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"handled\":false") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    REQUIRE(row_count(result) == 0);
    free(json);
    close_result(&result);

    session_type(session, "s");
    result = session_apply(session,
        "{\"type\":\"set_behaviors\",\"behaviors\":{\"ignore_caps_lock_in_chinese\":true}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"phonetic\":\"ㄋ\"") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"U\",\"modifiers\":{\"caps_lock\":true}}");
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"3\",\"modifiers\":{\"caps_lock\":true}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"你\"") != NULL);
    REQUIRE(strstr(json, "\"phonetic\":\"ㄋㄧˇ\"") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);
}


static void check_smart_sessions(const char *path) {
    GuanyinmaSession *session = open_session(path, "{\"method\":\"smart\"}");
    session_type(session, "g4");
    GuanyinmaResult *result = session_state(session);
    char *json = result_json(result);
    REQUIRE(row_count(result) == 0);
    REQUIRE(strstr(json, "\"composition\":\"是\"") != NULL);
    REQUIRE(strstr(json, "\"reading\":\"\"") != NULL);
    REQUIRE(strstr(json, "\"reading_cursor\":1") != NULL);
    free(json);
    close_result(&result);

    result = session_apply(session, "{\"type\":\"open_candidates\",\"index\":0}");
    REQUIRE(row_count(result) == 368);
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"是\",\"事\",\"市\",\"式\",\"視\",\"世\",\"示\",\"士\",") != NULL);
    REQUIRE(strstr(json, "\"candidate_spans\":[{\"start\":0,\"span\":1,\"text\":\"是\",") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"key\",\"key\":\"page_down\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"page\":1") != NULL);
    REQUIRE(strstr(json, "\"displayed_candidates\":[\"試\",\"識\",\"勢\",\"適\",\"室\",\"釋\",\"使\",\"飾\"]") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"select\",\"index\":0}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"試\"") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    REQUIRE(row_count(result) == 0);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"key\",\"key\":\"return\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"commit\":\"試\"") != NULL);
    free(json);
    close_result(&result);

    session_type(session, "su3cl3");
    result = session_apply(session, "{\"type\":\"open_candidates\",\"index\":0}");
    REQUIRE(row_count(result) == 87);
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"你好\",\"妳好\",\"你\",\"妳\",") != NULL);
    REQUIRE(strstr(json, "\"candidate_spans\":[{\"start\":0,\"span\":2,\"text\":\"你好\",") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"select\",\"index\":3}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"妳好\"") != NULL);
    REQUIRE(strstr(json, "\"reading_cursor\":1") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);

    result = session_state(session);
    char *before = result_json(result);
    close_result(&result);
    const char *invalid[] = {
        "{\"type\":\"set_cursor\",\"index\":3}",
        "{\"type\":\"open_candidates\",\"index\":2}",
        "{\"type\":\"select\",\"index\":0}",
        "{\"type\":\"set_smart_options\",\"options\":{\"max_completed_syllables\":0}}",
        "{\"type\":\"set_smart_options\",\"options\":{\"max_completed_syllables\":9}}",
        "{\"type\":\"set_smart_options\",\"options\":{\"max_completed_syllables\":21}}",
        "{\"type\":\"set_smart_options\",\"options\":{\"use_bigrams\":\"false\"}}",
        "{\"type\":\"set_smart_options\",\"options\":{\"candidate_selection_keys\":\"11\"}}",
        "{\"type\":\"set_table_options\",\"method\":\"smart\",\"options\":{}}"
    };
    for (size_t index = 0; index < sizeof(invalid) / sizeof(invalid[0]); ++index) {
        STATUS(guanyinma_session_apply(session, (const uint8_t *)invalid[index],
                                       strlen(invalid[index]), &result),
               GUANYINMA_INVALID_ARGUMENT);
        REQUIRE(result == NULL);
        result = session_state(session);
        json = result_json(result);
        REQUIRE(strcmp(json, before) == 0);
        free(json);
        close_result(&result);
    }
    free(before);

    result = session_apply(session, "{\"type\":\"set_smart_options\",\"options\":{\"space_opens_candidates\":false,\"max_completed_syllables\":20,\"selection_returns_to_end\":true}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"妳好\"") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    REQUIRE(strstr(json, "\"max_completed_syllables\":20") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"set_cursor\",\"index\":2}");
    close_result(&result);
    session_type(session, "s");
    result = session_apply(session, "{\"type\":\"set_method\",\"method\":\"traditional\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"commit\":\"妳好ㄋ\"") != NULL);
    REQUIRE(strstr(json, "\"composition\":\"\"") != NULL);
    free(json);
    close_result(&result);

    result = session_apply(session, "{\"type\":\"set_smart_options\",\"options\":{\"use_bigrams\":false}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"use_bigrams\":false") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"set_method\",\"method\":\"smart\"}");
    close_result(&result);
    session_type(session, "fu/3ru84ul4fm4s83");
    result = session_state(session);
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"請假要去那\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"set_smart_options\",\"options\":{\"use_bigrams\":true}}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"請假要去哪\"") != NULL);
    REQUIRE(strstr(json, "\"reading_cursor\":5") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"reset\"}");
    close_result(&result);
    /* An independently owned result keeps the Smart metadata after close. */
    result = session_apply(session, "{\"type\":\"set_method\",\"method\":\"smart\"}");
    close_result(&result);
    session_type(session, "su3cl3");
    result = session_apply(session, "{\"type\":\"open_candidates\",\"index\":0}");
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);
    REQUIRE(row_count(result) == 87);
    json = result_json(result);
    REQUIRE(strstr(json, "\"span\":2,\"text\":\"你好\"") != NULL);
    free(json);
    close_result(&result);
}

static GuanyinmaResult *user_data(GuanyinmaSession *session) {
    GuanyinmaResult *result = NULL;
    STATUS(guanyinma_session_user_data(session, &result), GUANYINMA_OK);
    REQUIRE(result != NULL);
    return result;
}

/* JSON-quote a UTF-8 path without changing its native separators or text. */
static char *json_path(const char *path) {
    const size_t length = strlen(path);
    REQUIRE(length <= (SIZE_MAX - 3) / 6);
    char *quoted = (char *)malloc(length * 6 + 3);
    REQUIRE(quoted != NULL);
    char *out = quoted;
    *out++ = '"';
    static const char hex[] = "0123456789abcdef";
    for (const unsigned char *in = (const unsigned char *)path; *in; ++in) {
        if (*in == '"' || *in == '\\') {
            *out++ = '\\';
            *out++ = (char)*in;
        } else if (*in < 0x20) {
            *out++ = '\\'; *out++ = 'u'; *out++ = '0'; *out++ = '0';
            *out++ = hex[*in >> 4]; *out++ = hex[*in & 0xf];
        } else {
            *out++ = (char)*in;
        }
    }
    *out++ = '"';
    *out = 0;
    return quoted;
}

static void check_learning_sessions(const char *model, const char *user_path) {
    /* The driver supplies a fresh Unicode path inside its disposable directory. */
    char *quoted_path = json_path(user_path);
    const size_t capacity = strlen(quoted_path) + 256;
    char *config = (char *)malloc(capacity);
    REQUIRE(config != NULL);
    const int count = snprintf(config, capacity,
        "{\"method\":\"smart\",\"user_database\":%s,"
        "\"learning\":{\"candidate_overrides\":true,\"bigrams\":true,\"table_learning\":true}}",
        quoted_path);
    free(quoted_path);
    REQUIRE(count > 0 && (size_t)count < capacity);
    GuanyinmaSession *session = open_session(model, config);
    session_type(session, "g4");
    GuanyinmaResult *result = session_apply(session, "{\"type\":\"open_candidates\",\"index\":0}");
    close_result(&result);
    result = session_apply(session, "{\"type\":\"select\",\"index\":1}");
    close_result(&result);
    result = user_data(session);
    char *json = result_json(result);
    REQUIRE(strstr(json, "\"kind\":\"user_data\"") != NULL);
    REQUIRE(strstr(json, "\"overrides\":[{\"qstring\":\"0_\",\"current\":\"事\"}]") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"save_learning\"}");
    close_result(&result);
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);

    session = open_session(model, config);
    session_type(session, "g4");
    result = session_apply(session, "{\"type\":\"open_candidates\",\"index\":0}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"事\"") != NULL);
    REQUIRE(strstr(json, "\"candidates\":[\"事\",\"是\",") != NULL);
    free(json);
    close_result(&result);
    /* Choosing the CURRENT first item removes the cached preference. */
    result = session_apply(session, "{\"type\":\"select\",\"index\":0}");
    close_result(&result);
    result = user_data(session);
    json = result_json(result);
    REQUIRE(strstr(json, "\"overrides\":[]") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"reset\"}");
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"add_user_phrase\",\"qstring\":\"0_0_\",\"text\":\"士事\"}");
    close_result(&result);
    result = session_apply(session, "{\"type\":\"reset_learning\"}");
    close_result(&result);
    result = user_data(session);
    REQUIRE(row_count(result) == 1);
    json = result_json(result);
    REQUIRE(strstr(json, "\"current\":\"士事\"") != NULL);
    REQUIRE(strstr(json, "\"overrides\":[]") != NULL);
    REQUIRE(strstr(json, "\"bigrams\":[]") != NULL);
    free(json);
    close_result(&result);
    session_type(session, "g4g4");
    result = session_state(session);
    json = result_json(result);
    REQUIRE(strstr(json, "\"composition\":\"士事\"") != NULL);
    free(json);
    close_result(&result);

    result = session_apply(session, "{\"type\":\"set_method\",\"method\":\"cangjie\"}");
    close_result(&result);
    session_type(session, "a");
    result = session_apply(session, "{\"type\":\"key\",\"key\":\"space\"}");
    close_result(&result);
    result = session_apply(session, "{\"type\":\"select\",\"index\":1}");
    close_result(&result);
    session_type(session, "a");
    result = session_apply(session, "{\"type\":\"key\",\"key\":\"space\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"candidates\":[\"曰\",\"日\"]") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"reset_method_learning\",\"method\":\"smart\"}");
    close_result(&result);
    result = user_data(session);
    json = result_json(result);
    REQUIRE(strstr(json, "\"method\":\"cangjie\",\"code\":\"a\",\"current\":\"曰\",\"count\":1") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"reset_learning\"}");
    close_result(&result);
    result = user_data(session);
    REQUIRE(row_count(result) == 1);
    json = result_json(result);
    REQUIRE(strstr(json, "\"table\":[]") != NULL);
    free(json);
    /* This data result remains valid after its session closes. */
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);
    REQUIRE(row_count(result) == 1);
    close_result(&result);
    STATUS(guanyinma_session_user_data(NULL, &result), GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    free(config);
}


/* Public, platform-neutral controls used by the macOS frontend. These are
 * ordinary ABI contracts; no migration trace or real frontend profile is read. */
static void check_native_behavior_controls(const char *path) {
    GuanyinmaSession *session = open_session(path,
        "{\"method\":\"cangjie\",\"cangjie\":{\"maximum_radical_length\":1,"
        "\"query_at_maximum\":true,\"wildcards\":{\"one\":null,\"many\":null}}}");
    session_type(session, "a");
    GuanyinmaResult *result = session_state(session);
    REQUIRE(row_count(result) == 2);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"select\",\"index\":1}");
    expect_commit_and_close(&result, "\"commit\":\"曰\"");
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);

    session = open_session(path, "{\"method\":\"traditional\"}");
    session_type(session, "5j/");
    result = session_apply(session,
        "{\"type\":\"key\",\"key\":\"space\",\"modifiers\":{\"shift\":true}}");
    char *json = result_json(result);
    REQUIRE(row_count(result) > 1);
    REQUIRE(strstr(json, "\"full_width\":false") != NULL);
    REQUIRE(strstr(json, "\"candidates\":[\"中\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"toggle_full_width\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"full_width\":true") != NULL);
    REQUIRE(strstr(json, "\"candidates\":[\"中\"") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"set_full_width\",\"enabled\":true}");
    expect_commit_and_close(&result, "\"full_width\":true");
    result = session_apply(session, "{\"type\":\"set_full_width\",\"enabled\":false}");
    expect_commit_and_close(&result, "\"full_width\":false");
    result = session_apply(session, "{\"type\":\"reset\"}");
    close_result(&result);
    session_type(session, "s");
    result = session_apply(session, "{\"type\":\"direct_text\",\"text\":\"好\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"commit\":\"好\"") != NULL);
    REQUIRE(strstr(json, "\"reading\":\"\"") != NULL);
    free(json);
    close_result(&result);
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);

    session = open_session(path, "{\"method\":\"smart\",\"smart\":{\"shift_always_uppercase\":true}}");
    result = session_apply(session,
        "{\"type\":\"character\",\"text\":\"a\",\"modifiers\":{\"shift\":true}}");
    expect_commit_and_close(&result, "\"commit\":\"A\"");
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);
}

static void check_mark_and_explicit_input_modes(const char *path) {
    GuanyinmaSession *session = open_session(path, "{\"method\":\"smart\"}");
    session_type(session, "su3cl3");
    GuanyinmaResult *result = session_apply(session,
        "{\"type\":\"key\",\"key\":\"left\",\"modifiers\":{\"shift\":true}}");
    close_result(&result);
    result = session_apply(session,
        "{\"type\":\"key\",\"key\":\"left\",\"modifiers\":{\"shift\":true}}");
    char *json = result_json(result);
    REQUIRE(strstr(json, "\"marked_phrase\":{") != NULL);
    REQUIRE(strstr(json, "\"text\":\"你好\"") != NULL);
    REQUIRE(strstr(json, "\"text_length\":2") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"key\",\"key\":\"return\"}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"phrase_feedback\":{\"text\":\"你好\",\"added\":false}") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    REQUIRE(strstr(json, "\"composition\":\"你好\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"set_english\",\"enabled\":true}");
    json = result_json(result);
    REQUIRE(strstr(json, "\"english\":true") != NULL);
    REQUIRE(strstr(json, "\"commit\":\"你好\"") != NULL);
    free(json);
    close_result(&result);
    result = session_apply(session, "{\"type\":\"set_english\",\"enabled\":true}");
    expect_commit_and_close(&result, "\"commit\":\"\"");
    result = session_apply(session, "{\"type\":\"set_english\",\"enabled\":false}");
    expect_commit_and_close(&result, "\"english\":false");
    result = session_apply(session, "{\"type\":\"toggle_english\"}");
    expect_commit_and_close(&result, "\"english\":true");
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);
}

static void check_user_archives(const char *path) {
    const char *minimal =
        "{\"format\":\"guanyinma_user_data\",\"schema_version\":1,\"phrases\":[]}";
    STATUS(guanyinma_user_archive_validate((const uint8_t *)minimal, strlen(minimal)),
           GUANYINMA_OK);
    STATUS(guanyinma_user_archive_validate(NULL, 1), GUANYINMA_INVALID_ARGUMENT);
    STATUS(guanyinma_user_archive_validate(NULL, 0), GUANYINMA_INVALID_ARGUMENT);
    const uint8_t invalid_utf8[] = {0xff};
    STATUS(guanyinma_user_archive_validate(invalid_utf8, sizeof(invalid_utf8)),
           GUANYINMA_INVALID_UTF8);
    const uint8_t embedded_nul[] = {'{', 0, '}'};
    STATUS(guanyinma_user_archive_validate(embedded_nul, sizeof(embedded_nul)),
           GUANYINMA_INVALID_ARGUMENT);
    const char *invalid[] = {
        "{\"format\":\"guanyinma_user_data\",\"schema_version\":2,\"phrases\":[]}",
        "{\"format\":\"guanyinma_user_data\",\"schema_version\":1,\"phrases\":[],\"generation\":5}",
        "{\"format\":\"guanyinma_user_data\",\"schema_version\":1,\"phrases\":[],\"smart\":{\"overrides\":[]}}",
        "{\"format\":\"guanyinma_user_data\",\"schema_version\":1,\"phrases\":[],\"table\":[{\"method\":\"cangjie\",\"code\":\"a\",\"current\":\"曰\",\"count\":true}]}",
        "{\"format\":\"guanyinma_user_data\",\"schema_version\":1,\"phrases\":[],\"phrases\":[]}"
    };
    for (size_t index = 0; index < sizeof(invalid) / sizeof(invalid[0]); ++index)
        REQUIRE(guanyinma_user_archive_validate((const uint8_t *)invalid[index],
                                                strlen(invalid[index])) != GUANYINMA_OK);

    const char *archive =
        "{\"format\":\"guanyinma_user_data\",\"schema_version\":1,"
        "\"phrases\":[{\"qstring\":\"0_0_\",\"current\":\"士事\",\"probability\":-0.25,\"backoff\":-0.1}],"
        "\"smart\":{\"overrides\":[{\"qstring\":\"0_\",\"current\":\"事\"}],"
        "\"bigrams\":[{\"qstring\":\"! 0_\",\"previous\":\"\",\"current\":\"事\",\"probability\":-0.5}]},"
        "\"table\":[{\"method\":\"cangjie\",\"code\":\"a\",\"current\":\"曰\",\"count\":9}]}";
    STATUS(guanyinma_user_archive_validate((const uint8_t *)archive, strlen(archive)),
           GUANYINMA_OK);
    GuanyinmaSession *session = open_session(path, "{\"method\":\"smart\"}");
    size_t capacity = strlen(archive) + 64;
    char *operation = (char *)malloc(capacity);
    REQUIRE(operation != NULL);
    int written = snprintf(operation, capacity,
                           "{\"type\":\"import_user_data\",\"archive\":%s}", archive);
    REQUIRE(written > 0 && (size_t)written < capacity);
    GuanyinmaResult *result = session_apply(session, operation);
    char *json = result_json(result);
    REQUIRE(strstr(json, "\"commit\":\"\"") != NULL);
    free(json);
    close_result(&result);
    result = user_data(session);
    REQUIRE(row_count(result) == 1);
    char *before = result_json(result);
    REQUIRE(strstr(before, "\"current\":\"士事\"") != NULL);
    REQUIRE(strstr(before, "\"count\":9") != NULL);
    REQUIRE(strstr(before, "\"generation\":1") != NULL);
    close_result(&result);

    written = snprintf(operation, capacity,
                       "{\"type\":\"import_user_data\",\"archive\":%s}", invalid[0]);
    REQUIRE(written > 0 && (size_t)written < capacity);
    REQUIRE(guanyinma_session_apply(session, (const uint8_t *)operation,
                                     strlen(operation), &result) != GUANYINMA_OK);
    REQUIRE(result == NULL);
    result = user_data(session);
    json = result_json(result);
    REQUIRE(strcmp(before, json) == 0);
    free(json);
    free(before);
    free(operation);
    close_result(&result);
    STATUS(guanyinma_session_close(&session), GUANYINMA_OK);
}

/* No model/session handle is involved in the portable codec contract. */
static void check_reading_codec(void) {
    const char *encode = "{\"operation\":\"encode\",\"reading\":\"ㄋㄧˇ,ㄏㄠˇ\"}";
    GuanyinmaResult *result = NULL;
    STATUS(guanyinma_reading_codec((const uint8_t *)encode, strlen(encode), &result), GUANYINMA_OK);
    REQUIRE(result != NULL);
    REQUIRE(row_count(result) == 2);
    char *json = result_json(result);
    REQUIRE(strstr(json, "\"kind\":\"reading_codec\"") != NULL);
    REQUIRE(strstr(json, "\"reading\":\"ㄋㄧˇ,ㄏㄠˇ\"") != NULL);
    REQUIRE(strstr(json, "\"syllable_count\":2") != NULL);
    free(json);
    check_complete_json_copy(result);
    close_result(&result);

    const char *decode = "{\"operation\":\"decode\",\"qstring\":\"\\\\O:W\","
        "\"options\":{\"separator\":\"space\",\"query\":\"canonical\"}}";
    STATUS(guanyinma_reading_codec((const uint8_t *)decode, strlen(decode), &result), GUANYINMA_OK);
    json = result_json(result);
    REQUIRE(strstr(json, "\"reading\":\"ㄋㄧˇ ㄏㄠˇ\"") != NULL);
    free(json);
    close_result(&result);

    const char *bad[] = {
        "{\"operation\":\"encode\",\"reading\":\"ㄅㄆ\",\"options\":{\"components\":\"unique_known\"}}",
        "{\"operation\":\"decode\",\"qstring\":\"x\"}",
        "{\"operation\":\"decode\",\"qstring\":\"~~\",\"options\":{\"query\":\"canonical\"}}",
        "{\"operation\":\"encode\",\"reading\":\"ㄋ\",\"options\":{\"unknown\":true}}"
    };
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        result = (GuanyinmaResult *)(uintptr_t)1;
        STATUS(guanyinma_reading_codec((const uint8_t *)bad[i], strlen(bad[i]), &result), GUANYINMA_INVALID_ARGUMENT);
        REQUIRE(result == NULL);
    }
    STATUS(guanyinma_reading_codec(NULL, 1, &result), GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    const uint8_t invalid[] = {0xff};
    STATUS(guanyinma_reading_codec(invalid, 1, &result), GUANYINMA_INVALID_UTF8);
    REQUIRE(result == NULL);
    STATUS(guanyinma_reading_codec(NULL, 0, NULL), GUANYINMA_INVALID_ARGUMENT);
}

static void check_associated_phrases(GuanyinmaDatabase *database) {
    const char *request = "{\"head\":\"你\",\"collections\":[\"anime\",\"McBopomofo\"]}";
    GuanyinmaResult *result = NULL;
    STATUS(guanyinma_database_associated_phrases(database, (const uint8_t *)request,
                                               strlen(request), &result), GUANYINMA_OK);
    REQUIRE(row_count(result) > 9); /* UI pages must not truncate the core result. */
    char *json = result_json(result);
    REQUIRE(strstr(json, "\"kind\":\"associated_phrases\"") != NULL);
    REQUIRE(strstr(json, "\"key\":\"你\"") != NULL);
    REQUIRE(strstr(json, "\"rows\":[\"的名字\",\"的名字是\",\"的謊言\",\"已經死了\",\"想\",\"們\",\"的\",") != NULL);
    /* 想 appears in both collections, at the first collection's position. */
    const char *first = strstr(json, "\"想\"");
    REQUIRE(first != NULL && strstr(first + strlen("\"想\""), "\"想\"") == NULL);
    free(json);
    close_result(&result);

    request = "{\"head\":\"你\",\"collections\":[]}";
    STATUS(guanyinma_database_associated_phrases(database, (const uint8_t *)request,
                                               strlen(request), &result), GUANYINMA_OK);
    REQUIRE(row_count(result) == 0);
    close_result(&result);
    request = "{\"order\":\"display\"}";
    STATUS(guanyinma_database_associated_collections(database, (const uint8_t *)request,
                                                   strlen(request), &result), GUANYINMA_OK);
    REQUIRE(row_count(result) > 1);
    json = result_json(result);
    REQUIRE(strstr(json, "\"kind\":\"associated_collections\"") != NULL);
    REQUIRE(strstr(json, "\"rows\":[{\"source\":\"McBopomofo\",\"display\":\"小麥注音\",\"sort_order\":0},") != NULL);
    free(json);
    close_result(&result);

    const char *bad[] = {"{}", "{\"head\":\"你\",\"collections\":[],\"limit\":1}",
        "{\"head\":\"你\",\"collections\":[\"bad\\u0000source\"]}",
        "{\"head\":\"你\\u0000\",\"collections\":[]}"};
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        result = (GuanyinmaResult *)(uintptr_t)1;
        STATUS(guanyinma_database_associated_phrases(database, (const uint8_t *)bad[i],
                                                   strlen(bad[i]), &result), GUANYINMA_INVALID_ARGUMENT);
        REQUIRE(result == NULL);
    }
    request = "{\"order\":\"locale\"}";
    STATUS(guanyinma_database_associated_collections(database, (const uint8_t *)request,
                                                   strlen(request), &result), GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    STATUS(guanyinma_database_associated_phrases(NULL, NULL, 0, &result), GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    STATUS(guanyinma_database_associated_collections(NULL, NULL, 0, &result), GUANYINMA_INVALID_ARGUMENT);
    REQUIRE(result == NULL);
    STATUS(guanyinma_database_associated_phrases(database, NULL, 0, NULL), GUANYINMA_INVALID_ARGUMENT);
    STATUS(guanyinma_database_associated_collections(database, NULL, 0, NULL), GUANYINMA_INVALID_ARGUMENT);
    STATUS(guanyinma_database_associated_phrases(database, NULL, 1, &result), GUANYINMA_INVALID_ARGUMENT);
    STATUS(guanyinma_database_associated_collections(database, NULL, 1, &result), GUANYINMA_INVALID_ARGUMENT);
    const uint8_t invalid[] = {0xff};
    STATUS(guanyinma_database_associated_phrases(database, invalid, 1, &result), GUANYINMA_INVALID_UTF8);
    STATUS(guanyinma_database_associated_collections(database, invalid, 1, &result), GUANYINMA_INVALID_UTF8);
}

static int smoke_main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s /absolute/path/to/KeyKey.db /scratch/user-data.db\n", argv[0]);
        return EXIT_FAILURE;
    }
    REQUIRE(guanyinma_abi_version() == 1);
    check_reading_codec();
    GuanyinmaDatabase *database = NULL;
    STATUS(guanyinma_database_open((const uint8_t *)argv[1], strlen(argv[1]),
                                  &database),
           GUANYINMA_OK);
    REQUIRE(database != NULL);
    check_associated_phrases(database);

    GuanyinmaResult *result = query(database, GUANYINMA_QUERY_CANGJIE, "a");
    REQUIRE(row_count(result) == 2);
    char *json = result_json(result);
    REQUIRE(strstr(json, "\"schema_version\":1") != NULL);
    REQUIRE(strstr(json, "\"kind\":\"cangjie\"") != NULL);
    REQUIRE(strstr(json, "\"rows\":[\"日\",\"曰\"]") != NULL);
    free(json);
    check_complete_json_copy(result);
    close_result(&result);

    result = query(database, GUANYINMA_QUERY_TRADITIONAL, "\\O");
    REQUIRE(row_count(result) > 3);
    json = result_json(result);
    REQUIRE(strstr(json, "\"kind\":\"traditional\"") != NULL);
    REQUIRE(strstr(json, "\"rows\":[\"你\",\"妳\",\"擬\",") != NULL);
    free(json);
    close_result(&result);

    result = query(database, GUANYINMA_QUERY_SIMPLEX, "ab");
    REQUIRE(row_count(result) > 9);
    json = result_json(result);
    REQUIRE(strstr(json, "\"kind\":\"simplex\"") != NULL);
    REQUIRE(strstr(json, "\"rows\":[\"明\",\"晞\",\"晴\",\"閒\",") != NULL);
    free(json);
    close_result(&result);

    result = query(database, GUANYINMA_QUERY_UNIGRAMS, "!");
    REQUIRE(row_count(result) > 0);
    json = result_json(result);
    REQUIRE(strstr(json, "\"kind\":\"unigrams\"") != NULL);
    REQUIRE(strstr(json, "\"current\":\"\"") != NULL);
    free(json);
    close_result(&result);

    result = query(database, GUANYINMA_QUERY_BIGRAMS, "! ci");
    REQUIRE(row_count(result) > 0);
    json = result_json(result);
    REQUIRE(strstr(json, "\"kind\":\"bigrams\"") != NULL);
    REQUIRE(strstr(json, "\"previous\":\"\"") != NULL);
    REQUIRE(strstr(json, "\"current\":\"原\"") != NULL);
    free(json);
    close_result(&result);

    result = query(database, GUANYINMA_QUERY_CANGJIE,
                   "__guanyinma_missing_key__");
    REQUIRE(row_count(result) == 0);
    json = result_json(result);
    REQUIRE(strstr(json, "\"rows\":[]") != NULL);
    free(json);
    close_result(&result);

    /* A zero-length NULL key is an empty string, not an invalid Rust slice. */
    STATUS(guanyinma_database_query(database, GUANYINMA_QUERY_CANGJIE,
                                    NULL, 0, &result),
           GUANYINMA_OK);
    REQUIRE(row_count(result) == 0);
    close_result(&result);

    check_invalid_inputs(database, argv[1]);

    /* Immutable result memory belongs to Rust and is independent of the DB. */
    result = query(database, GUANYINMA_QUERY_CANGJIE, "a");
    STATUS(guanyinma_database_close(&database), GUANYINMA_OK);
    REQUIRE(database == NULL);
    STATUS(guanyinma_database_close(&database), GUANYINMA_OK);
    REQUIRE(row_count(result) == 2);
    json = result_json(result);
    REQUIRE(strstr(json, "\"rows\":[\"日\",\"曰\"]") != NULL);
    free(json);
    close_result(&result);

    check_user_archives(argv[1]);
    check_sessions(argv[1]);
    check_candidate_filters(argv[1]);
    check_native_behavior_controls(argv[1]);
    check_mark_and_explicit_input_modes(argv[1]);
    check_keyboard_contracts(argv[1]);
    check_smart_sessions(argv[1]);
    check_learning_sessions(argv[1], argv[2]);

    printf("Guanyinma C ABI consumer: %u checks passed\n", checks);
    return EXIT_SUCCESS;
}

#if defined(_WIN32)
/* Windows argv is UTF-16. Convert explicitly rather than depending on the
 * current ANSI code page or silently reducing the user-store path to ASCII. */
int wmain(int argc, wchar_t **wide_argv) {
    char **argv = (char **)calloc((size_t)argc + 1, sizeof(*argv));
    if (argv == NULL) return EXIT_FAILURE;
    int result = EXIT_FAILURE;
    for (int index = 0; index < argc; ++index) {
        const int required = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
            wide_argv[index], -1, NULL, 0, NULL, NULL);
        if (required <= 0) goto cleanup;
        argv[index] = (char *)malloc((size_t)required);
        if (argv[index] == NULL) goto cleanup;
        if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide_argv[index],
                -1, argv[index], required, NULL, NULL) != required) goto cleanup;
    }
    result = smoke_main(argc, argv);
cleanup:
    for (int index = 0; index < argc; ++index) free(argv[index]);
    free(argv);
    return result;
}
#else
int main(int argc, char **argv) {
    return smoke_main(argc, argv);
}
#endif
