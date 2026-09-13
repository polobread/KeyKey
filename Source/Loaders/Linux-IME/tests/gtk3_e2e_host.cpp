#include <gtk/gtk.h>

#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct TestState {
    GtkWidget *entry = nullptr;
    std::string artifactDirectory;
    std::string expectedCommit;
    std::string expectedLiteral;
    std::vector<std::string> requiredPreedits;
    std::vector<bool> sawPreedits;
    bool positiveComplete = false;
    bool clearedAfterPositive = false;
    bool success = false;
};

std::vector<std::string> split(const std::string &value, char separator) {
    std::vector<std::string> parts;
    std::size_t start = 0;
    while (start <= value.size()) {
        const std::size_t end = value.find(separator, start);
        parts.push_back(value.substr(start, end - start));
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return parts;
}

bool sawAllRequiredPreedits(const TestState &state) {
    for (const bool sawPreedit : state.sawPreedits) {
        if (!sawPreedit) {
            return false;
        }
    }
    return true;
}

std::string jsonString(const std::string &value) {
    std::ostringstream output;
    output << '"';
    for (const char rawCharacter : value) {
        const auto character = static_cast<unsigned char>(rawCharacter);
        switch (character) {
        case '"':
            output << "\\\"";
            break;
        case '\\':
            output << "\\\\";
            break;
        case '\b':
            output << "\\b";
            break;
        case '\f':
            output << "\\f";
            break;
        case '\n':
            output << "\\n";
            break;
        case '\r':
            output << "\\r";
            break;
        case '\t':
            output << "\\t";
            break;
        default:
            if (character < 0x20U) {
                output << "\\u" << std::hex << std::setw(4)
                       << std::setfill('0') << static_cast<unsigned>(character)
                       << std::dec;
            } else {
                output << static_cast<char>(character);
            }
        }
    }
    output << '"';
    return output.str();
}

void appendEvent(const TestState &state, const std::string &type,
                 const std::string &value) {
    std::ofstream output(state.artifactDirectory + "/host-events.log",
                         std::ios::app | std::ios::binary);
    output << type << '=' << value << '\n';

    std::ofstream jsonOutput(state.artifactDirectory + "/events.jsonl",
                             std::ios::app | std::ios::binary);
    jsonOutput << "{\"source\":\"gtk3-host\",\"type\":"
               << jsonString(type) << ",\"value\":" << jsonString(value)
               << "}\n";
}

void writeValue(const std::string &path, const std::string &value) {
    std::ofstream output(path, std::ios::trunc | std::ios::binary);
    output << value;
}

void onPreeditChanged(GtkEntry *, gchar *preedit, gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    const std::string value = preedit == nullptr ? "" : preedit;
    appendEvent(state, "preedit", value);
    for (std::size_t index = 0; index < state.requiredPreedits.size(); ++index) {
        if (value == state.requiredPreedits[index]) {
            state.sawPreedits[index] = true;
        }
    }
}

void onTextChanged(GtkEditable *editable, gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    const std::string value = gtk_entry_get_text(GTK_ENTRY(editable));
    appendEvent(state, "text", value);

    if (!state.positiveComplete && value == state.expectedCommit &&
        sawAllRequiredPreedits(state)) {
        state.positiveComplete = true;
        writeValue(state.artifactDirectory + "/positive-ready", value);
        return;
    }
    if (state.positiveComplete && value.empty()) {
        state.clearedAfterPositive = true;
        return;
    }
    if (state.clearedAfterPositive && value == state.expectedLiteral) {
        state.success = true;
        writeValue(state.artifactDirectory + "/final.txt", value);
        gtk_main_quit();
    }
}

gboolean onTimeout(gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    const std::string value = gtk_entry_get_text(GTK_ENTRY(state.entry));
    appendEvent(state, "timeout-text", value);
    writeValue(state.artifactDirectory + "/final.txt", value);
    gtk_main_quit();
    return G_SOURCE_REMOVE;
}

void onDestroy(GtkWidget *, gpointer) { gtk_main_quit(); }

} // namespace

int main(int argc, char **argv) {
    if (!gtk_init_check(&argc, &argv)) {
        return EXIT_FAILURE;
    }

    const char *artifactDirectory = std::getenv("KEYKEY_E2E_CASE_DIR");
    const char *expectedCommit = std::getenv("KEYKEY_E2E_EXPECTED_COMMIT");
    const char *expectedLiteral = std::getenv("KEYKEY_E2E_EXPECTED_LITERAL");
    const char *requiredPreedits = std::getenv("KEYKEY_E2E_REQUIRED_PREEDITS");
    if (artifactDirectory == nullptr || *artifactDirectory == '\0' ||
        expectedCommit == nullptr || *expectedCommit == '\0' ||
        expectedLiteral == nullptr || requiredPreedits == nullptr) {
        return EXIT_FAILURE;
    }

    TestState state;
    state.artifactDirectory = artifactDirectory;
    state.expectedCommit = expectedCommit;
    state.expectedLiteral = expectedLiteral;
    if (*requiredPreedits != '\0') {
        state.requiredPreedits = split(requiredPreedits, ',');
    }
    state.sawPreedits.assign(state.requiredPreedits.size(), false);

    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), "chichi77-keykey-gtk3-e2e");
    gtk_window_set_default_size(GTK_WINDOW(window), 480, 100);
    g_signal_connect(window, "destroy", G_CALLBACK(onDestroy), nullptr);

    state.entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(state.entry),
                                   "Keyboard input must arrive through the IME");
    g_signal_connect(state.entry, "preedit-changed",
                     G_CALLBACK(onPreeditChanged), &state);
    g_signal_connect(state.entry, "changed", G_CALLBACK(onTextChanged), &state);
    gtk_container_add(GTK_CONTAINER(window), state.entry);

    gtk_widget_show_all(window);
    gtk_widget_grab_focus(state.entry);
    g_timeout_add_seconds(20, onTimeout, &state);
    gtk_main();

    appendEvent(state, "result", state.success ? "passed" : "failed");
    return state.success ? EXIT_SUCCESS : EXIT_FAILURE;
}
