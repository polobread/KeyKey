#include "FrontendSettings.h"
#include "SharedFileAccess.h"
#include "UserDataStore.h"
#include "PVPropertyList.h"
#include "LanguageModel.h"
#include "ModuleState.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <thread>
#include <atomic>
#include <stdexcept>
#include <functional>

namespace KeyKey::WindowsTsf {
HMODULE g_module=nullptr;
std::atomic<long> g_objectCount{0},g_serverLocks{0};
}
using namespace KeyKey::WindowsTsf;
using namespace OpenVanilla;
void Check(bool ok,const char* message) { if (!ok) throw std::runtime_error(message); }
std::string Read(const std::wstring& path) { std::string text; Check(ReadSharedSettingsFile(path,text),"Read shared settings"); return text; }
void Put(const std::wstring& path,const std::string& text) {
    SettingsFileLock lock(path); Check(static_cast<bool>(lock),"Settings lock");
    Check(WriteSharedSettingsFile(path,text),"Atomic settings replace");
}
std::unique_ptr<PVPlistValue> Parse(const std::wstring& path) {
    std::unique_ptr<PVPlistValue> result(PVPropertyList::ParsePlistFromString(Read(path).c_str()));
    Check(result && result->type()==PVPlistValue::Dictionary,"Settings reader saw incomplete XML"); return result;
}
void Writer(const std::wstring& path,const std::string& key,int iterations) {
    PVPropertyList file(OVUTF8::FromUTF16(path));
    for (int i=1;i<=iterations;++i) {
        file.readSync(true); file.rootDictionary()->setKeyValue(key,std::to_string(i)); file.write();
    }
}
void PlistChecks(const std::filesystem::path& profile) {
    const auto path=(profile/L"settings.plist").wstring();
    Put(path,"<plist><dict><key>A</key><string>0</string><key>B</key><string>0</string>"
        "<key>Array</key><array><string>A&amp;B</string></array></dict></plist>");
    PVPropertyList a(OVUTF8::FromUTF16(path)),b(OVUTF8::FromUTF16(path));
    a.rootDictionary()->setKeyValue("A","1"); a.write();
    b.rootDictionary()->setKeyValue("B","1"); b.write();
    auto merged=Parse(path);
    Check(merged->stringValueForKey("A")=="1" && merged->stringValueForKey("B")=="1" &&
        merged->valueForKey("Array")->arrayElementAtIndex(0)->stringValue()=="A&B","Stale plist overwrote unrelated keys");
    a.readSync(true); b.readSync(true);
    a.rootDictionary()->setKeyValue("A","2"); a.write();
    b.rootDictionary()->setKeyValue("A","stale"); b.write();
    Check(Parse(path)->stringValueForKey("A")=="2","Conflicting stale snapshot overwrote current disk value");
    b.readSync(true); b.rootDictionary()->setKeyValue("B","pending");
    const auto valid=Read(path);
    Put(path,"<plist><dict><key>broken</key><string>unfinished");
    const auto invalid=Read(path); b.write();
    Check(Read(path)==invalid,"Invalid existing file was overwritten with defaults");
    Put(path,valid); b.write();
    Check(Parse(path)->stringValueForKey("B")=="pending","Failed save incorrectly acknowledged its snapshot");

    std::atomic<bool> held{false},release{false};
    std::thread holder([&] { SettingsFileLock lock(path); held=true; while (!release) std::this_thread::yield(); });
    while (!held) std::this_thread::yield();
    b.readSync(true); b.rootDictionary()->setKeyValue("B","retry"); b.write();
    const bool preserved=Parse(path)->stringValueForKey("B")=="pending";
    release=true; holder.join(); Check(preserved,"Writer ignored another thread's shared lock");
    b.write(); Check(Parse(path)->stringValueForKey("B")=="retry","Lock timeout lost pending changes");

    std::atomic<bool> good{true};
    std::vector<std::thread> readers;
    for (int thread=0;thread<8;++thread) readers.emplace_back([&,thread] {
        const auto value=std::string(2048,static_cast<char>('a'+thread));
        const auto xml="<plist><dict><key>Value</key><string>"+value+"</string></dict></plist>";
        for (int i=0;i<100;++i) {
            std::unique_ptr<PVPlistValue> parsed(PVPropertyList::ParsePlistFromString(xml.c_str()));
            if (!parsed || parsed->stringValueForKey("Value")!=value) good=false;
        }
    });
    for (auto& reader : readers) reader.join(); Check(good,"Concurrent Expat parsing mixed static buffers");
    std::atomic<bool> stop{false};
    std::thread reader([&] { while (!stop) { try { Parse(path); } catch (...) { good=false; } } });
    Writer(path,"A",60); stop=true; reader.join(); Check(good,"Atomic replacement exposed incomplete file to readers");
    std::cout<<"Plist merge, conflicts, malformed input, lock timeout, parser threads and atomic readers passed\n";
}
DWORD Launch(const std::wstring& executable,std::wstring command,std::function<void()> concurrent={}) {
    STARTUPINFOW startup{sizeof(startup)}; PROCESS_INFORMATION process{};
    Check(CreateProcessW(executable.c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process),"Create isolated child");
    CloseHandle(process.hThread);
    if (concurrent) concurrent();
    const DWORD wait=WaitForSingleObject(process.hProcess,30000);
    DWORD result=1;
    if (wait==WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess,&result);
    else TerminateProcess(process.hProcess,1);
    CloseHandle(process.hProcess); Check(wait==WAIT_OBJECT_0,"Child timed out"); return result;
}
void ProcessChecks(const std::filesystem::path& profile,const std::wstring& executable,const std::wstring& prefix=L"") {
    const auto path=(profile/L"settings.plist").wstring();
    Put(path,"<plist><dict><key>A</key><string>0</string><key>B</key><string>0</string></dict></plist>");
    const auto command=L"\""+executable+L"\" "+prefix+L"--writer \""+path+L"\" B 60";
    const DWORD result=Launch(executable,command,[&] { Writer(path,"A",60); });
    Check(result==0,"Concurrent peer writer failed");
    auto data=Parse(path);
    Check(data->stringValueForKey("A")=="60" && data->stringValueForKey("B")=="60","Mixed-process writers lost a field");
    std::cout<<"Mixed-process settings writers preserved both fields\n";
    if (!prefix.empty()) {
        const auto ready=(profile/L"lock-ready").wstring(),release=(profile/L"lock-release").wstring();
        bool acquired=false,preserved=false;
        const auto held=Launch(executable,L"\""+executable+L"\" "+prefix+L"--hold-lock \""+path+L"\" \""+ready+L"\" \""+release+L"\"",[&] {
            const auto deadline=GetTickCount64()+5000;
            while (GetFileAttributesW(ready.c_str())==INVALID_FILE_ATTRIBUTES && GetTickCount64()<deadline) Sleep(10);
            acquired=GetFileAttributesW(ready.c_str())!=INVALID_FILE_ATTRIBUTES;
            if (acquired) { Writer(path,"A",1); preserved=Parse(path)->stringValueForKey("A")=="60"; }
            std::ofstream(std::filesystem::path(release))<<"release";
        });
        Check(held==0 && acquired && preserved,"Native writer did not honor managed settings mutex");
        Writer(path,"A",1); Check(Parse(path)->stringValueForKey("A")=="1","Save after managed lock release failed");
        std::cout<<"Native writer honored managed lock and resumed after release\n";
    }
}
struct Model {
    std::unique_ptr<OVSQLiteConnection> connection;
    std::unique_ptr<Manjusri::LanguageModel> model;
    Model(const std::filesystem::path& profile) {
        connection.reset(OVSQLiteConnection::Open(OVUTF8::FromUTF16((profile/L"model.db").wstring())));
        Check(connection!=nullptr,"Model connection");
        Check(connection->execute("CREATE TABLE IF NOT EXISTS unigrams(qstring,current,probability,backoff)")==SQLITE_OK &&
            connection->execute("CREATE TABLE IF NOT EXISTS bigrams(qstring,previous,current,probability)")==SQLITE_OK,"Test model schema");
        if (connection->execute("ATTACH DATABASE %Q AS userdb",OVUTF8::FromUTF16((profile/L"SmartMandarinUserData.db").wstring()).c_str())!=SQLITE_OK)
            throw std::runtime_error(std::string("Attach learning DB: ")+connection->lastErrorMessage());
        model=std::make_unique<Manjusri::LanguageModel>(connection.get(),nullptr,true,false,false,true,true);
        model->loadUserBigramCache(); model->loadUserCandidateOverrideCache();
    }
    int count(const char* table,const char* key=nullptr) {
        std::string sql="SELECT count(*) FROM userdb."+std::string(table);
        std::unique_ptr<OVSQLiteStatement> statement(connection->prepare((sql+(key ? " WHERE qstring=?" : "")).c_str()));
        Check(statement!=nullptr,"Prepare count learning rows");
        if (key) statement->bindTextToColumn(key,1);
        Check(statement->step()==SQLITE_ROW,"Count learning rows"); return statement->intOfColumn(0);
    }
    bool save() { return model->saveUserBigramCacheAndCandidateOverrideCache(true,true); }
};
void LearningChecks(const std::filesystem::path& profile) {
    Check(ResetUserLearning(),"Create test learning database");
    Model a(profile),b(profile);
    a.model->cacheOverrideSelection("A","甲"); a.model->cacheUserBigram("A","前","甲");
    b.model->cacheOverrideSelection("B","乙"); b.model->cacheUserBigram("B","前","乙");
    Check(a.save() && b.save(),"Save independent learning deltas");
    Check(a.count("user_candidate_override_cache")==2 && a.count("user_bigram_cache")==2,"Stale learning snapshot erased another host");
    a.model->cacheOverrideSelection("A","新甲"); Check(a.save(),"Update shared selection");
    b.model->cacheOverrideSelection("C","丙"); Check(b.save(),"Save unrelated selection from stale host");
    std::unique_ptr<OVSQLiteStatement> selected(a.connection->prepare("SELECT current FROM userdb.user_candidate_override_cache WHERE qstring='A'"));
    Check(selected && selected->step()==SQLITE_ROW && std::string(selected->textOfColumn(0))=="新甲","Unchanged stale selection replaced newer choice");
    selected.reset();
    Check(b.connection->execute("BEGIN")==SQLITE_OK &&
        b.connection->execute("UPDATE userdb.keykey_learning_metadata SET generation=generation WHERE id=1")==SQLITE_OK,"Hold user DB write lock");
    a.model->cacheOverrideSelection("retry","重試");
    Check(!a.save(),"Busy learning transaction was falsely reported saved");
    Check(b.connection->execute("ROLLBACK")==SQLITE_OK && a.save() && a.count("user_candidate_override_cache","retry")==1,"Busy transaction lost pending learning");
    a.model->cacheOverrideSelection("stale","舊");
    b.model->cacheOverrideSelection("older","更舊");
    Check(ResetUserLearning() && a.save() && b.save(),"Learning reset reconciliation failed");
    Check(a.count("user_candidate_override_cache")==0 && a.count("user_bigram_cache")==0,"Old host resurrected reset learning");
    a.model->cacheOverrideSelection("exported","匯出"); Check(a.save(),"Prepare learning export");
    const auto backup=(profile/L"backup.db").wstring(); Check(ExportUserData(backup),"Export isolated learning");
    a.model->cacheOverrideSelection("stale-import","過期");
    Check(ImportUserData(backup) && a.save() && a.count("user_candidate_override_cache","stale-import")==0 &&
        a.count("user_candidate_override_cache","exported")==1,"Old host overwrote imported learning");
    a.model->cacheOverrideSelection("fresh","新"); Check(a.save(),"Learning after reset stopped working");
    for (int i=0;i<220;++i) a.model->cacheOverrideSelection("bounded-"+std::to_string(i),"字");
    Check(a.save() && a.count("user_candidate_override_cache")<=200,"Shared learning exceeded cache capacity");
    std::unique_ptr<OVSQLiteStatement> integrity(a.connection->prepare("PRAGMA userdb.integrity_check"));
    Check(integrity && integrity->step()==SQLITE_ROW && std::string(integrity->textOfColumn(0))=="ok","Learning integrity check");
    std::cout<<"Learning deltas, busy rollback/retry, reset generation and capacity passed\n";
}
void LearnInChild(const std::filesystem::path& profile) {
    SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR",profile.c_str());
    Model child(profile);
    child.model->cacheOverrideSelection("child","子程序");
    child.model->cacheUserBigram("child","前","子程序");
    Check(child.save(),"Child learning save");
}
void ProcessLearningChecks(const std::filesystem::path& profile,const std::wstring& peer) {
    Check(ResetUserLearning(),"Reset isolated cross-process learning");
    Model parent(profile);
    parent.model->cacheOverrideSelection("parent","父程序");
    parent.model->cacheUserBigram("parent","前","父程序");
    Check(Launch(peer,L"\""+peer+L"\" --learn \""+profile.wstring()+L"\"")==0 && parent.save(),"Mixed-process learning save");
    Check(parent.count("user_candidate_override_cache")==2 && parent.count("user_bigram_cache")==2,
        "Mixed-process learning erased another host");
    std::cout<<"Mixed-process learning preserved both hosts\n";
}
int wmain(int argc,wchar_t** argv) {
    try {
        if (argc==5 && std::wstring(argv[1])==L"--writer") { Writer(argv[2],OVUTF8::FromUTF16(argv[3]),_wtoi(argv[4])); return 0; }
        if (argc==3 && std::wstring(argv[1])==L"--learn") { LearnInChild(argv[2]); return 0; }
        const auto profile=std::filesystem::temp_directory_path()/(L"keykey-shared-data-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(GetTickCount64()));
        std::filesystem::create_directories(profile); SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR",profile.c_str());
        struct Cleanup { std::filesystem::path path; ~Cleanup() { std::error_code error; std::filesystem::remove_all(path,error); } } cleanup{profile};
        PlistChecks(profile); LearningChecks(profile);
        wchar_t self[32768]{}; GetModuleFileNameW(nullptr,self,32768);
        if (argc==4 && std::wstring(argv[1])==L"--managed") ProcessChecks(profile,argv[2],L"\""+std::wstring(argv[3])+L"\" ");
        else { const std::wstring peer=argc==2 ? argv[1] : self; ProcessChecks(profile,peer); ProcessLearningChecks(profile,peer); }
        return 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
