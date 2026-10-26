/*
 * Guanyinma C ABI, version 1.
 * Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 * See ../LICENSE.txt and the repository licensing map.
 */
#ifndef GUANYINMA_H
#define GUANYINMA_H

#include <stddef.h>
#include <stdint.h>

/* Match Rust extern C even when a Windows consumer uses /Gz. */
#if defined(_WIN32)
#define GUANYINMA_CALL __cdecl
#else
#define GUANYINMA_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GuanyinmaDatabase GuanyinmaDatabase;
typedef struct GuanyinmaResult GuanyinmaResult;
typedef struct GuanyinmaSession GuanyinmaSession;

/* UTF-8 byte span is borrowed only during the callback. 0 rejects, any other
 * int32_t accepts. NULL callback means accept all and ignores its context. */
typedef int32_t (GUANYINMA_CALL *GuanyinmaCandidateFilter)(
    void *context, const uint8_t *text, size_t text_length);

enum {
    GUANYINMA_OK = 0,
    GUANYINMA_INVALID_ARGUMENT = 1,
    GUANYINMA_INVALID_UTF8 = 2,
    GUANYINMA_DATABASE_ERROR = 3,
    GUANYINMA_SCHEMA_ERROR = 4,
    GUANYINMA_BUFFER_TOO_SMALL = 5,
    GUANYINMA_PANIC = 6
};

enum {
    GUANYINMA_QUERY_TRADITIONAL = 1,
    GUANYINMA_QUERY_CANGJIE = 2,
    GUANYINMA_QUERY_SIMPLEX = 3,
    GUANYINMA_QUERY_UNIGRAMS = 4,
    GUANYINMA_QUERY_BIGRAMS = 5
};

/*
 * Contract shared by all functions:
 *
 * - Statuses and query kinds have fixed-width int32_t/uint32_t ABI parameters.
 * - Input strings are UTF-8 byte spans, not NUL-terminated C strings. Embedded
 *   NUL, invalid UTF-8 and lengths over PTRDIFF_MAX are rejected. NULL + zero
 *   length represents an empty span; a database path must still be nonempty.
 * - Nonempty spans must point to readable memory. Non-NULL outputs must be
 *   aligned and writable. Input/output regions must not overlap. Functions
 *   cannot validate arbitrary non-NULL addresses or stale/copy-aliased handles.
 * - Open/query output slots must be unused (normally initialized to NULL).
 *   They are set to NULL on failure; do not overwrite a live handle with them.
 * - Database queries are internally serialized. No operation may race with
 *   close. Results are immutable, may be read concurrently, and remain valid
 *   after their database is closed.
 * - Close consumes the unique handle and sets the caller's slot to NULL;
 *   closing an already-NULL slot is harmless. Copies of a handle become stale
 *   after close and must never be read or closed.
 * - Rust owns handle allocations. Release them only with the matching close;
 *   never free them with the caller's allocator.
 * - Recoverable Rust unwinds are contained and return GUANYINMA_PANIC. Process
 *   aborts, allocation failure and invalid caller pointers are not recoverable.
 * - Successful ordinary calls clear the calling thread's last diagnostic.
 *   guanyinma_last_error itself never clears or replaces that diagnostic.
 */

uint32_t GUANYINMA_CALL guanyinma_abi_version(void);

/* Existing KeyKey.db only: read-only open, schema validation, no DB creation. */
int32_t GUANYINMA_CALL guanyinma_database_open(
    const uint8_t *path, size_t path_length, GuanyinmaDatabase **output);

int32_t GUANYINMA_CALL guanyinma_database_close(GuanyinmaDatabase **handle);

/*
 * Raw database lookups, not an input-method state machine or ranked composer.
 * Table keys and model qstrings are already encoded database keys, not physical
 * key sequences such as "su3". All matching rows retain database rowid order.
 *
 * JSON result schema:
 * {"schema_version":1,"kind":"traditional|cangjie|simplex|unigrams|bigrams",
 *  "key":"...","rows":[...]}
 *
 * Table rows are strings. Unigrams contain qstring/current/probability/backoff.
 * Bigrams contain qstring/previous/current/probability. BOS/EOS may contain empty
 * text. No raw SQL, arbitrary table names, learning or cooking is exposed.
 */
int32_t GUANYINMA_CALL guanyinma_database_query(
    const GuanyinmaDatabase *database, uint32_t kind,
    const uint8_t *key, size_t key_length, GuanyinmaResult **output);

/*
 * Additive input-session API. The database/query ABI above remains version 1.
 *
 * Each session owns its read-only model connection. Configuration is strict
 * UTF-8 JSON; an empty span uses desktop/traditional/standard defaults.
 * Supported input origins: desktop, touch. Origins select the explicitly
 * defined interaction policy; keyboard behavior choices are independent.
 * Supported methods: traditional, smart, cangjie, simplex.
 * Example: {"profile":"desktop","method":"traditional","layout":"standard"}
 * Smart composition behavior is configured independently of native platforms:
 * {"method":"smart","smart":{"max_completed_syllables":10,
 *   "space_opens_candidates":true,"candidate_cursor_at_end":false,
 *   "clear_composing_with_escape":false,"selection_returns_to_end":false}}
 * candidate_selection_keys defaults to eight layout-specific keys. The
 * completed-reading limit is 10..20. shift_at_limit=false shifts after the
 * limit; true shifts upon reaching it. Both use the same whole-phrase rule.
 * use_bigrams defaults true (canonical Manjusri); false scores unigrams without
 * Bigram or previous-context backoff. Runtime changes re-walk cached nodes,
 * preserving readings, explicit selections and cursor, without committing.
 * The model is always read-only.
 * User data uses a separate user_database path supplied by the frontend;
 * omitting it creates only an isolated in-memory store. Existing files must
 * be Guanyinma-owned; legacy SQLite data is imported explicitly read-only.
 * learning defaults: user_phrases=true, candidate_overrides=false,
 * bigrams=false, table_learning=false. Table learning additionally requires
 * that method's learn_selection option (Cangjie default true, Simplex false).
 * Keyboard choices are grouped in a strict behaviors object:
 * {"behaviors":{"ignore_caps_lock_in_chinese":true,"literal_keypad":true}}
 * Defaults are ignore_caps_lock_in_chinese=false and literal_keypad=true.
 * The core has no operating-system preset; adapters choose explicit behaviors.
 *
 * Operations are strict tagged JSON, e.g.
 * {"type":"character","text":"s"}
 * {"type":"character","text":"1","modifiers":{"keypad":true,"num_lock":true}}
 * {"type":"key","key":"space"}
 * {"type":"select","index":0}
 * {"type":"set_method","method":"cangjie"}
 * {"type":"set_profile","profile":"touch"}
 * {"type":"reset"}
 * {"type":"finish_composition","complete_reading":true,
 *  "select_highlighted_candidate":true,"discard_table_code":true}
 * {"type":"toggle_english"}
 * {"type":"set_english","enabled":true}
 * {"type":"set_english","enabled":false}
 * {"type":"toggle_full_width"}
 * {"type":"set_full_width","enabled":true}
 * {"type":"set_full_width","enabled":false}
 * {"type":"direct_text","text":"中文"}
 * {"type":"set_behaviors","behaviors":{"literal_keypad":false}}
 * {"type":"open_candidates","index":0}
 * {"type":"set_cursor","index":1}
 * {"type":"set_smart_options","options":{"max_completed_syllables":20}}
 * {"type":"close_candidates"}
 * {"type":"set_learning_options","options":{"candidate_overrides":true}}
 * {"type":"add_user_phrase","qstring":"0_0_","text":"士事"}
 * {"type":"remove_user_phrase","qstring":"0_0_","text":"士事"}
 * {"type":"replace_user_phrases","phrases":[]}
 * {"type":"reset_learning"}
 * {"type":"reset_method_learning","method":"smart"}
 * {"type":"save_learning"}
 * {"type":"import_legacy_user_data","path":"/caller/legacy.db"}
 *
 * add/update/remove phrases and learning updates commit atomically per apply.
 * replace_user_phrases validates and replaces the complete phrase publication
 * atomically, including deletions; smart/table learning and its epoch survive.
 * Repeating the same ordered rows is a no-op. Rows use the Unigram JSON shape.
 * reset_learning preserves custom words. reset_method_learning clears only
 * Smart or the named table method, preserving other methods. Import preserves the source and
 * unrelated methods. Same-query dictionary inserts are idempotent.
 * update_user_phrase supplies qstring/text and new_qstring/new_text together.
 * Session close has no implicit write. Save failures return no input effects.
 * finish_composition is an atomic frontend handoff policy. complete_reading
 * completes a valid unfinished Smart reading before finishing (an unmatched
 * reading remains literal); select_highlighted_candidate preserves the selected
 * non-Smart candidate without recording selection learning; discard_table_code
 * clears unconfirmed Cangjie/Simplex input instead of committing its roots.
 * All flags default false. The original finish operation remains unchanged.
 * If another writer changes an open candidate view, an obsolete selection
 * event is consumed with beep and a closed panel, never reassigned by index.
 * Identical candidate text/spans retain the current page and highlight.
 *
 * Setters are idempotent. set_english selects English (true) or Chinese
 * (false); an actual change preserves/finishes visible input once. Full-width
 * setters select full (true) or half (false), and preserve all reading,
 * composition, candidates and cursor. Toggle operations invert current state.
 * Shortcut/gesture recognition belongs to the frontend: Shift+Space has no
 * built-in width toggle. A frontend resolves it to an operation above, or
 * forwards an ordinary Space if its binding means something else.
 *
 * Smart shift_always_uppercase is a configurable text policy. Native physical
 * key translation belongs to the frontend. Shift-mark selection uses up to six
 * completed readings; marked_phrase contains scalar text_start/text_length and
 * separate reading_start/reading_span/qstring/text. Return adds that generated phrase
 * atomically without committing the sentence; effects.phrase_feedback gives
 * text/added, including an existing-word result. Stale marks are canceled.
 *
 * Table options include maximum_radical_length (1..128, null=method default),
 * space_as_first_selection_key, space_commits_first_on_single_page (null uses
 * the method default) and wildcards {one,many}. Omitted wildcards use method
 * defaults; explicit null symbols disable them. Wildcard characters must be
 * printable non-space ASCII. Only explicit candidate selections learn.
 * Simplex clear_on_error defaults false; realtime input always disables it.
 *
 * set_behaviors changes future event handling without flushing composition.
 * It replaces the behavior object; omitted fields use the defaults above.
 *
 * character.text is the actual translated Unicode scalar from the frontend.
 * modifiers describe its real event: shift/control/alt/command/caps_lock,
 * num_lock (global toggle), keypad (actual origin), repeat, release. They are
 * strict booleans, default false. Global num_lock alone never marks main-row
 * input as keypad. Num Lock-off navigation/editing is sent as key operations.
 * When literal_keypad is enabled, printable keypad input preserves/finishes
 * visible composition then inserts literal text, bypassing phonetic and
 * candidate-number processing. When disabled it follows ordinary key handling.
 * General keypad shortcut and release events remain unhandled in either case.
 *
 * In Chinese mode, ignore_caps_lock_in_chinese normalizes unshifted ASCII
 * letter case before phonetic/table handling. It does not change explicit
 * Shift text or English-mode character case; frontends must not case-convert
 * actual text a second time. Native frontends retain their Shift-tap timing
 * recognizer (currently 300 ms). Each gesture resolves to one toggle_english,
 * or set_english with the frontend's target mode. macOS first preserves host
 * text, then uses set_english. The Rust core has no Shift-tap clock. A core
 * mode change preserves visible composition; repeating set_english is inert.
 *
 * Key names use snake_case: return, backspace, escape, space, down, left,
 * right, home, end, page_up, page_down, delete, tab.
 * Unknown fields/values and invalid text are errors, not ignored commands.
 *
 * Smart cursor operations count completed readings, not bytes or UTF-16.
 * open_candidates targets an existing reading; set_cursor targets a boundary
 * in 0..readings.length. select is page-local and fixes only the selected span;
 * it does not commit the whole composing sentence. close_candidates preserves
 * the composing sentence and reading cursor. set_smart_options replaces
 * options (omitted fields default), closes candidates and preserves readings,
 * explicit selections and cursor. Scoring changes may update composed text.
 *
 * For smart results, composition is the completed graph text, reading is the
 * unfinished phonetic sequence and visible_text inserts it at the text cursor.
 * cursor counts Unicode scalars in visible_text; reading_cursor, readings,
 * segments and candidate_spans expose separate graph coordinates. Segment and
 * candidate start/span values count completed readings. Frontends translate to
 * native ranges; no operating-system coordinate policy is built into the core.
 *
 * apply returns an independently owned session snapshot. Its effects describe
 * only that operation; snapshot returns no new host effects. Complete ordered
 * candidates and displayed_candidates are distinct arrays. Result row_count
 * means the complete candidate count for session results.
 *
 * Session calls serialize internally. A close must not race with them.
 * Results remain valid after session_close. Caller-buffer and lifetime
 * contracts are identical to the database/result APIs.
 */
int32_t GUANYINMA_CALL guanyinma_session_open(
    const uint8_t *path, size_t path_length,
    const uint8_t *config, size_t config_length, GuanyinmaSession **output);

/*
 * Optional native font/encoding capability check for all four input methods.
 * Filtering precedes table single-candidate commits, prefix limits, candidate
 * pagination and selection learning, and Smart graph/candidate construction.
 * BOS/EOS model boundaries are exempt. Literal frontend input is not filtered.
 * Raw guanyinma_database_query results retain their unfiltered source order.
 *
 * The callback is synchronous, receives valid UTF-8 without a trailing NUL, and
 * must not retain the span, unwind/throw, or reenter the same session. It may be
 * called during open and later serialized session operations, on the calling
 * thread. The function and context must remain valid until session_close.
 * Context ownership stays with the caller. A session's mutex does not make a
 * context shared with other sessions safe; callers provide that synchronization.
 * Its capability decisions must stay stable throughout the session lifetime.
 * Callback/context are runtime-only and never enter JSON, user data or backups.
 * NULL callback is equivalent to guanyinma_session_open and ignores context.
 */
int32_t GUANYINMA_CALL guanyinma_session_open_with_candidate_filter(
    const uint8_t *path, size_t path_length,
    const uint8_t *config, size_t config_length,
    GuanyinmaCandidateFilter filter, void *filter_context,
    GuanyinmaSession **output);

int32_t GUANYINMA_CALL guanyinma_session_apply(
    const GuanyinmaSession *session,
    const uint8_t *operation, size_t operation_length, GuanyinmaResult **output);

int32_t GUANYINMA_CALL guanyinma_session_snapshot(
    const GuanyinmaSession *session, GuanyinmaResult **output);

/*
 * Validate a complete portable Guanyinma archive without opening a database or
 * session. No files or user state are changed. The archive is strict UTF-8 JSON:
 * {"format":"guanyinma_user_data","schema_version":1,"phrases":[...],
 *  "smart":{"overrides":[...],"bigrams":[...]},"table":[...]}
 * All phrase/learning row fields are required; unknown fields, duplicate keys,
 * invalid numbers and excessive learning caches are rejected.
 * smart/table may be omitted or null: import preserves that learning domain.
 * Present arrays replace their domain, including when empty. Custom phrases
 * merge without overwriting an existing (qstring,current) entry.
 * Generation/revision are local concurrency state and cannot be imported.
 * Apply the validated archive with {"type":"import_user_data","archive":...};
 * that operation validates again and atomically commits every requested domain.
 */
int32_t GUANYINMA_CALL guanyinma_user_archive_validate(
    const uint8_t *archive, size_t archive_length);

/*
 * An immutable {"schema_version":1,"kind":"user_data","data":{...}} result.
 * data contains generation/revision, phrases, overrides, bigrams and table.
 * No input or host effects are emitted. row_count is the custom phrase count.
 * The result remains valid after session_close.
 */
int32_t GUANYINMA_CALL guanyinma_session_user_data(
    const GuanyinmaSession *session, GuanyinmaResult **output);

int32_t GUANYINMA_CALL guanyinma_session_close(GuanyinmaSession **handle);

/* Raw query rows, full input candidates, or user-data custom phrase count. */
int32_t GUANYINMA_CALL guanyinma_result_row_count(
    const GuanyinmaResult *result, size_t *count);

/*
 * Caller-owned copy-out buffer. *required includes the trailing NUL. Probe with
 * destination=NULL, capacity=0 to obtain GUANYINMA_BUFFER_TOO_SMALL and the full
 * size. An insufficient buffer is unchanged (no partial JSON/UTF-8 is written).
 * *required is initialized to zero on argument errors when that pointer is valid.
 */
int32_t GUANYINMA_CALL guanyinma_result_json(
    const GuanyinmaResult *result, uint8_t *destination,
    size_t capacity, size_t *required);

int32_t GUANYINMA_CALL guanyinma_result_close(GuanyinmaResult **handle);

/* Same copy-out contract, preserving the current thread's original diagnostic. */
int32_t GUANYINMA_CALL guanyinma_last_error(
    uint8_t *destination, size_t capacity, size_t *required);

#ifdef __cplusplus
}
#endif

#endif /* GUANYINMA_H */
