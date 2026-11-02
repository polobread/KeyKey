#include "FrontendSettings.h"
#include "SharedFileAccess.h"
#include "LegacyUserDataTestFixture.h"
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
    const auto log=std::filesystem::temp_directory_path()/(L"keykey-child-"+std::to_wstring(GetCurrentProcessId())+L".log");
    SECURITY_ATTRIBUTES security{sizeof(security),nullptr,TRUE};
    const auto output=CreateFileW(log.c_str(),GENERIC_WRITE,FILE_SHARE_READ,&security,CREATE_ALWAYS,FILE_ATTRIBUTE_TEMPORARY,nullptr);
    Check(output!=INVALID_HANDLE_VALUE,"Create child output log");
    struct OutputCleanup {
        HANDLE handle; std::filesystem::path path;
        ~OutputCleanup() { CloseHandle(handle); std::error_code error; std::filesystem::remove(path,error); }
    } outputCleanup{output,log};
    startup.dwFlags=STARTF_USESTDHANDLES;
    startup.hStdOutput=output; startup.hStdError=output;
    startup.hStdInput=GetStdHandle(STD_INPUT_HANDLE);
    Check(CreateProcessW(executable.c_str(),command.data(),nullptr,nullptr,TRUE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process),"Create isolated child");
    CloseHandle(process.hThread);
    struct ProcessCleanup {
        HANDLE handle;
        ~ProcessCleanup() {
            if (WaitForSingleObject(handle,0)!=WAIT_OBJECT_0) {
                TerminateProcess(handle,1); WaitForSingleObject(handle,5000);
            }
            CloseHandle(handle);
        }
    } processCleanup{process.hProcess};
    if (concurrent) concurrent();
    const DWORD wait=WaitForSingleObject(process.hProcess,30000);
    DWORD result=1;
    if (wait==WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess,&result);
    else { TerminateProcess(process.hProcess,1); WaitForSingleObject(process.hProcess,5000); }
    if (result!=0 || wait!=WAIT_OBJECT_0) {
        std::cerr<<"Child exit code: "<<result<<"\n";
        std::ifstream captured(log); std::cerr<<captured.rdbuf();
    }
    Check(wait==WAIT_OBJECT_0,"Child timed out"); return result;
}
void WriteLockNames(const std::filesystem::path& input,const std::filesystem::path& output) {
    std::ifstream paths(input);
    std::ofstream names(output);
    std::string path;
    while (std::getline(paths,path)) names<<OVUTF8::FromUTF16(SettingsLockName(OVUTF16::FromUTF8(path)))<<'\n';
    Check(paths.eof() && names.good(),"Write native lock names");
}
void LockPathChecks(const std::filesystem::path& profile,const std::wstring& executable,const std::wstring& prefix) {
    const auto directory=profile/L"Settings mutex path aliases";
    std::filesystem::create_directory(directory);
    wchar_t longBuffer[32768]{},shortBuffer[32768]{};
    Check(GetLongPathNameW(directory.c_str(),longBuffer,32768)!=0,"Resolve long test directory");
    Check(GetShortPathNameW(directory.c_str(),shortBuffer,32768)!=0,"Resolve short test directory");
    const std::wstring longDirectory=longBuffer,shortDirectory=shortBuffer;
    if (shortDirectory.find(L'~')==std::wstring::npos || shortDirectory==longDirectory) {
        Check(GetEnvironmentVariableW(L"KEYKEY_TEST_REQUIRE_SHORT_PATHS",nullptr,0)==0,
            "Short-path regression requires a test volume with 8.3 aliases enabled");
        std::cout<<"Short-path cases skipped: test volume has no 8.3 aliases\n";
        return;
    }
    std::vector<std::pair<std::wstring,std::wstring>> paths;
    const auto add=[&](const std::wstring& suffix) {
        paths.emplace_back(shortDirectory+suffix,longDirectory+suffix);
    };
    add(L"\\settings.plist"); // The file does not exist yet.
    add(L"\\missing parent\\missing child\\settings.plist");
    add(L"\\literal~name\\settings.plist");
    add(L"\\設定 資料\\settings.plist");
    std::wstring deep;
    for (int i=0;i<20;++i) deep+=L"\\missing directory";
    add(deep+L"\\settings.plist"); // Expansion must also work beyond MAX_PATH.
    auto alternate=shortDirectory+L"/./missing/../settings.plist";
    paths.emplace_back(alternate,longDirectory+L"\\settings.plist");
    for (auto& value : alternate) if (value>=L'a' && value<=L'z') value-=L'a'-L'A';
    paths.emplace_back(alternate,longDirectory+L"\\settings.plist");
    const auto before=SettingsLockName(shortDirectory+L"\\settings.plist");
    const auto check=[&] {
        const auto input=profile/L"lock-paths.txt",output=profile/L"lock-names.txt";
        {
            std::ofstream file(input);
            for (const auto& [alias,expected] : paths) {
                Check(SettingsLockName(alias)==SettingsLockName(expected),"Native short/long path mutex mismatch");
                file<<OVUTF8::FromUTF16(alias)<<'\n'<<OVUTF8::FromUTF16(expected)<<'\n';
            }
        }
        Check(Launch(executable,L"\""+executable+L"\" "+prefix+L"--lock-names \""+input.wstring()+L"\" \""+output.wstring()+L"\"")==0,
            "Peer lock-name check failed");
        std::ifstream names(output);
        for (const auto& [alias,expected] : paths) {
            for (const auto& path : {alias,expected}) {
                std::string name; Check(static_cast<bool>(std::getline(names,name)),"Missing peer lock name");
                if (name!=OVUTF8::FromUTF16(SettingsLockName(path)))
                    std::cerr<<"Path: "<<OVUTF8::FromUTF16(path)<<"\nPeer: "<<name<<"\nNative: "<<OVUTF8::FromUTF16(SettingsLockName(path))<<'\n';
                Check(name==OVUTF8::FromUTF16(SettingsLockName(path)),"Peer path normalization differs from native");
            }
        }
    };
    check();
    Put(longDirectory+L"\\settings.plist","<plist><dict/></plist>");
    Check(before==SettingsLockName(shortDirectory+L"\\settings.plist"),"File creation changed mutex identity");
    Check(GetShortPathNameW((longDirectory+L"\\settings.plist").c_str(),shortBuffer,32768)!=0,"Resolve short file name");
    paths.emplace_back(shortBuffer,longDirectory+L"\\settings.plist");
    std::filesystem::create_directories(directory/L"missing parent"/L"missing child");
    check();
    std::cout<<"Short/long path mutex identity, absent parents, file creation, case and long paths passed\n";
}
void ProcessChecks(const std::filesystem::path& profile,const std::wstring& executable,const std::wstring& prefix=L"") {
    LockPathChecks(profile,executable,prefix);
    const auto path=(profile/L"settings.plist").wstring();
    if (!prefix.empty()) {
        Put(path,"<plist><dict><key>A</key><string>60</string><key>B</key><string>60</string></dict></plist>");
        const auto ready=(profile/L"lock-ready").wstring(),release=(profile/L"lock-release").wstring();
        bool acquired=false,preserved=false,sameName=false;
        const auto held=Launch(executable,L"\""+executable+L"\" "+prefix+L"--hold-lock \""+path+L"\" \""+ready+L"\" \""+release+L"\"",[&] {
            const auto deadline=GetTickCount64()+5000;
            while (GetFileAttributesW(ready.c_str())==INVALID_FILE_ATTRIBUTES && GetTickCount64()<deadline) Sleep(10);
            acquired=GetFileAttributesW(ready.c_str())!=INVALID_FILE_ATTRIBUTES;
            if (acquired) {
                sameName=Read(ready)==OVUTF8::FromUTF16(SettingsLockName(path));
                std::cerr<<"Native mutex: "<<OVUTF8::FromUTF16(SettingsLockName(path))
                    <<"\nManaged mutex: "<<Read(ready)<<'\n';
                Writer(path,"A",1); preserved=Parse(path)->stringValueForKey("A")=="60";
            }
            std::ofstream(std::filesystem::path(release))<<"release";
        });
        Check(held==0 && acquired && sameName && preserved,"Native writer did not honor managed settings mutex");
        Writer(path,"A",1); Check(Parse(path)->stringValueForKey("A")=="1","Save after managed lock release failed");
        std::cout<<"Native writer honored managed lock and resumed after release\n";
    }
    Put(path,"<plist><dict><key>A</key><string>0</string><key>B</key><string>0</string></dict></plist>");
    const auto command=L"\""+executable+L"\" "+prefix+L"--writer \""+path+L"\" B 60";
    const DWORD result=Launch(executable,command,[&] { Writer(path,"A",60); });
    Check(result==0,"Concurrent peer writer failed");
    auto data=Parse(path);
    if (data->stringValueForKey("A")!="60" || data->stringValueForKey("B")!="60")
        std::cerr<<"Mixed-process final fields: A="<<data->stringValueForKey("A")<<", B="<<data->stringValueForKey("B")<<'\n';
    Check(data->stringValueForKey("A")=="60" && data->stringValueForKey("B")=="60","Mixed-process writers lost a field");
    std::cout<<"Mixed-process settings writers preserved both fields\n";
}
struct InspectableLanguageModel : Manjusri::LanguageModel {
    using LanguageModel::LanguageModel;
    bool pendingWithinCapacity() const {
        return m_pendingBigrams.size()<=200 && m_pendingOverrides.size()<=200 &&
            m_pendingBigramOrder.size()==m_pendingBigrams.size() &&
            m_pendingOverrideOrder.size()==m_pendingOverrides.size();
    }
    bool pendingEmpty() const {
        return m_pendingBigrams.empty() && m_pendingOverrides.empty() &&
            m_pendingBigramOrder.empty() && m_pendingOverrideOrder.empty();
    }
};
struct CountingExternalTable : OVKeyValueDataTableInterface {
    int& destroyed;
    explicit CountingExternalTable(int& count) : destroyed(count) {}
    ~CountingExternalTable() override { ++destroyed; }
    const std::vector<std::string> valuesForKey(const std::string&) override { return {}; }
    const std::vector<std::pair<std::string,std::string>> valuesForKey(const OVWildcard&) override { return {}; }
    const std::string valueForProperty(const std::string&) override { return {}; }
};
struct Model {
    std::unique_ptr<OVSQLiteConnection> connection;
    std::unique_ptr<InspectableLanguageModel> model;
    Model(const std::filesystem::path& profile) {
        connection.reset(OVSQLiteConnection::Open(OVUTF8::FromUTF16((profile/L"model.db").wstring())));
        Check(connection!=nullptr,"Model connection");
        Check(connection->execute("CREATE TABLE IF NOT EXISTS unigrams(qstring,current,probability,backoff)")==SQLITE_OK &&
            connection->execute("CREATE TABLE IF NOT EXISTS bigrams(qstring,previous,current,probability)")==SQLITE_OK,"Test model schema");
        if (connection->execute("ATTACH DATABASE %Q AS userdb",OVUTF8::FromUTF16((profile/L"SmartMandarinUserData.db").wstring()).c_str())!=SQLITE_OK)
            throw std::runtime_error(std::string("Attach learning DB: ")+connection->lastErrorMessage());
        model=std::make_unique<InspectableLanguageModel>(connection.get(),nullptr,true,false,false,true,true);
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
void ExternalTableOwnershipChecks(OVSQLiteConnection* connection) {
    int destroyed=0;
    for (int i=0;i<100;++i) {
        { Manjusri::LanguageModel owned(connection,new CountingExternalTable(destroyed),false,false,false,false,false,true); }
        Check(destroyed==i+1,"Owned external table was not released exactly once");
    }
    int borrowedDestroyed=0;
    auto borrowed=std::make_unique<CountingExternalTable>(borrowedDestroyed);
    { Manjusri::LanguageModel model(connection,borrowed.get(),false,false,false); }
    Check(borrowedDestroyed==0,"Model released a caller-owned external table");
    borrowed.reset(); Check(borrowedDestroyed==1,"Borrowed table cleanup failed");
    std::cout<<"100 owned table retirements and borrowed table lifetime passed\n";
}
void LearningChecks(const std::filesystem::path& profile) {
    Check(ResetUserLearning(),"Create test learning database");
    Model a(profile),b(profile);
    ExternalTableOwnershipChecks(a.connection.get());
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
    Check(a.model->pendingEmpty() && b.model->pendingEmpty(),"Reset retained pending learning recency");
    Check(a.count("user_candidate_override_cache")==0 && a.count("user_bigram_cache")==0,"Old host resurrected reset learning");
    a.model->cacheOverrideSelection("exported","匯出"); Check(a.save(),"Prepare learning export");
    const auto backup=(profile/L"backup.db").wstring(); Check(ExportUserData(backup),"Export isolated learning");
    a.model->cacheOverrideSelection("stale-import","過期");
    Check(ImportUserData(backup) && a.save() && a.count("user_candidate_override_cache","stale-import")==0 &&
        a.count("user_candidate_override_cache","exported")==1,"Old host overwrote imported learning");
    a.model->cacheOverrideSelection("fresh","新"); Check(a.save(),"Learning after reset stopped working");
    for (int i=0;i<220;++i) a.model->cacheOverrideSelection("bounded-"+std::to_string(i),"字");
    Check(a.save() && a.count("user_candidate_override_cache")<=200,"Shared learning exceeded cache capacity");
    Check(a.model->pendingEmpty(),"Successful save retained pending learning recency");
    Check(ResetUserLearning() && a.save() && b.save(),"Reset before locked-capacity test");
    a.model->loadUserBigramCache(); a.model->loadUserCandidateOverrideCache();
    a.model->cacheOverrideSelection("erase-on-retry","刪除");
    Check(a.save() && a.count("user_candidate_override_cache","erase-on-retry")==1,"Prepare persisted deletion");
    Check(b.connection->execute("BEGIN IMMEDIATE")==SQLITE_OK,"Hold writer during capacity stress");
    for (int i=0;i<1000;++i) {
        const auto key="overflow-"+std::to_string(i), value="value-"+std::to_string(i);
        a.model->cacheOverrideSelection(key,value); a.model->cacheUserBigram(key,"前",value);
        a.model->cacheOverrideSelection("hot",value); a.model->cacheUserBigram("hot","前",value);
        // Refresh a deletion marker while other distinct keys overflow capacity.
        a.model->cacheOverrideSelection("erase-on-retry","刪除");
        a.model->removeCachedSelection("erase-on-retry");
        Check(a.model->pendingWithinCapacity(),"Failed saves exceeded pending capacity or duplicated recency keys");
        if (i%100==99) Check(!a.save(),"Locked capacity stress falsely reported saved");
    }
    Check(b.connection->execute("ROLLBACK")==SQLITE_OK && a.save(),"Capacity stress failed to recover");
    Check(a.model->pendingEmpty() && a.count("user_candidate_override_cache")<=200 &&
        a.count("user_bigram_cache")<=200,"Recovered learning retained excess memory or rows");
    for (const auto* table : {"user_candidate_override_cache","user_bigram_cache"}) {
        Check(a.count(table,"overflow-0")==0 && a.count(table,"overflow-999")==1,"Pending eviction lost recent learning or retained oldest key");
        std::unique_ptr<OVSQLiteStatement> latest(a.connection->prepare(
            ("SELECT current FROM userdb."+std::string(table)+" WHERE qstring='hot'").c_str()));
        Check(latest && latest->step()==SQLITE_ROW && std::string(latest->textOfColumn(0))=="value-999",
            "Repeated pending key lost its newest value");
    }
    Check(a.count("user_candidate_override_cache","erase-on-retry")==0,"Bounded retry lost deletion marker");
    std::unique_ptr<OVSQLiteStatement> integrity(a.connection->prepare("PRAGMA userdb.integrity_check"));
    Check(integrity && integrity->step()==SQLITE_ROW && std::string(integrity->textOfColumn(0))=="ok","Learning integrity check");
    std::cout<<"Learning deltas, locked pending capacity/recency/deletions, recovery and reset generation passed\n";
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
        if (argc==4 && std::wstring(argv[1])==L"--lock-names") { WriteLockNames(argv[2],argv[3]); return 0; }
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
