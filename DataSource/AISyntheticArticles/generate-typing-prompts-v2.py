#!/usr/bin/env python3
"""Build 10,000 Traditional Chinese assignments around real typing situations."""

from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path
import random


SEED = 20260924
TARGET_CHARS = 1200
ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "typing-prompts-v2.jsonl"
PREVIEW = ROOT / "typing-prompts-v2-preview.md"
STATS = ROOT / "typing-prompts-v2-stats.json"


ERA_CONFIG = [
    {
        "era": "1926-1945",
        "count": 500,
        "recent": False,
        "channels": [("私人書信", "書信往返"), ("日記", "日記片段"), ("報刊投書", "投書與回應"), ("會議紀錄", "紀錄與發言摘要"), ("公文草稿", "正式文件"), ("留言簿", "短句集合")],
        "guard": "內容須符合二十世紀上半葉台灣可行的書寫、交通與商品條件，不得出現現代網路、智慧型手機或即時通訊。",
    },
    {
        "era": "1946-1969",
        "count": 800,
        "recent": False,
        "channels": [("私人書信", "書信往返"), ("家庭留言", "便條與回覆"), ("公司備忘錄", "工作文件組"), ("報刊投書", "投書與回應"), ("會議紀錄", "紀錄與發言摘要"), ("申請書", "申請與回覆")],
        "guard": "使用戰後早期台灣可能出現的溝通工具與詞彙，不得套入後來的網路平台、行動應用程式或現代產品。",
    },
    {
        "era": "1970-1989",
        "count": 1100,
        "recent": False,
        "channels": [("私人書信", "書信往返"), ("電話留言", "留言與後續回覆"), ("公司備忘錄", "工作文件組"), ("聯絡簿", "短文與回覆"), ("讀者投書", "投書與回應"), ("旅行札記", "見聞與實用資訊")],
        "guard": "科技、消費、旅遊與工作內容須符合一九七〇至八〇年代台灣環境，不得提前使用電子郵件、社群網站或智慧型手機。",
    },
    {
        "era": "1990-1996",
        "count": 600,
        "recent": False,
        "channels": [("電子布告欄", "討論串"), ("傳真往返", "文件往返"), ("電子郵件", "郵件串"), ("呼叫器留言", "短句與電話回覆"), ("公司文件", "工作文件組"), ("旅遊筆記", "行程與心得")],
        "guard": "呈現九〇年代前半從紙本走向數位的過渡，不得使用尚未普及的智慧型手機、社群應用程式或行動支付。",
    },
    {
        "era": "1997-2009",
        "count": 1800,
        "recent": True,
        "channels": [("手機簡訊", "短訊息串"), ("即時通訊", "一對一對話"), ("電子布告欄", "討論串"), ("電子郵件", "郵件串"), ("部落格留言", "文章與留言"), ("工作文件", "工作文件組")],
        "guard": "區分撥接、寬頻、按鍵手機、簡訊、即時通訊與早期智慧型手機的時序，不得把今日平台功能直接搬入。",
    },
    {
        "era": "2010-2019",
        "count": 2200,
        "recent": True,
        "channels": [("通訊軟體私訊", "一對一對話"), ("通訊軟體群組", "多人對話"), ("電子郵件", "郵件串"), ("社群貼文", "貼文與留言"), ("客服文字對談", "客服紀錄"), ("共享文件", "文件與批註")],
        "guard": "使用二〇一〇年代台灣自然用語，避免把生成式人工智慧或尚未普及的服務提前寫成日常。",
    },
    {
        "era": "2020-2026",
        "count": 3000,
        "recent": True,
        "channels": [("通訊軟體私訊", "一對一對話"), ("通訊軟體群組", "多人對話"), ("工作聊天軟體", "工作討論串"), ("社群留言", "貼文與留言"), ("客服文字對談", "客服紀錄"), ("電子郵件", "郵件串"), ("搜尋與人工智慧提示", "查詢與追問集合"), ("共享文件", "文件與批註")],
        "guard": "使用二〇二〇年代台灣自然繁體中文；涉及現行政策、產品規格、票價、營業時間或法律時，不得捏造可變動資訊。",
    },
]


COMMON_RELATIONSHIPS = ["家人", "朋友", "伴侶", "同學", "鄰居", "同事", "主管與部屬", "店家與顧客", "居民與承辦人", "陌生網友"]
TONES = ["自然直接", "客氣克制", "急迫但清楚", "帶著不滿", "溫和安慰", "輕鬆幽默", "正式謹慎", "猶豫試探", "簡短俐落", "耐心說明"]
REGIONS = ["北部都會", "北部郊區", "中部城市", "中部農村", "南部城市", "南部鄉鎮", "東部地區", "離島", "跨縣市", "線上跨地區"]

ERA_ORDER = {item["era"]: index for index, item in enumerate(ERA_CONFIG)}

CHANNEL_KIND = {
    "私人書信": "personal", "日記": "personal", "家庭留言": "personal", "電話留言": "personal",
    "呼叫器留言": "personal", "手機簡訊": "personal", "即時通訊": "personal", "通訊軟體私訊": "personal",
    "通訊軟體群組": "group", "工作聊天軟體": "work", "電子郵件": "mail", "共享文件": "work",
    "公司備忘錄": "work", "公司文件": "work", "工作文件": "work", "會議紀錄": "work",
    "聯絡簿": "education", "報刊投書": "public", "讀者投書": "public", "電子布告欄": "public",
    "部落格留言": "public", "社群貼文": "public", "社群留言": "public", "留言簿": "public",
    "客服文字對談": "service", "申請書": "formal", "公文草稿": "formal", "傳真往返": "formal",
    "旅行札記": "travel", "旅遊筆記": "travel", "搜尋與人工智慧提示": "search",
}

CATEGORY_CHANNEL_KINDS = {
    "日常溝通與協調": {"personal", "group", "mail", "public"},
    "工作討論與公事": {"work", "mail", "formal"},
    "情緒與人際關係": {"personal", "group", "mail", "public"},
    "消費服務與交易": {"service", "mail", "public", "formal", "personal"},
    "法律紛爭與政府政策": {"formal", "mail", "public", "work"},
    "學習請教與知識問答": {"education", "personal", "group", "mail", "public", "search"},
    "社群吐槽與講幹話": {"personal", "group", "public"},
    "住宿旅遊與交通": {"travel", "personal", "group", "mail", "public", "service", "search"},
    "餐飲與休閒娛樂": {"travel", "personal", "group", "public", "service", "search"},
    "商品品牌與科技": {"service", "mail", "public", "personal", "search"},
    "台灣地標與地方生活": {"travel", "personal", "group", "public", "search"},
    "日本繁中景點與旅行": {"travel", "personal", "group", "mail", "public", "search"},
    "美國繁中地名與旅行": {"travel", "personal", "group", "mail", "public", "search"},
    "中國繁中地名與旅行": {"travel", "personal", "group", "mail", "public", "search"},
    "歐洲繁中地名與旅行": {"travel", "personal", "group", "mail", "public", "search"},
    "其他國家繁中地名與旅行": {"travel", "personal", "group", "mail", "public", "search"},
}

RELATIONSHIPS_BY_CATEGORY = {
    "日常溝通與協調": ["家人", "朋友", "伴侶", "同學", "鄰居", "同事"],
    "工作討論與公事": ["同事", "主管與部屬", "跨部門同仁", "公司與客戶", "店家與供應商"],
    "情緒與人際關係": ["家人", "朋友", "伴侶", "同學", "鄰居", "久未聯絡的朋友"],
    "消費服務與交易": ["店家與顧客", "客服與消費者", "買家與賣家", "旅客與業者"],
    "法律紛爭與政府政策": ["房東與房客", "勞工與雇主", "事故當事人", "鄰居", "居民與承辦人", "管委會與住戶"],
    "學習請教與知識問答": ["同學", "師生", "家長與教師", "讀者與作者", "學習者與指導者"],
    "社群吐槽與講幹話": ["朋友", "同學", "同事", "家人", "遊戲隊友", "陌生網友"],
    "住宿旅遊與交通": ["同行家人", "朋友", "旅客與業者", "旅客與站務人員", "同事"],
    "餐飲與休閒娛樂": ["朋友", "家人", "同事", "店家與顧客", "活動參加者"],
    "商品品牌與科技": ["店家與顧客", "客服與使用者", "朋友", "家人", "買家與賣家"],
    "台灣地標與地方生活": ["同行家人", "朋友", "旅客與在地居民", "同學", "同事"],
    "日本繁中景點與旅行": ["同行家人", "朋友", "旅客與住宿業者", "同學", "同事"],
    "美國繁中地名與旅行": ["同行家人", "朋友", "旅客與住宿業者", "同學", "同事"],
    "中國繁中地名與旅行": ["同行家人", "朋友", "旅客與住宿業者", "同學", "同事"],
    "歐洲繁中地名與旅行": ["同行家人", "朋友", "旅客與住宿業者", "同學", "同事"],
    "其他國家繁中地名與旅行": ["同行家人", "朋友", "旅客與住宿業者", "同學", "同事"],
}

MIN_ERA_BY_SITUATION = {
    "網購延遲到貨": "1997-2009", "訂單重複扣款": "1997-2009", "會員方案取消": "1997-2009",
    "餐點漏送": "1997-2009",
    "家庭群組誤傳訊息": "2010-2019", "遊戲隊伍聊天": "1997-2009", "看球賽即時反應": "1997-2009",
    "外送餐點異常": "2010-2019", "演唱會搶票": "1997-2009", "桌遊或電玩聚會": "1970-1989",
    "軟體更新改變操作": "1990-1996", "帳號與資料移轉": "1997-2009", "開箱後發現問題": "1997-2009",
    "學生使用人工智慧工具": "2020-2026", "查證網路說法": "1997-2009", "無障礙路線": "1990-1996",
}

ERA_BANNED_CONTENT_TERMS = {
    "1926-1945": ["截圖", "貼圖", "群組", "網路", "軟體", "人工智慧", "信用卡", "電子票券", "遊戲房間", "迷因", "帳號", "外送", "客服", "會員", "開箱", "即時規格", "折價券", "包棟"],
    "1946-1969": ["截圖", "貼圖", "群組", "網路", "軟體", "人工智慧", "信用卡", "電子票券", "遊戲房間", "迷因", "帳號", "外送", "客服", "會員", "開箱", "即時規格", "包棟"],
    "1970-1989": ["截圖", "貼圖", "群組", "網購", "人工智慧", "電子票券", "遊戲房間", "迷因", "帳號移轉", "外送訂單", "開箱影片", "生成內容"],
    "1990-1996": ["人工智慧", "生成內容", "通訊軟體", "社群貼文", "行動支付"],
    "1997-2009": ["人工智慧工具", "生成內容"],
    "2010-2019": ["生成內容"],
    "2020-2026": [],
}

ERA_BANNED_RELATIONSHIP_TERMS = {
    "1926-1945": ["客服", "使用者", "網友", "遊戲隊友"],
    "1946-1969": ["客服", "使用者", "網友", "遊戲隊友"],
    "1970-1989": ["網友", "遊戲隊友"],
    "1990-1996": [], "1997-2009": [], "2010-2019": [], "2020-2026": [],
}


TAIWAN_ENTITIES = [
    "台北一〇一", "西門町", "國立故宮博物院", "中正紀念堂", "大稻埕", "淡水老街", "九份老街", "野柳地質公園",
    "桃園國際機場", "新竹城隍廟", "日月潭", "國立臺灣美術館", "臺中國家歌劇院", "鹿港老街", "阿里山", "故宮南院",
    "赤崁樓", "安平古堡", "奇美博物館", "駁二藝術特區", "旗津", "佛光山", "墾丁國家公園", "太魯閣國家公園",
    "三仙台", "伯朗大道", "澎湖跨海大橋", "金門莒光樓", "馬祖北海坑道", "基隆廟口", "逢甲夜市", "花園夜市",
    "臺北車站", "板橋車站", "臺中車站", "高雄車站", "左營高鐵站", "松山機場", "高雄國際機場", "臺灣高鐵",
]

TAIWAN_ENTITIES_BY_ERA = {
    "1926-1945": ["大稻埕", "西門町", "淡水", "九份", "阿里山", "日月潭", "鹿港", "安平", "旗津", "基隆港", "臺北驛", "臺中驛"],
    "1946-1969": ["大稻埕", "西門町", "淡水", "九份", "阿里山", "日月潭", "鹿港", "安平", "旗津", "太魯閣", "臺北車站", "高雄車站"],
    "1970-1989": ["國立故宮博物院", "中正紀念堂", "西門町", "淡水", "九份", "阿里山", "日月潭", "鹿港", "安平古堡", "旗津", "墾丁國家公園", "太魯閣", "臺北車站", "高雄車站"],
    "1990-1996": ["國立故宮博物院", "中正紀念堂", "西門町", "淡水老街", "九份", "阿里山", "日月潭", "鹿港老街", "安平古堡", "旗津", "墾丁國家公園", "太魯閣國家公園", "臺北車站", "臺中車站", "高雄車站"],
    "1997-2009": [x for x in TAIWAN_ENTITIES if x not in {"臺中國家歌劇院", "故宮南院"}],
    "2010-2019": TAIWAN_ENTITIES,
    "2020-2026": TAIWAN_ENTITIES,
}


JAPAN_ENTITIES = [
    "淺草寺", "東京晴空塔", "明治神宮", "澀谷十字路口", "上野公園", "新宿御苑", "東京車站", "東京迪士尼樂園",
    "清水寺", "伏見稻荷大社", "嵐山", "金閣寺", "京都車站", "心齋橋", "道頓堀", "大阪城",
    "奈良公園", "東大寺", "神戶港", "姬路城", "小樽運河", "函館山", "富良野", "美瑛青池",
    "札幌時計台", "太宰府天滿宮", "由布院", "熊本城", "長崎和平公園", "別府地獄", "沖繩美麗海水族館", "首里城",
    "廣島和平紀念公園", "嚴島神社", "名古屋城", "兼六園", "白川鄉", "立山黑部", "松本城", "富士山",
]

JAPAN_ENTITIES_BY_ERA = {
    "1970-1989": ["淺草寺", "明治神宮", "上野公園", "新宿御苑", "東京車站", "清水寺", "伏見稻荷大社", "嵐山", "金閣寺", "京都車站", "心齋橋", "道頓堀", "大阪城", "奈良公園", "東大寺", "神戶港", "姬路城", "小樽運河", "函館山", "富士山"],
    "1990-1996": ["淺草寺", "明治神宮", "上野公園", "新宿御苑", "東京車站", "東京迪士尼樂園", "清水寺", "伏見稻荷大社", "嵐山", "金閣寺", "京都車站", "心齋橋", "道頓堀", "大阪城", "奈良公園", "東大寺", "神戶港", "姬路城", "小樽運河", "函館山", "富良野", "札幌時計台", "太宰府天滿宮", "由布院", "熊本城", "長崎和平公園", "別府地獄", "廣島和平紀念公園", "嚴島神社", "名古屋城", "兼六園", "白川鄉", "立山黑部", "松本城", "富士山"],
    "1997-2009": [x for x in JAPAN_ENTITIES if x != "東京晴空塔"],
    "2010-2019": JAPAN_ENTITIES,
    "2020-2026": JAPAN_ENTITIES,
}

USA_ENTITIES = [
    "自由女神像", "時代廣場", "中央公園", "帝國大廈", "大都會藝術博物館", "布魯克林大橋", "白宮", "林肯紀念堂",
    "華盛頓紀念碑", "美國國會大廈", "國家廣場", "黃石國家公園", "大峽谷國家公園", "優勝美地國家公園", "金門大橋", "漁人碼頭",
    "九曲花街", "好萊塢星光大道", "聖塔莫尼卡碼頭", "拉斯維加斯大道", "胡佛水壩", "大煙山國家公園", "鑽石頭山", "珍珠港",
]

CHINA_ENTITIES = [
    "北京故宮", "天安門廣場", "萬里長城", "頤和園", "天壇", "上海外灘", "豫園", "西湖",
    "秦始皇兵馬俑", "華清宮", "張家界國家森林公園", "九寨溝", "桂林山水", "麗江古城", "布達拉宮", "黃山",
    "泰山", "蘇州園林", "南京中山陵", "成都寬窄巷子", "都江堰", "樂山大佛", "莫高窟", "平遙古城",
    "鼓浪嶼", "福建土樓", "龍門石窟", "承德避暑山莊", "青海湖", "長白山",
]

EUROPE_ENTITIES = [
    "艾菲爾鐵塔", "羅浮宮", "巴黎凱旋門", "巴黎聖母院", "凡爾賽宮", "倫敦塔橋", "大笨鐘", "白金漢宮",
    "大英博物館", "羅馬競技場", "梵蒂岡博物館", "聖彼得大教堂", "比薩斜塔", "聖馬可廣場", "米蘭大教堂", "聖家堂",
    "阿爾罕布拉宮", "馬德里王宮", "布蘭登堡門", "新天鵝堡", "科隆大教堂", "阿姆斯特丹國家博物館", "布拉格城堡", "美泉宮",
    "哈修塔特", "少女峰", "馬特洪峰", "雅典衛城", "聖托里尼", "多瑙河", "挪威峽灣", "雷克雅維克",
]

OTHER_COUNTRY_ENTITIES = [
    "尼加拉瀑布", "班夫國家公園", "露易絲湖", "雪梨歌劇院", "雪梨港灣大橋", "大堡礁", "烏魯魯", "米佛峽灣",
    "皇后鎮", "霍比屯", "蒂卡波湖", "景福宮", "南山首爾塔", "海雲臺", "濟州島", "甘川文化村",
    "曼谷大皇宮", "鄭王廟", "清邁古城", "濱海灣金沙", "魚尾獅公園", "濱海灣花園", "吉隆坡雙峰塔", "馬六甲古城",
    "下龍灣", "會安古城", "吳哥窟", "婆羅浮屠", "泰姬瑪哈陵", "佩特拉古城", "吉薩金字塔", "桌山",
    "塞倫蓋提國家公園", "維多利亞瀑布", "馬丘比丘", "基督救世主像", "伊瓜蘇瀑布", "復活節島", "加拉巴哥群島", "巴塔哥尼亞",
]

INTERNATIONAL_TRAVEL_SITUATIONS = ["確認景點繁體中文名稱", "安排城市行程", "詢問交通轉乘", "比較住宿區域", "尋找附近餐飲", "購買交通票券", "規劃季節旅行", "同行者走散", "行李寄放", "分享旅後心得", "閱讀旅行文章", "替家人整理景點清單"]
INTERNATIONAL_TRAVEL_OBJECTS = ["繁體中文景點名", "當地原名", "車站名稱", "轉乘路線", "訂房確認信", "交通票券", "行程表", "地圖", "行李寄放單", "旅行照片", "遊記", "伴手禮清單"]
INTERNATIONAL_TRAVEL_COMPLICATIONS = ["中文譯名有不只一種寫法", "景點與交通站名容易混淆", "同一天安排太多地點", "交通方式說明不一致", "同行者偏好不同", "季節會影響行程", "不能確認即時票價或開放狀態", "地圖顯示的出口不同", "行李增加移動困難", "需要使用台灣常見繁體名稱", "文章使用不同地名譯法", "清單裡混入相近名稱"]
INTERNATIONAL_TRAVEL_SPEECH_ACTS = ["確認名稱", "規劃行程", "詢問轉乘", "比較住宿地點", "搜尋餐飲", "確認票券", "規劃季節行程", "聯絡會合", "詢問寄放", "分享心得", "核對名稱", "整理清單"]


PRODUCTS_BY_ERA = {
    "1926-1945": ["礦石收音機", "腳踏車", "打字機", "鋼筆", "縫紉機", "唱片", "懷錶", "油紙傘"],
    "1946-1969": ["電晶體收音機", "黑白電視", "轉盤電話", "電風扇", "縫紉機", "底片相機", "腳踏車", "唱片機"],
    "1970-1989": ["卡帶錄音機", "彩色電視", "隨身聽", "電子計算機", "錄影機", "摩托車", "電冰箱", "三用電表"],
    "1990-1996": ["家庭電腦", "呼叫器", "傳真機", "磁碟片", "錄影帶", "隨身聽", "早期行動電話", "中文文書軟體"],
    "1997-2009": ["按鍵手機", "數位相機", "MP3 播放器", "筆記型電腦", "遊戲主機", "液晶螢幕", "隨身碟", "無線基地台"],
    "2010-2019": ["iPhone", "iPad", "AirPods", "MacBook", "Nintendo Switch", "PlayStation 4", "GoPro", "掃地機器人", "智慧手環", "行動電源"],
    "2020-2026": ["iPhone", "iPad", "AirPods", "MacBook", "Apple Watch", "Galaxy 手機", "Pixel 手機", "Nintendo Switch", "PlayStation 5", "Kindle", "GoPro", "Garmin 手錶", "Dyson 吸塵器", "Roomba 掃地機器人", "Gogoro 電動機車"],
}


CATEGORY_CONFIG = [
    {
        "category": "日常溝通與協調", "count": 1400,
        "situations": ["約定見面時間", "臨時更改行程", "家人報平安", "請人代收物品", "借用東西", "分配家務", "接送安排", "鄰居協調", "朋友聚會", "遺失物協尋", "群組公告", "確認對方是否方便"],
        "objects": ["集合時間", "備用鑰匙", "雨傘", "包裹", "採買清單", "交通路線", "門禁", "家務表", "聯絡電話", "失物照片", "訂位資料", "行事曆"],
        "complications": ["對方一直沒有回覆", "臨時有人不能出席", "兩邊記得的時間不同", "訊息被誤解", "地址寫得不清楚", "天氣打亂安排", "有人忘了先通知", "群組裡同時出現太多意見", "語氣看起來比原意強硬", "需要拒絕又不想傷感情"],
        "speech_acts": ["確認時間", "協調改期", "報平安", "請託", "詢問借用", "分配家務", "提醒", "協調", "邀約", "協尋", "通知", "詢問是否方便"],
        "aim": "收錄日常真正會打出的詢問、確認、改期、提醒與回覆，不要把每句都寫成完整作文句。",
    },
    {
        "category": "工作討論與公事", "count": 1200,
        "situations": ["專案進度落後", "軟體錯誤排查", "會議改期", "工作交接", "請假與排班", "採購詢價", "客戶追加需求", "事故回報", "優先順序衝突", "新人訓練", "遠端協作", "帳款核對"],
        "objects": ["進度表", "錯誤紀錄", "會議邀請", "交接文件", "班表", "報價單", "需求單", "事故紀錄", "待辦清單", "操作手冊", "共享文件", "發票"],
        "complications": ["期限已經接近", "不同部門說法不一致", "關鍵資料尚未補齊", "負責人暫時聯絡不上", "修改會影響其他工作", "預算不足", "客戶誤解原本範圍", "問題暫時無法重現", "有人只在口頭交代", "需要留下正式紀錄"],
        "speech_acts": ["回報進度", "排查問題", "協調時間", "交接", "提出請假", "詢價", "澄清範圍", "事故回報", "協商優先順序", "教學與追問", "同步資訊", "核對帳款"],
        "aim": "呈現台灣職場常見的即時訊息、郵件與文件語氣，包含簡短討論和可追蹤的正式結論。",
    },
    {
        "category": "情緒與人際關係", "count": 900,
        "situations": ["朋友發生誤會", "伴侶為時間安排爭執", "家人對選擇不認同", "考試失利需要安慰", "求職受挫需要鼓勵", "工作出錯感到自責", "生病期間需要陪伴", "關係中提出界線", "道歉沒有被接受", "分手後歸還物品", "久未聯絡重新開口", "面對親友離世"],
        "objects": ["未讀訊息", "共同照片", "成績單", "面試通知", "工作紀錄", "藥袋", "行事曆", "借放的物品", "道歉訊息", "舊對話", "車票", "紀念物"],
        "complications": ["雙方都覺得自己沒有被聽見", "一句話被截圖轉傳", "安慰聽起來像說教", "對方現在不想回覆", "舊問題再次被提起", "有人用反話掩飾難過", "關心變成過度追問", "需要說不但怕失去關係", "道歉沒有說明如何改變", "事情沒有立即解法"],
        "speech_acts": ["澄清誤會", "爭辯", "解釋選擇", "安慰", "鼓勵", "安慰與檢討", "陪伴", "設下界線", "再次道歉", "結束關係", "重新邀請對話", "陪伴與傾聽"],
        "aim": "讓情緒出現在具體措辭、停頓、改口與回覆速度中；不可要求每次衝突都和解。",
    },
    {
        "category": "消費服務與交易", "count": 800,
        "situations": ["網購延遲到貨", "退貨退款", "餐點漏送", "預約被取消", "維修後問題仍在", "價格標示不同", "保固範圍爭議", "物流地址錯誤", "訂單重複扣款", "保險理賠詢問", "二手交易驗貨", "會員方案取消"],
        "objects": ["訂單編號", "付款紀錄", "商品照片", "取貨通知", "維修單", "價目表", "保固卡", "配送紀錄", "信用卡帳單", "理賠文件", "面交地點", "續約通知"],
        "topic_relationships": ["店家與顧客", "店家與顧客", "餐飲業者與顧客", "預約者與業者", "維修業者與顧客", "店家與顧客", "廠商與顧客", "物流業者與收件人", "付款人與交易平台", "保險業者與保戶", "買家與賣家", "會員與服務業者"],
        "complications": ["已經超過預定日期", "商品已拆封", "店家只願意補送而不願退款", "問題需要第三方確認", "維修後問題仍然存在", "雙方保存的價格紀錄不同", "證明文件不完整", "地址欄位有一處錯誤", "付款成功但系統沒有訂單", "需要補充就醫或事故文件", "照片無法顯示全部瑕疵", "取消後仍收到續約通知"],
        "speech_acts": ["催單", "要求退款", "要求補送", "申訴", "報修", "核對價格", "確認保固", "更正地址", "要求退回款項", "補充理賠資料", "議價與驗貨", "取消續約"],
        "aim": "包含顧客實際會輸入的問題、店家回覆與後續協商，避免所有客服都使用同一套官樣句型。",
    },
    {
        "category": "法律紛爭與政府政策", "count": 700,
        "situations": ["租屋押金爭議", "加班費與排班爭議", "交通事故責任", "鄰居噪音", "契約內容不一致", "遺產分配討論", "著作權使用", "個人資料外洩", "網路交易糾紛", "社區規約爭議", "交通政策討論", "住宅與能源政策意見"],
        "objects": ["租賃契約", "出勤紀錄", "事故照片", "管委會紀錄", "報價與合約", "財產清冊", "授權文件", "通知信", "交易紀錄", "會議議程", "政策草案", "陳情書"],
        "topic_relationships": ["房東與房客", "勞工與雇主", "事故當事人", "鄰居", "契約雙方", "家人", "創作者與使用者", "資料當事人與機構", "買家與賣家", "管委會與住戶", "居民與承辦人", "居民與承辦人"],
        "complications": ["雙方對事實經過描述不同", "證據散落在多段訊息裡", "情緒與權利主張混在一起", "有人引用未確認的規定", "需要把時間順序寫清楚", "涉及多位當事人", "口頭承諾沒有留下紀錄", "規則一致卻造成不同影響", "居民與主管機關關注點不同", "短期便利與長期成本衝突"],
        "speech_acts": ["要求返還押金", "提出出勤紀錄", "釐清事故經過", "協調噪音問題", "核對契約", "協商分配", "確認授權", "要求說明", "提出交易證據", "討論規約", "政策辯論", "提出政策意見"],
        "aim": "區分人物主張、可確認紀錄與尚待判定事項；呈現法律、公務與一般人用語之間的落差。",
    },
    {
        "category": "學習請教與知識問答", "count": 650,
        "situations": ["詢問作業要求", "討論分組報告", "向老師請教", "選課與轉系", "準備考試", "閱讀不同資料", "查證網路說法", "實驗失敗", "語言學習", "職業技能訓練", "家長詢問學習狀況", "學生使用人工智慧工具"],
        "objects": ["作業說明", "報告大綱", "課堂筆記", "選課單", "考卷", "參考資料", "新聞連結", "實驗紀錄", "單字表", "操作步驟", "聯絡簿", "生成內容"],
        "complications": ["問題問得太籠統", "組員理解不同", "找到的資料互相矛盾", "害怕問得太簡單", "只記住答案卻不懂原因", "引用來源不完整", "工具給出看似合理的錯誤", "時間不足", "設備條件不同", "需要把複雜概念說得易懂"],
        "speech_acts": ["詢問要求", "協調分工", "請教", "比較選項", "準備與追問", "比較資料", "查證", "檢討步驟", "練習與更正", "詢問操作", "回報學習狀況", "確認使用界線"],
        "aim": "收錄自然的問法、追問、重新解釋與承認不知道，不得捏造研究數據或來源。",
    },
    {
        "category": "社群吐槽與講幹話", "count": 650,
        "situations": ["朋友互相吐槽", "辦公室小插曲", "遊戲隊伍聊天", "家庭群組誤傳訊息", "看球賽即時反應", "減肥破功", "熬夜後自嘲", "排隊太久", "天氣突然改變", "寵物搗蛋", "錯字造成誤會", "假日結束前抱怨"],
        "objects": ["迷因圖片", "貼圖", "錯字截圖", "比賽畫面", "宵夜照片", "鬧鐘", "排隊號碼", "天氣預報", "寵物照片", "遊戲戰績", "未完成清單", "星期一行事曆"],
        "complications": ["有人把玩笑當真", "吐槽踩到對方在意的點", "群組突然安靜", "同一句話需要補充語氣", "大家接力把話題越講越遠", "自嘲裡其實帶著壓力", "有人認真回答了幹話", "反話被誤會成同意", "貼圖比文字更有力", "需要適時收住玩笑"],
        "speech_acts": ["吐槽", "自嘲", "接梗", "澄清誤傳", "即時吐槽", "自嘲", "抱怨", "抱怨排隊", "誇張抱怨", "分享趣事", "澄清玩笑", "假日收心吐槽"],
        "aim": "使用自然台灣口語、短句、反話和接話節奏；幽默不得只靠堆疊流行語，也不要把人物都寫成相同語氣。",
    },
    {
        "category": "住宿旅遊與交通", "count": 800,
        "situations": ["詢問空房與價格", "訂房後確認", "提前寄放行李", "延後辦理入住", "房間設備故障", "臨時取消行程", "規劃跨縣市交通", "詢問末班車", "多人旅行分工", "露營與包棟", "溫泉旅館禮節", "旅行後提出評論"],
        "objects": ["訂房確認信", "房型照片", "入住時間", "行李寄放單", "冷氣遙控器", "退款規則", "車票", "轉乘路線", "行程表", "營位資料", "住宿須知", "評論頁面"],
        "complications": ["預算與房型難以同時符合", "房型名稱容易誤解", "行李超過寄放時間", "店家尚未回覆", "需要維修又不方便換房", "取消規則說明不清", "交通延誤", "末班時間不容易確認", "同行者需求不同", "天候影響行程", "不同旅館的禮節不一樣", "照片與現場有落差"],
        "speech_acts": ["詢價", "確認訂房", "詢問寄放", "通知晚到", "要求維修", "取消與退款", "規劃路線", "確認末班時間", "分配行程", "確認住宿規則", "詢問禮節", "評論"],
        "aim": "涵蓋飯店、民宿、青年旅館、露營、交通轉乘與旅後評論，使用旅客和業者都會打出的句子。",
    },
    {
        "category": "餐飲與休閒娛樂", "count": 800,
        "situations": ["餐廳訂位", "飲料甜度冰量", "外送餐點異常", "詢問過敏原", "朋友約宵夜", "家庭聚餐", "電影選位", "演唱會搶票", "球賽討論", "展覽邀約", "登山與單車活動", "桌遊或電玩聚會"],
        "objects": ["菜單", "訂位資料", "外送訂單", "餐點標示", "集合訊息", "包廂", "電影票", "電子票券", "賽程", "展覽門票", "裝備清單", "遊戲房間代碼"],
        "complications": ["訂位人數改變", "每個人的口味不同", "餐點少送", "有人不能吃某項食物", "熱門時段沒有座位", "同行者喜好差異很大", "想要的座位已經售出", "票券規則看不懂", "支持的隊伍不同", "集合地點容易走錯", "活動因天氣調整", "參加者對規則理解不同"],
        "speech_acts": ["訂位", "點餐", "要求補送", "詢問成分", "邀約", "協調聚餐", "選位", "確認票券", "討論賽況", "邀約看展", "提醒安全", "確認規則"],
        "aim": "包含吃喝玩樂的搜尋、邀約、點餐、訂票、即時反應與心得，保留自然省略句和常見量詞。",
    },
    {
        "category": "商品品牌與科技", "count": 800,
        "situations": ["比較商品功能", "詢問配件相容性", "選擇尺寸或容量", "維修與保固", "二手商品交易", "開箱後發現問題", "購買前看評論", "軟體更新改變操作", "帳號與資料移轉", "送禮選擇", "家電安裝", "交通工具保養"],
        "objects": ["商品名稱", "型號標示", "配件清單", "保固文件", "二手照片", "開箱影片", "使用者評論", "更新說明", "備份紀錄", "購物清單", "安裝手冊", "維修紀錄"],
        "topic_relationships": ["店家與顧客", "客服與使用者", "店家與顧客", "維修業者與顧客", "買家與賣家", "店家與顧客", "消費者與店家", "客服與使用者", "客服與使用者", "家人", "安裝業者與顧客", "維修業者與顧客"],
        "complications": ["名稱相近但規格不同", "舊配件不一定相容", "官方名稱與俗稱不同", "網路評論互相矛盾", "價格在不同通路有差異", "商品已經停產", "更新後找不到原本功能", "個人資料不能完整移轉", "維修與換新成本接近", "不能確認某項即時規格"],
        "speech_acts": ["比較功能", "確認相容性", "詢問尺寸容量", "報修", "議價與驗貨", "反映瑕疵", "詢問評價", "詢問更新操作", "詢問資料移轉", "推薦與比較", "確認安裝", "詢問保養"],
        "aim": "正確使用指定商品名稱與台灣常見商品類別，著重名稱周邊常用動詞、配件、尺寸、容量、維修和比較語句。",
    },
    {
        "category": "台灣地標與地方生活", "count": 650,
        "situations": ["約定景點集合", "詢問大眾運輸", "安排一日行程", "尋找附近餐飲", "雨天備案", "親子或長輩同行", "無障礙路線", "拍照與觀景", "地方活動", "返鄉與探親", "商圈散步", "旅行後分享心得"],
        "objects": ["車站出口", "地圖連結", "景點名稱", "公車路線", "停車資訊", "門票", "集合照片", "行程表", "地方小吃", "伴手禮", "老街店面", "旅行評論"],
        "complications": ["同行者走錯出口", "交通方式說明不一致", "景點之間距離太遠", "附近店家資訊不完整", "天氣臨時改變", "長輩走路速度較慢", "無障礙資訊不足", "有人只想拍照有人想慢慢逛", "假日人潮影響安排", "返鄉交通時間比預期久", "正式名稱和俗稱不同", "不能確認即時營業資訊"],
        "speech_acts": ["確認集合點", "詢問交通", "規劃行程", "搜尋餐飲", "安排備案", "協調步調", "詢問無障礙路線", "分享拍照地點", "詢問活動", "安排返鄉", "推薦路線", "分享心得"],
        "aim": "自然使用指定台灣地標的正式名稱、常見簡稱及交通搭配詞，避免杜撰即時營業資訊。",
    },
    {
        "category": "日本繁中景點與旅行", "count": 200,
        "eligible_eras": ["1970-1989", "1990-1996", "1997-2009", "2010-2019", "2020-2026"],
        "situations": ["確認景點中文名稱", "安排城市行程", "詢問車站轉乘", "比較住宿區域", "尋找附近餐飲", "購買交通票券", "規劃賞花或雪季旅行", "同行者走散", "行李寄放", "分享旅後心得", "閱讀旅行文章", "替家人整理景點清單"],
        "objects": ["繁體中文景點名", "日文原名", "車站名稱", "轉乘路線", "訂房確認信", "交通票券", "行程表", "地圖", "行李寄放單", "旅行照片", "遊記", "伴手禮清單"],
        "complications": ["中文譯名有不只一種寫法", "景點與車站名稱容易混淆", "同一天安排太多地點", "交通方式說明不一致", "同行者對購物和參觀偏好不同", "季節會影響行程", "不能確認即時票價或開放狀態", "地圖顯示的出口不同", "行李增加移動困難", "需要使用台灣常見繁體名稱"],
        "speech_acts": ["確認名稱", "規劃行程", "詢問轉乘", "比較住宿地點", "搜尋餐飲", "確認票券", "規劃季節行程", "聯絡會合", "詢問寄放", "分享心得", "核對名稱", "整理清單"],
        "aim": "使用台灣常見的繁體中文景點名，必要時附日文原名或別稱；不得虛構票價、班次、營業時間與現場狀態。",
    },
    {
        "category": "美國繁中地名與旅行", "count": 100,
        "eligible_eras": ["1997-2009", "2010-2019", "2020-2026"],
        "situations": INTERNATIONAL_TRAVEL_SITUATIONS, "objects": INTERNATIONAL_TRAVEL_OBJECTS,
        "complications": INTERNATIONAL_TRAVEL_COMPLICATIONS, "speech_acts": INTERNATIONAL_TRAVEL_SPEECH_ACTS,
        "aim": "使用台灣常見的美國地名與景點繁體中文名稱，必要時附英文原名；不得虛構即時票價、班次、營業時間或入境規定。",
    },
    {
        "category": "中國繁中地名與旅行", "count": 100,
        "eligible_eras": ["1997-2009", "2010-2019", "2020-2026"],
        "situations": INTERNATIONAL_TRAVEL_SITUATIONS, "objects": INTERNATIONAL_TRAVEL_OBJECTS,
        "complications": INTERNATIONAL_TRAVEL_COMPLICATIONS, "speech_acts": INTERNATIONAL_TRAVEL_SPEECH_ACTS,
        "aim": "將中國地名與景點名稱轉為台灣繁體中文常見寫法，保留專名並避免混入簡體字；不得虛構即時旅遊資訊。",
    },
    {
        "category": "歐洲繁中地名與旅行", "count": 100,
        "eligible_eras": ["1997-2009", "2010-2019", "2020-2026"],
        "situations": INTERNATIONAL_TRAVEL_SITUATIONS, "objects": INTERNATIONAL_TRAVEL_OBJECTS,
        "complications": INTERNATIONAL_TRAVEL_COMPLICATIONS, "speech_acts": INTERNATIONAL_TRAVEL_SPEECH_ACTS,
        "aim": "使用台灣常見的歐洲城市、地標與景點繁體中文譯名，必要時附當地原名；不得虛構即時旅遊資訊。",
    },
    {
        "category": "其他國家繁中地名與旅行", "count": 150,
        "eligible_eras": ["1997-2009", "2010-2019", "2020-2026"],
        "situations": INTERNATIONAL_TRAVEL_SITUATIONS, "objects": INTERNATIONAL_TRAVEL_OBJECTS,
        "complications": INTERNATIONAL_TRAVEL_COMPLICATIONS, "speech_acts": INTERNATIONAL_TRAVEL_SPEECH_ACTS,
        "aim": "涵蓋加拿大、澳洲、紐西蘭、韓國、東南亞、南亞、中東、非洲與拉丁美洲常見景點繁體中文名稱；不得虛構即時旅遊資訊。",
    },
]


TITLE_PATTERNS = [
    "關於{activity}的那段{channel}", "{relationship}正在討論{activity}", "從{object_name}開始的{speech_act}",
    "當{activity}碰上{complication}", "{channel}裡沒有說完的話", "怎麼把{activity}說清楚",
    "一場圍繞{object_name}的{speech_act}", "{tone}地談{activity}", "{activity}之後的回覆",
    "寫下{activity}的幾種方式", "{object_name}與那次{activity}", "從{speech_act}到下一步",
]


def stable_index(key: str, size: int) -> int:
    digest = hashlib.sha256(key.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") % size


def choose(key: str, values: list | tuple):
    return values[stable_index(key, len(values))]


def allocate_pairs() -> list[tuple[dict, dict]]:
    era_by_name = {item["era"]: item for item in ERA_CONFIG}
    remaining = {item["era"]: item["count"] for item in ERA_CONFIG}
    initial = dict(remaining)
    pairs = []

    ordered_categories = sorted(
        CATEGORY_CONFIG,
        key=lambda item: len(item.get("eligible_eras", era_by_name)),
    )
    for category in ordered_categories:
        allowed = category.get("eligible_eras", list(era_by_name))
        for occurrence in range(category["count"]):
            candidates = [name for name in allowed if remaining[name] > 0]
            if not candidates:
                raise ValueError(f"no era capacity for {category['category']}")
            salt = f"{SEED}:{category['category']}:{occurrence}"
            era_name = max(
                candidates,
                key=lambda name: (remaining[name] / initial[name], stable_index(salt + name, 1_000_003)),
            )
            remaining[era_name] -= 1
            pairs.append((era_by_name[era_name], category))

    if any(remaining.values()):
        raise ValueError(f"unallocated era capacity: {remaining}")
    random.Random(SEED).shuffle(pairs)
    return pairs


def selected_entities(category: dict, era: dict, key: str) -> list[str]:
    if category["category"] == "台灣地標與地方生活":
        names = TAIWAN_ENTITIES_BY_ERA[era["era"]]
        first = choose(key + ":entity-a", names)
        second = choose(key + ":entity-b", [x for x in names if x != first])
        return [first, second]
    if category["category"] == "日本繁中景點與旅行":
        names = JAPAN_ENTITIES_BY_ERA[era["era"]]
        first = choose(key + ":entity-a", names)
        second = choose(key + ":entity-b", [x for x in names if x != first])
        return [first, second]
    international_names = {
        "美國繁中地名與旅行": USA_ENTITIES,
        "中國繁中地名與旅行": CHINA_ENTITIES,
        "歐洲繁中地名與旅行": EUROPE_ENTITIES,
        "其他國家繁中地名與旅行": OTHER_COUNTRY_ENTITIES,
    }.get(category["category"])
    if international_names:
        first = choose(key + ":entity-a", international_names)
        second = choose(key + ":entity-b", [x for x in international_names if x != first])
        return [first, second]
    if category["category"] == "商品品牌與科技":
        products = PRODUCTS_BY_ERA[era["era"]]
        first = choose(key + ":entity-a", products)
        second = choose(key + ":entity-b", [x for x in products if x != first])
        return [first, second]
    return []


def build_prompt(sequence: int, era: dict, category: dict, seen_titles: set[str], seen_signatures: set[tuple]) -> dict:
    base_key = f"{SEED}:{sequence}:{era['era']}:{category['category']}"
    for attempt in range(100):
        key = f"{base_key}:{attempt}"
        topic_index = stable_index(key + ":topic", len(category["situations"]))
        activity = category["situations"][topic_index]
        object_name = category["objects"][topic_index % len(category["objects"])]
        complication = category["complications"][topic_index % len(category["complications"])]
        minimum_era = MIN_ERA_BY_SITUATION.get(activity)
        if minimum_era and ERA_ORDER[era["era"]] < ERA_ORDER[minimum_era]:
            continue
        content_for_guard = activity + object_name + complication
        if any(term in content_for_guard for term in ERA_BANNED_CONTENT_TERMS[era["era"]]):
            continue
        speech_act = category["speech_acts"][topic_index % len(category["speech_acts"])]
        if "topic_relationships" in category:
            relationship = category["topic_relationships"][topic_index % len(category["topic_relationships"])]
        else:
            relationship = choose(key + ":relationship", RELATIONSHIPS_BY_CATEGORY[category["category"]])
        if any(term in relationship for term in ERA_BANNED_RELATIONSHIP_TERMS[era["era"]]):
            continue
        tone = choose(key + ":tone", TONES)
        region = choose(key + ":region", REGIONS)
        allowed_kinds = CATEGORY_CHANNEL_KINDS[category["category"]]
        compatible_channels = [value for value in era["channels"] if CHANNEL_KIND[value[0]] in allowed_kinds]
        if not compatible_channels:
            continue
        channel, output_form = choose(key + ":channel", compatible_channels)
        entities = selected_entities(category, era, key)
        signature = (era["era"], category["category"], activity, complication, speech_act, relationship, tone, channel, tuple(entities))
        if signature not in seen_signatures:
            seen_signatures.add(signature)
            break
    else:
        raise ValueError(f"could not make unique signature for {sequence}")

    title_values = {
        "activity": activity,
        "channel": channel,
        "relationship": relationship,
        "object_name": object_name,
        "speech_act": speech_act,
        "complication": complication,
        "tone": tone,
    }
    for offset in range(len(TITLE_PATTERNS)):
        pattern = TITLE_PATTERNS[(stable_index(key + ":title", len(TITLE_PATTERNS)) + offset) % len(TITLE_PATTERNS)]
        candidate = pattern.format(**title_values)
        if candidate not in seen_titles:
            title = candidate
            break
    else:
        title = f"{activity}：{relationship}在{channel}裡的{speech_act}（{sequence:05d}）"
    seen_titles.add(title)

    entity_text = "、".join(entities)
    scenario_templates = [
        "以{era}年的{region}為背景，讓{relationship}透過{channel}處理{activity}；過程中遇到{complication}，主要溝通目的為{speech_act}。",
        "描寫{era}年的{relationship}如何在{channel}中談{activity}。{complication}使原本簡單的事情需要進一步{speech_act}。",
        "從一段關於{activity}的{channel}開始，呈現{era}年{region}的{relationship}面對{complication}時如何{speech_act}。",
        "整理一組{era}年可能透過{channel}輸入的文字：{relationship}正在處理{activity}，並因{complication}而需要{speech_act}。",
    ]
    scenario = choose(key + ":scenario-template", scenario_templates).format(
        era=era["era"], region=region, relationship=relationship, channel=channel,
        activity=activity, complication=complication, speech_act=speech_act,
    )
    scenario += f"整體以{tone}的語氣表達。"
    if entities:
        scenario += f"內容自然使用「{entity_text}」。"

    requirements = [
        f"輸出形式為{output_form}，主要媒介是{channel}，總長約一千二百字。",
        f"主要人物關係為{relationship}，整體語氣是{tone}；不同人物仍須有可辨認的說話方式。",
        f"圍繞{activity}推進，讓「{complication}」實際改變措辭、回覆或決定。",
        f"至少具體呈現詢問、回應與後續處理，其中必須出現自然的{speech_act}用語。",
        "保留真實輸入會出現的短句、省略、改口、追問與確認，不要把每一句都修成作文語氣。",
        "同一意思至少用兩種不同說法表達，但不可機械替換同義詞或重複完整句型。",
        category["aim"],
        era["guard"],
    ]
    if entities:
        requirements.append(f"完整而正確地使用指定名稱：{entity_text}；不得自行改造名稱或捏造其即時狀態。")
    if "對話" in output_form or "訊息" in output_form or "客服" in output_form or "留言" in output_form:
        requirements.append("包含長短交錯的訊息與至少一次未立即獲得答案的追問，避免所有訊息長度一致。")
    else:
        requirements.append("文件內容須包含可直接擷取的自然句子，避免只列標題、欄位名稱或抽象綱要。")
    if category["category"] == "法律紛爭與政府政策":
        requirements.append("不得把人物主張寫成法律定論；若未提供可靠來源，不引用法條編號、金額門檻或現行期限。")

    return {
        "id": f"tw-typing-{sequence:05d}",
        "era": era["era"],
        "recent_30_years": era["recent"],
        "category": category["category"],
        "title": title,
        "target_chars": TARGET_CHARS,
        "accepted_char_range": [1050, 1350],
        "region": region,
        "channel": channel,
        "output_form": output_form,
        "relationship": relationship,
        "speech_act": speech_act,
        "tone": tone,
        "named_entities": entities,
        "scenario": scenario,
        "requirements": requirements,
        "language_requirements": ["使用台灣繁體中文與全形中文標點。", "用字須符合指定年代與媒介。", "正式程度須符合人物關係和溝通目的。", "可以使用自然口語，但不得混用簡體字。"],
        "avoid": ["不得重複固定開場或制式結尾", "不得虛構真實私人個資", "不得捏造研究數字、法律條文、產品規格、票價或營業時間", "不得把所有人物寫成相同語氣", "避免每段都先講道理再舉例"],
        "evaluation": ["是否像指定情境下真的會輸入的文字", "溝通目的是否清楚", "長短句與語氣是否自然", "名稱與年代是否正確", "是否提供有用而不呆板的相鄰詞組"],
        "weight_class": "high" if category["category"] in {"日常溝通與協調", "工作討論與公事", "情緒與人際關係"} else "medium",
    }


def main() -> None:
    pairs = allocate_pairs()
    seen_titles: set[str] = set()
    seen_signatures: set[tuple] = set()
    prompts = [build_prompt(i, era, category, seen_titles, seen_signatures) for i, (era, category) in enumerate(pairs, 1)]

    if len(prompts) != 10_000:
        raise ValueError(f"expected 10000 prompts, got {len(prompts)}")
    if len({item["id"] for item in prompts}) != len(prompts):
        raise ValueError("duplicate prompt id")
    if len({item["title"] for item in prompts}) != len(prompts):
        raise ValueError("duplicate title")

    era_counts = Counter(item["era"] for item in prompts)
    category_counts = Counter(item["category"] for item in prompts)
    expected_eras = {item["era"]: item["count"] for item in ERA_CONFIG}
    expected_categories = {item["category"]: item["count"] for item in CATEGORY_CONFIG}
    if era_counts != expected_eras:
        raise ValueError(f"era count mismatch: {era_counts}")
    if category_counts != expected_categories:
        raise ValueError(f"category count mismatch: {category_counts}")
    recent_count = sum(item["recent_30_years"] for item in prompts)
    if recent_count != 7000:
        raise ValueError(f"expected 7000 recent prompts, got {recent_count}")
    if any(item["era"] in {"1926-1945", "1946-1969"} for item in prompts if item["category"] == "日本繁中景點與旅行"):
        raise ValueError("Japan travel prompt assigned to unsupported era")
    modern_international = {"美國繁中地名與旅行", "中國繁中地名與旅行", "歐洲繁中地名與旅行", "其他國家繁中地名與旅行"}
    if any(not item["recent_30_years"] for item in prompts if item["category"] in modern_international):
        raise ValueError("modern international travel prompt assigned before 1997")

    with OUTPUT.open("w", encoding="utf-8") as stream:
        for prompt in prompts:
            stream.write(json.dumps(prompt, ensure_ascii=False, separators=(",", ":")) + "\n")

    stats = {
        "total": len(prompts),
        "recent_30_years": recent_count,
        "recent_share": recent_count / len(prompts),
        "era_counts": dict(era_counts),
        "category_counts": dict(category_counts),
        "channel_counts": dict(Counter(item["channel"] for item in prompts)),
        "output_form_counts": dict(Counter(item["output_form"] for item in prompts)),
        "named_entity_prompt_count": sum(bool(item["named_entities"]) for item in prompts),
        "unique_titles": len({item["title"] for item in prompts}),
        "unique_scenarios": len({item["scenario"] for item in prompts}),
    }
    STATS.write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    preview_indexes = []
    for category in CATEGORY_CONFIG:
        preview_indexes.append(next(i for i, item in enumerate(prompts) if item["category"] == category["category"]))
    for era in ERA_CONFIG:
        preview_indexes.append(next(i for i, item in enumerate(prompts) if item["era"] == era["era"]))
    preview_indexes = list(dict.fromkeys(preview_indexes))
    lines = ["# Typing prompt v2 preview", "", "The complete dataset is `typing-prompts-v2.jsonl`.", ""]
    for index in preview_indexes:
        item = prompts[index]
        lines.extend([
            f"## {item['id']}｜{item['title']}", "",
            f"- 年代：{item['era']}", f"- 類別：{item['category']}", f"- 管道：{item['channel']}",
            f"- 形式：{item['output_form']}", f"- 關係：{item['relationship']}", f"- 目的：{item['speech_act']}",
            f"- 情境：{item['scenario']}", "- 必寫要求：", *[f"  - {value}" for value in item["requirements"]], "",
        ])
    PREVIEW.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

    print(f"wrote {len(prompts)} prompts to {OUTPUT}")
    print(f"1997-2026: {recent_count} ({recent_count / len(prompts):.0%})")
    print("era counts:", dict(era_counts))
    print("category counts:", dict(category_counts))


if __name__ == "__main__":
    main()
