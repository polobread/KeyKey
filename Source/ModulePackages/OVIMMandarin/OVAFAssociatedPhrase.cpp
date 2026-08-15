//
// OVAFAssociatedPhrase.cpp
//
// Copyright (c) 2004-2010 The OpenVanilla Project (http://openvanilla.org)
// All rights reserved.
// 
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//

#include "OVAFAssociatedPhrase.h"

#include <map>
#include <set>

namespace OpenVanilla {

const string RemoveHeadChar(const string& s)
{
    vector<string> v = OVUTF8Helper::SplitStringByCodePoint(s);
    v.erase(v.begin());
    return OVUTF8Helper::CombineCodePoints(v);
}

OVAFAssociatedPhraseContext::OVAFAssociatedPhraseContext(OVAFAssociatedPhrase* module)
    : m_module(module)
    , m_selectStatement(0)
    , m_keyHandled(false)
    , m_statementGeneration(0)
{
    rebuildStatementIfNeeded();
}

void OVAFAssociatedPhraseContext::rebuildStatementIfNeeded()
{
    if (m_selectStatement && m_statementGeneration == m_module->m_cfgGeneration)
        return;

    if (m_selectStatement) {
        delete m_selectStatement;
        m_selectStatement = 0;
    }

    m_statementGeneration = m_module->m_cfgGeneration;

    // No collections ticked is a legitimate choice, and it means no statement
    // to run at all rather than a query that matches nothing.
    if (m_module->m_cfgCollections.empty())
        return;

    // The IN list does not order the rows, so they are sorted back into the
    // user's collection order after the query.
    string query = "SELECT data, source FROM associated_phrases WHERE headchar = ? AND source IN (";
    for (size_t i = 0; i < m_module->m_cfgCollections.size(); ++i) {
        if (i)
            query += ", ";
        query += "'" + m_module->m_cfgCollections[i] + "'";
    }
    query += ")";

    m_selectStatement = m_module->m_phraseDB->prepare(query.c_str());
}

OVAFAssociatedPhraseContext::~OVAFAssociatedPhraseContext()
{
    if (m_selectStatement)
        delete m_selectStatement;
}
    
void OVAFAssociatedPhraseContext::startSession(OVLoaderService* loaderService)
{
    m_candidates.clear();
}

bool OVAFAssociatedPhraseContext::handleKey(OVKey* key, OVTextBuffer* readingText, OVTextBuffer* composingText, OVCandidateService* candidateService, OVLoaderService* loaderService)
{
    OVBenchmark benchmark;
    benchmark.start();
    // loaderService->logger("OVAFAssociatedPhraseContext") << "OVAFAPC, start: " << benchmark.elapsedSeconds() << endl;
    
//    OVOneDimensionalCandidatePanel* panel = candidateService->useVerticalCandidatePanel();
     OVOneDimensionalCandidatePanel* panel = candidateService->useOneDimensionalCandidatePanel();

	if (!m_candidates.size())  {
		if(panel->isVisible()) {
			panel->hide();
			panel->reset();
			panel->updateDisplay();
			return true;
		}
        return false;
	}
    
    if (key->keyCode() == OVKeyCode::PageUp) {
        panel->goToPreviousPage();
        panel->updateDisplay();
        return true;
    }
    
    if (key->keyCode() == OVKeyCode::PageDown || key->keyCode() == OVKeyCode::Space) {
        panel->goToNextPage();
        panel->updateDisplay();
        return true;
    }
		  
    bool absorbKey = false;
    
    char shiftKeys[10] = "!@#$%^&*(";
    size_t ski;
    for (ski = 0; ski < 9 ; ski++)
        if (key->keyCode() == shiftKeys[ski]) break;
    
    if (ski < 9 && key->isShiftPressed()) {
        if (ski >= panel->currentPageCandidateCount()) {
            loaderService->beep();
        }
        else {
            size_t index = panel->candidatesPerPage() * panel->currentPage() + ski;
            vector<string> cvec = OVUTF8Helper::SplitStringByCodePoint(m_candidates[index]);
            
            // the candidate is already a headless one, so.
            // cvec.erase(cvec.begin());
            composingText->setText(OVUTF8Helper::CombineCodePoints(cvec));
            composingText->commit();
        }
        
        absorbKey = true;
    }

    // we hide the candidate panel and clear state with any key other than LeftShift--we need the latter behavior
    // because we want to let the panel stay in Windows
    if (panel->isVisible() && key->keyCode() != OVKeyCode::LeftShift) {
        OVCandidateList* list = panel->candidateList();
        list->clear();
        m_candidates.clear();
        panel->hide();
        panel->reset();
        panel->updateDisplay();
    }    
    
    // we want to make the candidate panel disappear, but we also want to absorb the enter key
    if (key->keyCode() == OVKeyCode::Return)
        absorbKey = true;

	if (key->keyCode() == OVKeyCode::Esc)
        absorbKey = true;
//     
//  if(!key->isPrintable()) 
// //    if (key->keyCode() == OVKeyCode::Esc)
//         absorbKey = true;

    benchmark.stop();
    // loaderService->logger("OVAFAssociatedPhraseContext") << "OVAFAPC, stop: " << benchmark.elapsedSeconds() << endl;
    
    return absorbKey;
}

bool OVAFAssociatedPhraseContext::handleDirectText(const string& text, OVTextBuffer* readingText, OVTextBuffer* composingText, OVCandidateService* candidateService, OVLoaderService* loaderService)
{
    if (m_keyHandled) {
        m_keyHandled = false;
        return false;
    }

    if (!readingText->isEmpty() || !composingText->isEmpty())
        return false;
    
    // Preferences may have changed the selection since this context was made.
    rebuildStatementIfNeeded();

    vector<string> chrs = OVUTF8Helper::SplitStringByCodePoint(text);
    
    // loaderService->logger("OVAFAssociatedPhrase") << "handleDirectText: " << text << " (" << chrs.size() << ")" << endl;
    
    if (m_selectStatement && chrs.size() == 1 && composingText->isEmpty() && readingText->isEmpty()) {
        unsigned int codepoint = OVUTF8Helper::CodePointFromSingleUTF8String(chrs[0]);
        
        if (codepoint < 0x3000 || codepoint > 0xff00)
            return false;
    
        composingText->setText(text);
        composingText->commit();
        
        m_candidates.clear();
        m_selectStatement->reset();
        m_selectStatement->bindTextToColumn(chrs[0], 1);
        
        // One row per collection now, so gather them and lay them out in the
        // order the collections were ticked. Duplicates across collections are
        // dropped, keeping the first occurrence.
        map<string, vector<string> > bySource;
        while (m_selectStatement->step() == SQLITE_ROW)
            bySource[m_selectStatement->textOfColumn(1)] = OVStringHelper::Split(m_selectStatement->textOfColumn(0), ',');

        set<string> seen;
        for (vector<string>::const_iterator citer = m_module->m_cfgCollections.begin() ; citer != m_module->m_cfgCollections.end() ; ++citer) {
            map<string, vector<string> >::const_iterator found = bySource.find(*citer);
            if (found == bySource.end())
                continue;

            for (vector<string>::const_iterator piter = (*found).second.begin() ; piter != (*found).second.end() ; ++piter) {
                if (seen.insert(*piter).second)
                    m_candidates.push_back(*piter);
            }
        }
        
        if (m_candidates.size()) {
//            OVOneDimensionalCandidatePanel* panel = candidateService->useVerticalCandidatePanel();
            OVOneDimensionalCandidatePanel* panel = candidateService->useOneDimensionalCandidatePanel();
            OVCandidateList* list = panel->candidateList();
            list->clear();        
            list->setCandidates(m_candidates);
            panel->setCandidatesPerPage(9);
            panel->updateDisplay();
            panel->setHighlightIndex(panel->candidatesPerPage() + 1);

			string locale = loaderService->locale();
			if (locale == "zh_TW" || locale == "zh-Hant") {
			#ifndef _MSC_VER
				panel->setPrompt("SHIFT + 數字鍵");
			#else
				panel->setPrompt("SHIFT + \xE6\x95\xB8\xE5\xAD\x97\xE9\x8D\xB5");
			#endif
			}
			else {
				panel->setPrompt("SHIFT + NUM");
			}
            panel->show();
        }
        
        return true;
    }
        
    return false;
}

OVAFAssociatedPhrase::OVAFAssociatedPhrase()
    : m_phraseDB(0)
    , m_cfgConfigured(false)
    , m_cfgGeneration(0)
{
}

OVAFAssociatedPhrase::~OVAFAssociatedPhrase()
{
    // DON'T DELETE THE DB FROM LOADER SERVICE HERE!
    
    // if (m_phraseDB)
    //     delete m_phraseDB;
}

OVEventHandlingContext* OVAFAssociatedPhrase::createContext()
{
    return new OVAFAssociatedPhraseContext(this);
}

const string OVAFAssociatedPhrase::identifier() const
{
    return string(OVAFASSOCIATEDPHRASE_IDENTIFIER);
}

const string OVAFAssociatedPhrase::localizedName(const string& locale)
{
	#ifndef _MSC_VER
		string tcname = "聯想詞提示";
		string scname = "联想词提示";
	#else
		string tcname = "\xe8\x81\xaf\xe6\x83\xb3\xe8\xa9\x9e\xe6\x8f\x90\xe7\xa4\xba";
		string scname = "\xe8\x81\x94\xe6\x83\xb3\xe8\xaf\x8d\xe6\x8f\x90\xe7\xa4\xba";
	#endif 
	if (locale == "zh_TW" || locale == "zh-Hant")
		return tcname;
	else if (locale == "zh_CN" || locale == "zh-Hans")
		return scname;
	else
		return string("Associated Phrase");
}

bool OVAFAssociatedPhrase::initialize(OVPathInfo* pathInfo, OVLoaderService* loaderService)
{
	OVSQLiteDatabaseService* dbService = dynamic_cast<OVSQLiteDatabaseService*>(loaderService->SQLiteDatabaseService());
	if (!dbService) {
        // loaderService->logger("OVAFAssociatedPhrase") << "cannot obtain SQLite-backed DB service" << endl;
		return false;
	}
	
    //     // string dbPath = OVPathHelper::PathCat(pathInfo->resourcePath, "OpenVanilla.db");
    // string dbPath = dbService->filename();
    // 
    //     if (!OVPathHelper::PathExists(dbPath)) {
    //         loaderService->logger("OVAFAssociatedPhrase") << "db not found: " << dbPath << endl;
    //         return false;
    //     }
    // else {
    //  loaderService->logger("OVAFAssociatedPhrase") << "attempting to open: " << dbPath << endl;
    // }
    // m_phraseDB = OVSQLiteConnection::Open(dbPath);

    m_phraseDB = dbService->connection(); 
    
    if (!m_phraseDB->hasTable("associated_phrases")) {
        // loaderService->logger("OVAFAssociatedPhrase") << "doesn't have table required." << endl; // : " << dbPath << endl;
        // delete lmdb;
        return false;
    }
    
	return true;
}

void OVAFAssociatedPhrase::finalize()
{
}

void OVAFAssociatedPhrase::loadConfig(OVKeyValueMap* moduleConfig, OVLoaderService* loaderService)
{
    vector<string> previous = m_cfgCollections;

    m_cfgCollections.clear();
    m_cfgConfigured = moduleConfig->hasKey("EnabledCollections");

    // An absent key is a first run and gets McBopomofo. An empty one is the
    // user having unticked everything, which is left empty.
    string value = m_cfgConfigured ? moduleConfig->stringValueForKey("EnabledCollections") : string("McBopomofo");

    vector<string> names = OVStringHelper::Split(value, ',');
    for (vector<string>::const_iterator iter = names.begin() ; iter != names.end() ; ++iter) {
        string name = *iter;

        string::size_type first = name.find_first_not_of(" \t");
        if (first == string::npos)
            continue;
        string::size_type last = name.find_last_not_of(" \t");
        name = name.substr(first, last - first + 1);

        // The name goes straight into a quoted SQL literal, so anything that
        // could close the quote does not belong in a collection name.
        if (name.find('\'') != string::npos)
            continue;

        m_cfgCollections.push_back(name);
    }

    if (m_cfgCollections != previous)
        ++m_cfgGeneration;
}

void OVAFAssociatedPhrase::saveConfig(OVKeyValueMap* moduleConfig, OVLoaderService* loaderService)
{
    string value;
    for (size_t i = 0; i < m_cfgCollections.size(); ++i) {
        if (i)
            value += ",";
        value += m_cfgCollections[i];
    }

    moduleConfig->setKeyStringValue("EnabledCollections", value);
}

};
