#include "WindowsTableInputMethod.h"

#include <algorithm>
#include <map>
#include <memory>

namespace KeyKey::WindowsTsf {
namespace {
using namespace OpenVanilla;

class WindowsTableContext final : public OVIMGenericContext {
public:
    explicit WindowsTableContext(WindowsTableInputMethod* module)
        : OVIMGenericContext(module), module_(module) {}

    void startSession(OVLoaderService*) override {
        m_components.clear();
        m_lastCommittedString.clear();
        frequency_.reset();
        syncFrequency();
    }

    void stopSession(OVLoaderService*) override {
        frequency_.reset();
        m_components.clear();
        m_lastCommittedString.clear();
    }

    bool candidateSelected(OVCandidateService* candidates, const std::string& text,
                           size_t index, OVTextBuffer* reading,
                           OVTextBuffer* composing, OVLoaderService* service) override {
        // A short write transaction makes the increment atomic across text hosts.
        // Contention or an unwritable learning file must never prevent input.
        syncFrequency();
        if (frequency_ && index && frequency_->execute("BEGIN IMMEDIATE") == SQLITE_OK) {
            const std::string query = combineQueryString();
            std::unique_ptr<OVSQLiteStatement> update(frequency_->prepare(
                "UPDATE user_frequency SET count = count + 1 WHERE key = ? AND value = ?"));
            bool ok = false;
            if (update) {
                update->bindTextToColumn(query, 1);
                update->bindTextToColumn(text, 2);
                ok = update->step() == SQLITE_DONE;
                update.reset();
            }
            std::unique_ptr<OVSQLiteStatement> insert(frequency_->prepare(
                "INSERT INTO user_frequency SELECT ?, ?, 1 WHERE NOT EXISTS "
                "(SELECT 1 FROM user_frequency WHERE key = ? AND value = ?)"));
            if (ok && insert) {
                insert->bindTextToColumn(query, 1);
                insert->bindTextToColumn(text, 2);
                insert->bindTextToColumn(query, 3);
                insert->bindTextToColumn(text, 4);
                ok = insert->step() == SQLITE_DONE;
            } else {
                ok = false;
            }
            insert.reset();
            if (!ok || frequency_->execute("COMMIT") != SQLITE_OK)
                frequency_->execute("ROLLBACK");
        }
        return OVIMGenericContext::candidateSelected(
            candidates, text, index, reading, composing, service);
    }

protected:
    bool compose(OVTextBuffer* reading, OVTextBuffer* composing,
                 OVCandidateService* candidates, OVLoaderService* service,
                 bool sendIfOnlyOneCandidate = true) override {
        const bool result = OVIMGenericContext::compose(
            reading, composing, candidates, service, sendIfOnlyOneCandidate);
        auto* panel = candidates->useOneDimensionalCandidatePanel();
        if (!result) {
            panel->hide();
            panel->cancelEventHandler();
            return result;
        }
        if (panel->isVisible()) {
            panel->setCandidatesPerPage(std::min<size_t>(9, panel->candidateList()->size()));
            panel->updateDisplay();
        }
        syncFrequency();
        if (!frequency_ || !panel->isVisible()) return result;
        std::unique_ptr<OVSQLiteStatement> query(frequency_->prepare(
            "SELECT value, SUM(count) FROM user_frequency WHERE key = ? GROUP BY value"));
        if (!query) return result;
        query->bindTextToColumn(combineQueryString(), 1);
        std::map<std::string, int> counts;
        while (query->step() == SQLITE_ROW)
            counts[query->textOfColumn(0)] = query->intOfColumn(1);
        // Reorder only the already-filtered candidates. Learning must not bring
        // back excluded characters when the user switches to Big-5.
        auto* list = panel->candidateList();
        std::vector<std::string> values;
        for (size_t i = 0; i < list->size(); ++i) values.push_back(list->candidateAtIndex(i));
        std::stable_sort(values.begin(), values.end(), [&](const auto& a, const auto& b) {
            return counts[a] > counts[b];
        });
        list->setCandidates(values);
        panel->updateDisplay();
        return result;
    }

private:
    void syncFrequency() {
        if (!module_->dynamicFrequency()) { frequency_.reset(); return; }
        if (frequency_) return;
        frequency_.reset(OVSQLiteConnection::Open(module_->frequencyPath()));
        if (!frequency_) return;
        frequency_->execute("PRAGMA busy_timeout = 50");
        if (frequency_->execute("CREATE TABLE IF NOT EXISTS user_frequency "
                                "(key, value, count)") != SQLITE_OK ||
            frequency_->execute("CREATE INDEX IF NOT EXISTS user_frequency_index "
                                "ON user_frequency (key)") != SQLITE_OK)
            frequency_.reset();
    }

    WindowsTableInputMethod* module_;
    std::unique_ptr<OVSQLiteConnection> frequency_;
};
}  // namespace

WindowsTableInputMethod::WindowsTableInputMethod(
    const std::string& name, OpenVanilla::OVDatabaseService* database)
    : OVIMGeneric(name, database) {
    m_cfgUseDynamicFrequency = false;  // Match the old Windows preference default.
}

OpenVanilla::OVEventHandlingContext* WindowsTableInputMethod::createContext() {
    return new WindowsTableContext(this);
}

void WindowsTableInputMethod::loadConfig(OpenVanilla::OVKeyValueMap* config,
                                         OpenVanilla::OVLoaderService* service) {
    dynamicFrequency_ = config->hasKey("UseDynamicFrequency") &&
                        config->isKeyTrue("UseDynamicFrequency");
    // The old Simplex settings UI wrote this alias even when a canonical
    // default already existed. An explicit modern Apply marks it migrated.
    OVIMGeneric::loadConfig(config, service);
    if (config->hasKey("ComposeWhenTyping") &&
        !config->isKeyTrue("ComposeWhenTypingMigrated"))
        m_cfgComposeWhileTyping = config->isKeyTrue("ComposeWhenTyping");
    // The loader supplies a read-only configuration map. Keep learning out of
    // the base implementation without rewriting that map during loadConfig.
    delete m_userDatabaseConnection;
    m_userDatabaseConnection = nullptr;
    m_cfgUseDynamicFrequency = false;
    // Keep the table-specific code limits even with malformed preferences.
    m_cfgMaximumRadicalLength = m_name == "Generic-cj-cin" ? 5 : 2;
    if (m_cfgComposeWhileTyping) m_cfgClearReadingBufferAtCompositionError = false;
}

void WindowsTableInputMethod::saveConfig(OpenVanilla::OVKeyValueMap* config,
                                         OpenVanilla::OVLoaderService* service) {
    OVIMGeneric::saveConfig(config, service);
    config->setKeyBoolValue("UseDynamicFrequency", dynamicFrequency_);
    config->setKeyBoolValue("ComposeWhenTypingMigrated", true);
}

}  // namespace KeyKey::WindowsTsf
