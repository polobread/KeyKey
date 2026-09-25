#!/usr/bin/env python3

"""Build 3,000 deterministic article assignments without generating articles."""

from collections import Counter
from pathlib import Path
import hashlib
import json
import random


SEED = 20260923
TARGET_CHARS = 1200
OUTPUT = Path(__file__).with_name("writing-prompts-v1.jsonl")
PREVIEW = Path(__file__).with_name("writing-prompts-preview.md")

ERA_CONFIG = [
    {
        "era": "1926-1945",
        "count": 300,
        "share": "10%",
        "settings": ["縱貫線小站", "大稻埕街屋", "港邊倉庫", "鄉間公學校", "糖廠宿舍", "市場亭仔腳", "山城診療所", "郵便局外"],
        "artifacts": ["舊布包", "木造月台", "手寫家書", "腳踏車", "收音機", "油紙傘", "布鞋", "車票"],
        "language": "以二十世紀上半葉在台灣可能出現的繁體中文書面語感重建；保持可讀性，不冒充真實史料。",
        "guard": "不得出現智慧型手機、網路、捷運等後世事物；涉及殖民統治時須避免虛構法令與真實人物言論。",
    },
    {
        "era": "1946-1969",
        "count": 360,
        "share": "12%",
        "settings": ["戰後眷舍", "鄉鎮火車站", "合作社門口", "黑白電影院", "國民學校教室", "加工出口工廠", "農村曬穀場", "碼頭候船室"],
        "artifacts": ["配給簿", "縫紉機", "黑白照片", "竹製便當盒", "廣播", "腳踏車牌", "藍色制服", "郵票"],
        "language": "使用戰後早期台灣的節制書面語與生活詞彙，對不同家庭背景保持尊重。",
        "guard": "不得套用今日社群媒體語氣；政治與社會背景只能作合理情境，不得杜撰具體史實。",
    },
    {
        "era": "1970-1989",
        "count": 540,
        "share": "18%",
        "settings": ["紡織工廠", "客運轉運站", "家庭代工客廳", "唱片行", "升學補習班", "海邊漁村", "新建公寓", "夜市攤位"],
        "artifacts": ["卡帶錄音機", "三用電表", "塑膠雨衣", "國語日報", "摩托車鑰匙", "薪水袋", "手寫聯絡簿", "電話簿"],
        "language": "呈現工業化、都市化與家庭生活轉變中的台灣繁體中文，不刻意仿古。",
        "guard": "科技、物價與交通描寫須符合年代；不要把後來才普及的裝置提前放入故事。",
    },
    {
        "era": "1990-1996",
        "count": 300,
        "share": "10%",
        "settings": ["電腦教室", "錄影帶出租店", "新開通的捷運工地旁", "社區圖書館", "證券行大廳", "連鎖便利商店", "高中社團教室", "傳統市場"],
        "artifacts": ["呼叫器", "磁碟片", "錄影帶", "投幣電話", "紙本地圖", "傳真紙", "隨身聽", "家庭電腦"],
        "language": "使用九〇年代前半台灣常見書面語與口語節奏，呈現類比生活走向數位化的過渡。",
        "guard": "不得使用尚未普及的智慧型手機與行動應用程式；涉及公共事件不得捏造新聞細節。",
    },
    {
        "era": "1997-2009",
        "count": 450,
        "share": "15%",
        "settings": ["撥接網路的家中書房", "網咖", "高中電腦教室", "高鐵車站", "社區大學", "辦公室茶水間", "夜市手機攤", "部落格讀書會"],
        "artifacts": ["光碟片", "按鍵手機", "即時通訊狀態", "數位相機", "電子信箱", "部落格留言", "悠遊卡", "高鐵票"],
        "language": "呈現網路與行動通訊快速進入台灣生活的語感，保留當時常見用詞。",
        "guard": "區分撥接、寬頻、按鍵手機與後來的智慧型手機功能，避免年代錯置。",
    },
    {
        "era": "2010-2019",
        "count": 450,
        "share": "15%",
        "settings": ["大學共學空間", "捷運車廂", "共同工作空間", "智慧型手機門市", "地方創生工作坊", "醫院候診區", "外送尚未普及的餐館", "社群活動現場"],
        "artifacts": ["智慧型手機", "行動電源", "社群貼文", "通訊軟體群組", "雲端文件", "行動支付試用貼紙", "共享單車", "平板電腦"],
        "language": "使用二〇一〇年代台灣自然繁體中文，呈現智慧型手機、社群與工作方式變化。",
        "guard": "不要把今日已成熟的生成式 AI 使用情境提前普及化；品牌與真實人物不作不實陳述。",
    },
    {
        "era": "2020-2026",
        "count": 600,
        "share": "20%",
        "settings": ["遠端會議中的住家", "校園自主學習教室", "捷運轉乘站", "外送取餐區", "區公所線上服務櫃台", "醫療視訊門診", "社區防災會議", "人工智慧工作坊"],
        "artifacts": ["視訊會議連結", "智慧型手機", "數位學習平台", "生成式人工智慧", "行動支付", "電子發票", "共享文件", "輸入法候選窗"],
        "language": "使用二〇二〇年代台灣自然、清楚且不過度網路化的繁體中文，兼顧口語與正式書面語。",
        "guard": "不得把尚未確定的科技能力寫成事實；避免真實個資、網路霸凌細節與未經查證的公共資訊。",
    },
]

GENRE_CONFIG = [
    {
        "genre": "日常生活、社群與對話",
        "count": 600,
        "aim": "從具體生活事件呈現人物關係與選擇，對話需推動情節。",
        "angles": ["家庭溝通", "世代差異", "朋友互助", "鄰里關係", "個人界線", "時間管理", "消費選擇", "數位禮貌"],
        "topics": [
            ("親情", "一只舊提袋", "家人把關心藏在命令裡"),
            ("成長", "聯絡簿", "學生想獨立卻害怕犯錯"),
            ("信任", "備用鑰匙", "承諾與臨時變動發生衝突"),
            ("陪伴", "餐桌上的空位", "忙碌讓家人難以好好說話"),
            ("期待", "成績單", "父母的盼望成為孩子的壓力"),
            ("友誼", "雨傘", "誤會在沒有說完的訊息中擴大"),
            ("選擇", "購物清單", "需要與想要難以分辨"),
            ("責任", "值日表", "團體工作分配不平均"),
        ],
    },
    {
        "genre": "工作、商業與公文",
        "count": 420,
        "aim": "交代工作情境、利害關係與可執行決策，避免只有口號。",
        "angles": ["職場溝通", "專業倫理", "組織改變", "服務品質", "勞動價值", "風險判斷", "交接責任", "創業取捨"],
        "topics": [
            ("合作", "會議紀錄", "團隊對優先順序沒有共識"),
            ("誠信", "報價單", "短期利益可能傷害長期信任"),
            ("轉型", "老店招牌", "傳統做法遇到新消費習慣"),
            ("專業", "工具箱", "速度與品質無法同時滿足"),
            ("服務", "叫號單", "制度效率忽略個別需要"),
            ("勞動", "薪水袋", "看不見的工作容易被低估"),
            ("交接", "工作筆記", "關鍵經驗只存在某人記憶中"),
            ("創業", "第一張訂單", "理想與現金流彼此拉扯"),
        ],
    },
    {
        "genre": "科技、軟體與輸入法",
        "count": 360,
        "aim": "以使用者經驗說明科技帶來的便利、代價與設計責任。",
        "angles": ["人機互動", "資料隱私", "數位落差", "軟體更新", "人工智慧", "輸入習慣", "資訊安全", "可近用性"],
        "topics": [
            ("專注", "手機通知", "工具協助學習也持續打斷注意力"),
            ("習慣", "輸入法候選窗", "更新改變長年累積的手指記憶"),
            ("隱私", "權限提示", "便利功能要求過多個人資料"),
            ("判斷", "人工智慧回答", "快速生成內容可能掩蓋錯誤"),
            ("安全", "驗證碼", "使用便利與帳號保護互相拉扯"),
            ("包容", "字幕按鈕", "設計忽略不同使用者的能力"),
            ("保存", "舊檔案", "格式更新讓數位記憶難以開啟"),
            ("連線", "分享連結", "協作效率伴隨權限失控風險"),
        ],
    },
    {
        "genre": "新聞與公共議題",
        "count": 360,
        "aim": "呈現不同立場、共同事實與政策取捨，結論須承認限制。",
        "angles": ["公共利益", "程序正義", "城鄉差距", "媒體識讀", "災害治理", "居住問題", "能源選擇", "世代公平"],
        "topics": [
            ("參與", "公聽會通知", "決策速度與居民表達權衝突"),
            ("查證", "新聞截圖", "情緒化轉傳快過事實核對"),
            ("安全", "防災地圖", "有限資源需要決定配置順序"),
            ("居住", "租屋契約", "市場價格與基本生活需求拉扯"),
            ("交通", "施工告示", "整體建設造成個別生活不便"),
            ("能源", "電費單", "穩定供應與環境成本難以兼顧"),
            ("地方", "里民公告", "中央標準未必符合地方條件"),
            ("公平", "申請表", "一致規則可能造成不同結果"),
        ],
    },
    {
        "genre": "教育與知識",
        "count": 300,
        "aim": "把概念放入具體學習情境，兼顧知識理解、方法與反思。",
        "angles": ["學習動機", "歷史思辨", "閱讀方法", "媒體素養", "考試制度", "自主學習", "師生互動", "跨域理解"],
        "topics": [
            ("學習", "筆記本", "記住答案與真正理解並不相同"),
            ("歷史", "年代表", "英雄敘事容易忽略群體與制度"),
            ("閱讀", "書頁摺角", "快速摘要可能取代深入閱讀"),
            ("提問", "黑板上的問號", "害怕答錯使學生不敢發言"),
            ("評量", "考卷", "分數無法呈現所有學習成果"),
            ("自主", "學習計畫", "自由選題也需要自我管理"),
            ("工具", "搜尋框", "找到資料不等於判斷資料"),
            ("實作", "實驗紀錄", "失敗過程常比正確答案重要"),
        ],
    },
    {
        "genre": "醫療健康",
        "count": 240,
        "aim": "以生活經驗呈現健康選擇與照護關係，不提供武斷診斷。",
        "angles": ["預防保健", "照護壓力", "醫病溝通", "心理健康", "高齡生活", "運動習慣", "公共衛生", "健康資訊"],
        "topics": [
            ("照護", "藥袋", "家屬關心與病人自主需要協調"),
            ("溝通", "候診號碼", "短暫看診難以說清長期症狀"),
            ("休息", "關掉的鬧鐘", "忙碌文化使人忽略身體訊號"),
            ("陪伴", "復健紀錄", "進步緩慢考驗病人與家屬"),
            ("資訊", "健康文章", "網路建議可能缺少個別條件"),
            ("運動", "河堤步道", "追求成績可能超過身體負荷"),
            ("老化", "放大鏡", "安全照顧與自主生活互有張力"),
            ("防疫", "口罩收納袋", "個人方便與群體保護需要平衡"),
        ],
    },
    {
        "genre": "交通、旅遊與地方生活",
        "count": 240,
        "aim": "透過移動路線與地方細節寫出人、環境及記憶的關係。",
        "angles": ["通勤經驗", "地方認同", "觀光影響", "交通安全", "返鄉記憶", "無障礙移動", "城鄉連結", "環境承載"],
        "topics": [
            ("返鄉", "車票", "離開故鄉後重新理解熟悉街道"),
            ("通勤", "月台廣播", "效率與擁擠改變人的互動"),
            ("地方", "老地圖", "開發帶來便利也改變共同記憶"),
            ("安全", "反光背心", "個人趕時間增加公共風險"),
            ("旅行", "行李標籤", "打卡清單遮住真正的觀察"),
            ("無障礙", "電梯指標", "看似順暢的路線並非人人可用"),
            ("連結", "末班公車", "偏遠地區承受較高移動成本"),
            ("環境", "步道告示", "觀光收入與自然承載互相拉扯"),
        ],
    },
    {
        "genre": "文化、飲食與農業",
        "count": 240,
        "aim": "由技藝、飲食或土地經驗呈現文化如何變動與傳承。",
        "angles": ["飲食記憶", "技藝傳承", "土地倫理", "市場文化", "節慶變遷", "語言保存", "農業轉型", "文化再現"],
        "topics": [
            ("味道", "搪瓷飯碗", "家常菜在世代之間改變做法"),
            ("技藝", "磨舊的工具", "傳統工法難以吸引年輕學徒"),
            ("土地", "田埂", "產量需求與環境維護彼此衝突"),
            ("市場", "手寫價牌", "人情交易遇上標準化管理"),
            ("節慶", "供桌", "儀式簡化引發不同世代理解"),
            ("語言", "錄音帶", "家庭不再使用熟悉的母語"),
            ("農業", "產銷履歷", "新技術提高效率也增加成本"),
            ("再現", "展覽說明牌", "外來觀看容易把文化固定化"),
        ],
    },
    {
        "genre": "散文、書信與評論",
        "count": 240,
        "aim": "以可感細節承載思想或情感，避免直接宣告大道理。",
        "angles": ["親情書寫", "物件記憶", "城市觀察", "自然感受", "自我反省", "書信往返", "閱讀回應", "價值評論"],
        "topics": [
            ("父愛", "舊布包", "沉默的照顧多年後才被理解"),
            ("母女", "針線盒", "相似的期待造成彼此誤會"),
            ("記憶", "褪色照片", "個人回憶與家人說法並不一致"),
            ("告別", "月台長椅", "一次普通離別留下長久重量"),
            ("城市", "窗邊盆栽", "快速變動使熟悉景物逐漸消失"),
            ("自然", "午後陣雨", "短暫停留改變原本匆忙步調"),
            ("反省", "未寄出的信", "多年沉默需要重新說明"),
            ("閱讀", "書籤", "舊文章在不同年紀產生新理解"),
        ],
    },
]

PERSPECTIVES = ["第一人稱回憶", "第一人稱現場觀察", "第三人稱限知", "雙線交錯敘事", "書信體", "日記與現場交錯", "採訪者視角", "多角色片段組合"]
STRUCTURES = ["由一個動作開場，經過衝突與理解後回到同一物件", "以一天的時間推進，讓細節逐步改變人物判斷", "先寫結果，再回溯造成結果的三個關鍵場景", "用兩個世代的選擇互相映照，最後保留開放問題", "從一項日常用品切入，逐層連結家庭與社會變化", "安排一次誤解、一次對話及一次未說出口的反省", "先呈現支持立場，再處理反方理由與現實限制", "以地點移動串接三個片段，結尾回到出發處"]
REGIONS = ["北部都會", "北部郊區", "中部城市", "中部農村", "南部城市", "南部鄉鎮", "東部地區", "離島或海港"]
TITLE_PATTERNS = [
    "{object}留下的{keyword}",
    "{setting}裡的{keyword}",
    "從{object}看見{keyword}",
    "{keyword}的重量",
    "當{keyword}遇上現實",
    "那一天我重新理解{keyword}",
    "{object}與一場改變",
    "面對{keyword}的難題",
    "留在{object}裡的話",
    "離開{setting}以後",
    "一場關於{keyword}的選擇",
    "{keyword}從{setting}說起",
]

GENRE_SETTINGS = {
    "工作、商業與公文": ["店舖後場", "工場工作桌", "辦公桌旁", "倉庫入口", "商行帳房", "服務窗口", "會議室", "交接班現場"],
    "科技、軟體與輸入法": ["修理店工作桌", "學校實驗教室", "家中書桌", "工場機械旁", "廣播設備室", "印刷工作間", "辦公桌旁", "電器行"],
    "新聞與公共議題": ["地方集會場", "行政服務窗口", "街道說明會", "社區公告欄", "河堤工程現場", "市場入口", "學校禮堂", "報社編輯桌"],
    "教育與知識": ["學校教室", "圖書室", "操場邊", "教師辦公室", "自習空間", "實驗教室", "社團教室", "家中書桌"],
    "醫療健康": ["診所候診區", "醫院走廊", "藥局櫃台", "復健室", "家中餐桌", "社區健康站", "河堤步道", "照護者房間"],
    "交通、旅遊與地方生活": ["地方車站月台", "候車亭", "渡船碼頭", "返鄉道路", "市場旁路口", "山區步道入口", "客運候車室", "港邊道路"],
    "文化、飲食與農業": ["傳統市場", "家中廚房", "農田邊", "廟埕", "手工作坊", "漁港拍賣場", "節慶準備處", "老店灶腳"],
}

HISTORICAL_TECH_TOPICS = {
    "1926-1945": [
        ("傳播", "礦石收音機", "新消息傳得更快也可能造成誤解"),
        ("速度", "電報紙", "快速傳訊與完整說明難以兼顧"),
        ("書寫", "打字機", "機械化文字改變辦公與排版習慣"),
        ("知識", "印刷鉛字", "大量印刷擴大閱讀也影響內容選擇"),
        ("光影", "電影放映機", "新媒介帶來見聞也改變地方娛樂"),
        ("照明", "電燈開關", "新設備改善生活卻不是家家可用"),
        ("交通", "列車時刻表", "標準時間改變人們安排生活的方式"),
        ("聯絡", "電話聽筒", "遠距通話仍受設備與費用限制"),
    ],
    "1946-1969": [
        ("聯絡", "轉盤電話", "即時通話便利但線路與費用有限"),
        ("傳播", "電晶體收音機", "家庭從同一段廣播理解外界消息"),
        ("影像", "黑白電視", "新媒介改變晚間生活與共同話題"),
        ("生產", "縫紉機", "機械提高效率也改變家庭分工"),
        ("勞動", "工廠機台", "產量要求與操作安全產生衝突"),
        ("印刷", "油印機", "教材複製變快仍需要人工校對"),
        ("保存", "盤式錄音帶", "聲音可以留下卻不容易長期保存"),
        ("家電", "電風扇", "新用品改善生活但增加家庭支出"),
    ],
    "1970-1989": [
        ("聲音", "卡帶錄音機", "複製與分享音樂改變聆聽習慣"),
        ("計算", "電子計算機", "工具提高速度也可能弱化心算練習"),
        ("影像", "彩色電視", "家庭娛樂增加也改變相處時間"),
        ("工作", "傳真機", "文件傳送加快但錯誤也更快擴散"),
        ("學習", "電腦終端機", "新工具帶來機會也形成設備落差"),
        ("修理", "三用電表", "依賴技術設備仍需要基本判斷"),
        ("自動化", "工廠控制面板", "提高產量也要求勞工學習新技能"),
        ("遊戲", "大型電玩機台", "新娛樂吸引年輕人也引發家庭擔心"),
    ],
    "1990-1996": [
        ("聯絡", "呼叫器", "快速找到一個人也增加隨時回覆的壓力"),
        ("社群", "電子布告欄", "陌生人交流擴大也需要判斷資訊真偽"),
        ("文件", "傳真機", "立即傳送文件仍可能因模糊而誤解"),
        ("保存", "磁碟片", "數位資料方便攜帶也容易損壞遺失"),
        ("學習", "家庭電腦", "新設備開啟探索也拉大資源差距"),
        ("連線", "撥接數據機", "進入網路需要時間並占用家中電話"),
        ("書寫", "中文文書軟體", "輸入與排版工具改變寫作流程"),
        ("行動", "早期行動電話", "可移動通話仍受到價格與體積限制"),
    ],
}

ERA_BANNED_TOPIC_TERMS = {
    "1926-1945": ["手機", "人工智慧", "驗證碼", "分享連結", "字幕按鈕", "搜尋框", "產銷履歷", "新聞截圖", "電梯指標", "雲端", "社群"],
    "1946-1969": ["手機", "人工智慧", "驗證碼", "分享連結", "搜尋框", "產銷履歷", "新聞截圖", "雲端", "社群"],
    "1970-1989": ["智慧型手機", "人工智慧", "驗證碼", "分享連結", "搜尋框", "產銷履歷", "新聞截圖", "雲端"],
    "1990-1996": ["智慧型手機", "人工智慧", "分享連結", "產銷履歷", "雲端文件", "社群貼文"],
}

HISTORICAL_TECH_ANGLES = ["技術普及", "操作技能", "資訊傳播", "設備成本", "工作改變", "安全維護", "城鄉差距", "新舊習慣"]


def anchor_prompts():
    common_avoid = ["不得沿用名作原句或改寫原文情節", "不得虛構真實人物引言", "不得混用簡體字", "避免制式的正能量結尾"]
    return [
        {
            "id": "tw-writing-0001",
            "era": "1926-1945",
            "genre": "散文、書信與評論",
            "title": "月台邊的舊布包",
            "target_chars": TARGET_CHARS,
            "accepted_char_range": [1050, 1350],
            "region": "北部郊區",
            "perspective": "第一人稱成年後回憶",
            "scenario": "以二十世紀上半葉台灣的木造小站為背景，寫一位不善言辭的父親送孩子離鄉，舊布包與幾個笨拙動作成為多年後理解親情的線索。",
            "requirements": ["參考朱自清《背影》的白描、動作細節、物件象徵與含蓄親情技法", "不得沿用《背影》的原句、人物、橘子情節或段落結構", "至少描寫三個父親沒有直接說愛、卻表現照顧的動作", "交代當時交通、衣著與家庭經濟情境，但不冒充真實史料", "情感轉折必須由具體回憶觸發", "結尾回到舊布包，不直接喊出孝順口號"],
            "language_requirements": ["使用可讀的早期繁體中文書面語感", "對話簡短克制", "約一千二百字"],
            "avoid": common_avoid,
            "evaluation": ["細節能否承載情感", "年代是否一致", "是否形成獨立故事而非名作仿寫"],
        },
        {
            "id": "tw-writing-0002",
            "era": "2020-2026",
            "genre": "教育與知識",
            "title": "掌心裡的教室：手機與學生學習",
            "target_chars": TARGET_CHARS,
            "accepted_char_range": [1050, 1350],
            "region": "北部都會",
            "perspective": "學生第一人稱與教師觀察交錯",
            "scenario": "描寫手機同時是查資料、協作與分心工具，從一堂需要手機完成任務的課開始，討論學生如何建立自主界線。",
            "requirements": ["呈現至少兩種手機幫助學習的方式", "呈現通知、短影音或聊天打斷專注的具體場景", "比較全面禁止與共同訂規則的利弊", "納入家庭資源差異與數位落差", "提出可執行的班級與個人做法", "結論保留學生自主與教師責任之間的張力"],
            "language_requirements": ["使用現代台灣校園常見繁體中文", "論述與敘事各占一定比例", "約一千二百字"],
            "avoid": ["不得把所有學生概括成手機成癮", "不得捏造研究數字", "不得使用空泛科技口號", "不得混用簡體字"],
            "evaluation": ["觀點是否平衡", "例子是否具體", "建議是否可執行"],
        },
        {
            "id": "tw-writing-0003",
            "era": "2020-2026",
            "genre": "教育與知識",
            "title": "從多次挫折到辛亥革命：革命精神如何形成",
            "target_chars": TARGET_CHARS,
            "accepted_char_range": [1050, 1350],
            "region": "全台",
            "perspective": "歷史議論",
            "scenario": "討論孫中山及革命團體在多次起義受挫後持續組織、宣傳與尋求支持的精神，並分析個人、群體和時勢在辛亥革命中的作用。",
            "requirements": ["先區分傳統十次起義敘事、武昌起義與辛亥革命的關係", "不得寫成孫中山親自領導第十次革命並立即成功", "分析理想、組織、國際環境與群眾動員", "討論堅持是否也需要修正方法", "至少提出一項對英雄中心史觀的反思", "史實不確定處不得杜撰細節或假造引言"],
            "language_requirements": ["使用現代台灣歷史教育常見繁體中文", "區分史實敘述與價值評論", "約一千二百字"],
            "avoid": ["避免神化單一人物", "避免未查證的次數與日期", "不得假造名言", "不得混用簡體字"],
            "evaluation": ["史實框架是否清楚", "是否呈現多重因素", "精神論述是否有歷史依據"],
        },
        {
            "id": "tw-writing-0004",
            "era": "2020-2026",
            "genre": "日常生活、社群與對話",
            "title": "期待的重量：現代父母與子女之間",
            "target_chars": TARGET_CHARS,
            "accepted_char_range": [1050, 1350],
            "region": "全台",
            "perspective": "親子雙視角",
            "scenario": "以升學、職涯或生活選擇的一次家庭談話為核心，呈現父母把擔心說成要求、子女把自主說成拒絕的溝通落差。",
            "requirements": ["父母與子女都要有合理動機", "安排一次失敗的對話與一次重新表達", "具體寫出期待如何進入成績、科系、工作或婚姻選擇", "討論經濟安全感與個人興趣", "避免把任何一方寫成單純反派", "結尾提出界線與支持可以同時存在的做法"],
            "language_requirements": ["使用現代台灣家庭自然對話", "避免說教式旁白", "約一千二百字"],
            "avoid": ["不得使用刻板的虎爸虎媽標籤", "不得把服從等同孝順", "不得以一句道歉解決所有衝突", "不得混用簡體字"],
            "evaluation": ["雙方是否立體", "衝突是否貼近生活", "轉折是否可信"],
        },
    ]


def stable_index(key, size):
    digest = hashlib.sha256(key.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") % size


def compatible_topic(key, era, genre):
    if genre["genre"] == "科技、軟體與輸入法" and era["era"] in HISTORICAL_TECH_TOPICS:
        topics = HISTORICAL_TECH_TOPICS[era["era"]]
        return topics[stable_index(key + ":historical-tech", len(topics))]

    topics = genre["topics"]
    start = stable_index(key + ":topic", len(topics))
    banned_terms = ERA_BANNED_TOPIC_TERMS.get(era["era"], [])
    for offset in range(len(topics)):
        topic = topics[(start + offset) % len(topics)]
        joined = "".join(topic)
        if not any(term in joined for term in banned_terms):
            return topic
    raise ValueError(f"no era-compatible topic for {era['era']} / {genre['genre']}")


def build_prompt(sequence, era, genre, seen_titles):
    key = f"{SEED}:{sequence}:{era['era']}:{genre['genre']}"
    topic = compatible_topic(key, era, genre)
    keyword, object_name, conflict = topic
    setting_candidates = GENRE_SETTINGS.get(genre["genre"], era["settings"])
    setting = setting_candidates[stable_index(key + ":setting", len(setting_candidates))]
    artifact = era["artifacts"][stable_index(key + ":artifact", len(era["artifacts"]))]
    perspective = PERSPECTIVES[stable_index(key + ":perspective", len(PERSPECTIVES))]
    structure = STRUCTURES[stable_index(key + ":structure", len(STRUCTURES))]
    region = REGIONS[stable_index(key + ":region", len(REGIONS))]
    angle_source = HISTORICAL_TECH_ANGLES if genre["genre"] == "科技、軟體與輸入法" and era["era"] in HISTORICAL_TECH_TOPICS else genre["angles"]
    angles = [angle_source[(stable_index(key + ":angle", len(angle_source)) + i) % len(angle_source)] for i in range(3)]

    for offset in range(len(TITLE_PATTERNS)):
        pattern = TITLE_PATTERNS[(stable_index(key + ":title", len(TITLE_PATTERNS)) + offset) % len(TITLE_PATTERNS)]
        base = pattern.format(object=object_name, keyword=keyword, setting=setting, conflict=conflict)
        candidate = f"{base}：從{setting}談{angles[0]}"
        if candidate not in seen_titles:
            title = candidate
            break
    else:
        title = f"{keyword}與{conflict}：{era['era']}年的{region}{setting}觀察"
        if title in seen_titles:
            title = f"{title}（{sequence:04d}）"
    seen_titles.add(title)

    requirements = [
        f"以{era['era']}年的{region}{setting}為主要場景，讓年代環境直接影響人物選擇。",
        f"圍繞「{conflict}」形成主要問題，不可只作背景介紹。",
        f"從{angles[0]}、{angles[1]}、{angles[2]}三個面向推進內容。",
        f"採用{perspective}，全文視角必須一致且可辨認。",
        f"依照「{structure}」安排起承轉合。",
        f"讓{object_name}至少出現兩次，後一次出現必須帶來新的理解；{artifact}只作年代環境細節，不必承擔主題象徵。",
        genre["aim"],
        era["guard"],
        "至少包含三個具體場景或例證，抽象評論後要回到人物、物件或事件。",
        "結尾回應開頭提出的問題，但不得使用制式勵志口號。",
    ]
    if genre["genre"] in {"新聞與公共議題", "教育與知識"} or era["era"] <= "1990-1996":
        requirements.append("涉及史實、制度、數字或公共事件時，須區分可確認事實、合理推論與人物感受；不得捏造資料或引言。")

    return {
        "id": f"tw-writing-{sequence:04d}",
        "era": era["era"],
        "genre": genre["genre"],
        "title": title,
        "target_chars": TARGET_CHARS,
        "accepted_char_range": [1050, 1350],
        "region": region,
        "perspective": perspective,
        "scenario": f"以{era['era']}年的{region}{setting}為背景，圍繞{conflict}展開，讓{object_name}成為主要線索，並以{artifact}補充年代環境。",
        "requirements": requirements,
        "language_requirements": [era["language"], "使用台灣繁體中文與全形中文標點。", "對話、敘事與議論比例必須符合題型，不堆疊成語。", "目標約一千二百字，可接受一千零五十至一千三百五十字。"],
        "avoid": ["不得出現真實私人個資", "不得假造新聞來源、研究數字或名人引言", "不得混用簡體字或中國大陸慣用行政詞彙", "不得複製既有文章、歌詞或名作句子", "避免每段使用相同句型與制式人工智慧結語"],
        "evaluation": ["年代與物件是否一致", "情境與衝突是否具體", "三個指定面向是否都有實質內容", "文章是否形成完整推進", "語言是否自然且符合台灣使用習慣"],
    }


def main():
    anchors = anchor_prompts()
    era_remaining = {item["era"]: item["count"] for item in ERA_CONFIG}
    genre_remaining = {item["genre"]: item["count"] for item in GENRE_CONFIG}
    for prompt in anchors:
        era_remaining[prompt["era"]] -= 1
        genre_remaining[prompt["genre"]] -= 1

    eras_by_name = {item["era"]: item for item in ERA_CONFIG}
    genres_by_name = {item["genre"]: item for item in GENRE_CONFIG}
    era_pool = [eras_by_name[name] for name, count in era_remaining.items() for _ in range(count)]
    genre_pool = [genres_by_name[name] for name, count in genre_remaining.items() for _ in range(count)]
    random.Random(SEED).shuffle(era_pool)
    random.Random(SEED + 1).shuffle(genre_pool)

    prompts = list(anchors)
    seen_titles = {item["title"] for item in anchors}
    for sequence, (era, genre) in enumerate(zip(era_pool, genre_pool), start=len(anchors) + 1):
        prompts.append(build_prompt(sequence, era, genre, seen_titles))

    if len(prompts) != 3000:
        raise ValueError(f"expected 3000 prompts, got {len(prompts)}")
    if len({item["id"] for item in prompts}) != 3000:
        raise ValueError("duplicate prompt ids")
    if len({item["title"] for item in prompts}) != 3000:
        raise ValueError("duplicate prompt titles")
    expected_keys = set(prompts[0])
    for prompt in prompts:
        if set(prompt) != expected_keys:
            raise ValueError(f"inconsistent schema for {prompt['id']}")
        searchable = prompt["title"] + prompt["scenario"]
        for banned_term in ERA_BANNED_TOPIC_TERMS.get(prompt["era"], []):
            if banned_term in searchable:
                raise ValueError(f"anachronistic term {banned_term} in {prompt['id']}")

    era_counts = Counter(item["era"] for item in prompts)
    genre_counts = Counter(item["genre"] for item in prompts)
    expected_eras = {item["era"]: item["count"] for item in ERA_CONFIG}
    expected_genres = {item["genre"]: item["count"] for item in GENRE_CONFIG}
    if era_counts != expected_eras:
        raise ValueError(f"era distribution mismatch: {era_counts}")
    if genre_counts != expected_genres:
        raise ValueError(f"genre distribution mismatch: {genre_counts}")
    recent_count = sum(count for era, count in era_counts.items() if era >= "1997-2009")
    if recent_count != 1500:
        raise ValueError(f"expected 1500 prompts from the last 30 years, got {recent_count}")

    with OUTPUT.open("w", encoding="utf-8") as stream:
        for prompt in prompts:
            stream.write(json.dumps(prompt, ensure_ascii=False, separators=(",", ":")) + "\n")

    preview_indexes = list(range(4))
    for era in ERA_CONFIG:
        preview_indexes.append(next(i for i, item in enumerate(prompts) if item["era"] == era["era"] and i >= 4))
    for genre in GENRE_CONFIG:
        preview_indexes.append(next(i for i, item in enumerate(prompts) if item["genre"] == genre["genre"] and i >= 4))
    preview_indexes = list(dict.fromkeys(preview_indexes))
    lines = ["# Writing prompt preview", "", "The complete dataset is `writing-prompts-v1.jsonl`.", ""]
    for index in preview_indexes:
        item = prompts[index]
        lines.extend([
            f"## {item['id']}｜{item['title']}",
            "",
            f"- 年代：{item['era']}",
            f"- 類型：{item['genre']}",
            f"- 視角：{item['perspective']}",
            f"- 情境：{item['scenario']}",
            "- 必寫要求：",
            *[f"  - {requirement}" for requirement in item["requirements"]],
            "",
        ])
    PREVIEW.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    print(f"wrote {len(prompts)} prompts to {OUTPUT}")
    print(f"last-30-years prompts: {recent_count} (50%)")
    print("era counts:", dict(era_counts))
    print("genre counts:", dict(genre_counts))


if __name__ == "__main__":
    main()
