#!/usr/bin/env python3
"""Build 350 deterministic v3 assignments that fill gaps found in v2."""

from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path
import random


SEED = 20260925
ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "typing-prompts-v3.jsonl"
PREVIEW = ROOT / "typing-prompts-v3-preview.md"
STATS = ROOT / "typing-prompts-v3-stats.json"
PLAN = ROOT / "typing-prompts-v3-plan.md"


ERA_CONFIG = [
    {"era": "1926-1945", "count": 18, "recent": False, "guard": "不得出現網路、手機、數位平台或不合年代的行政與消費工具。"},
    {"era": "1946-1969", "count": 28, "recent": False, "guard": "使用戰後早期台灣可能出現的公文、書信、會議與工作詞彙。"},
    {"era": "1970-1989", "count": 38, "recent": False, "guard": "科技、職場、交通與消費內容須符合一九七〇至八〇年代台灣環境。"},
    {"era": "1990-1996", "count": 21, "recent": False, "guard": "呈現紙本轉向數位的過渡，不得提前使用社群平台、智慧型手機或行動支付。"},
    {"era": "1997-2009", "count": 63, "recent": True, "guard": "區分電子郵件、BBS、即時通訊、簡訊與早期網路服務的使用時序。"},
    {"era": "2010-2019", "count": 77, "recent": True, "guard": "使用二〇一〇年代台灣自然用語，不得提前使用尚未普及的生成式人工智慧服務。"},
    {"era": "2020-2026", "count": 105, "recent": True, "guard": "使用二〇二〇年代台灣自然繁體中文；可變的法律、票價、規格與政策不得寫成確定事實。"},
]

ERA_ORDER = {item["era"]: index for index, item in enumerate(ERA_CONFIG)}
REGIONS = ["北部都會", "北部郊區", "中部城市", "中部鄉鎮", "南部城市", "南部鄉鎮", "東部地區", "離島", "跨縣市", "線上跨地區"]


MODE_CONFIG = {
    "短訊息包": {
        "eligible_eras": ["1997-2009", "2010-2019", "2020-2026"],
        "target_chars": 1050, "accepted_char_range": [900, 1250],
        "channels": {
            "1997-2009": [("手機簡訊", "多輪短訊息包"), ("即時通訊", "一對一短對話")],
            "2010-2019": [("通訊軟體私訊", "一對一短對話"), ("通訊軟體群組", "多人短訊息串")],
            "2020-2026": [("通訊軟體私訊", "一對一短對話"), ("通訊軟體群組", "多人短訊息串"), ("工作聊天軟體", "工作短訊息串")],
        },
        "requirement": "以三十五至六十則短訊息組成；至少一半訊息不超過十二個漢字，旁白不得超過全文兩成。",
    },
    "正式文件": {
        "eligible_eras": [item["era"] for item in ERA_CONFIG],
        "target_chars": 1200, "accepted_char_range": [1050, 1350],
        "channels": {
            "default": [("公文草稿", "正式文件"), ("陳情書", "陳情與回覆"), ("調查紀錄", "紀錄與擬辦"), ("契約往返", "條款與書面回覆")],
        },
        "requirement": "寫成可直接使用的文件與回覆，保留自然段落及明確主詞，不得只列抽象綱要。",
    },
    "工作討論串": {
        "eligible_eras": [item["era"] for item in ERA_CONFIG],
        "target_chars": 1200, "accepted_char_range": [1050, 1350],
        "channels": {
            "1926-1945": [("會議紀錄", "紀錄與發言摘要"), ("工作便箋", "便箋往返")],
            "1946-1969": [("公司備忘錄", "工作文件組"), ("會議紀錄", "紀錄與發言摘要")],
            "1970-1989": [("公司備忘錄", "工作文件組"), ("交接紀錄", "交接與追問")],
            "1990-1996": [("電子郵件", "郵件串"), ("公司文件", "工作文件組")],
            "1997-2009": [("電子郵件", "郵件串"), ("工作文件", "文件與批註")],
            "2010-2019": [("電子郵件", "郵件串"), ("共享文件", "文件與批註")],
            "2020-2026": [("工作聊天軟體", "工作討論串"), ("共享文件", "文件與批註"), ("電子郵件", "郵件串")],
        },
        "requirement": "呈現任務、責任人、卡點與可追蹤決定；不要讓所有人只說完整而客氣的長句。",
    },
    "社群討論串": {
        "eligible_eras": ["1997-2009", "2010-2019", "2020-2026"],
        "target_chars": 1050, "accepted_char_range": [900, 1250],
        "channels": {
            "1997-2009": [("電子布告欄", "討論串"), ("部落格留言", "文章與留言")],
            "2010-2019": [("社群貼文", "貼文與留言"), ("通訊軟體群組", "多人對話")],
            "2020-2026": [("社群留言", "貼文與留言"), ("通訊軟體群組", "多人對話")],
        },
        "requirement": "至少安排二十則貼文、留言或接話，其中三分之一是自然短句；允許離題、反話與沒有收束的尾聲。",
    },
    "客服交易對話": {
        "eligible_eras": ["2010-2019", "2020-2026"],
        "target_chars": 1050, "accepted_char_range": [900, 1250],
        "channels": {"default": [("客服文字對談", "客服紀錄"), ("平台申訴訊息", "申訴與回覆")]},
        "requirement": "交錯呈現顧客與業者的短句、資料補充與等待，不得讓客服每句都套用相同官樣開頭。",
    },
    "搜尋與欄位組": {
        "eligible_eras": ["1997-2009", "2010-2019", "2020-2026"],
        "target_chars": 950, "accepted_char_range": [800, 1150],
        "channels": {"default": [("搜尋與人工智慧提示", "查詢與追問集合"), ("線上表單", "欄位與補充說明"), ("技術問答", "問題與回覆")]} ,
        "requirement": "由三十至五十組搜尋詞、欄位、提示、追問或短答組成，不得用長篇旁白把片段全部串成作文。",
    },
    "私人往返": {
        "eligible_eras": [item["era"] for item in ERA_CONFIG],
        "target_chars": 1150, "accepted_char_range": [1000, 1300],
        "channels": {
            "1926-1945": [("私人書信", "書信往返"), ("日記與便條", "片段與回覆")],
            "1946-1969": [("私人書信", "書信往返"), ("日記與便條", "片段與回覆")],
            "1970-1989": [("私人書信", "書信往返"), ("電話留言", "留言與回覆")],
            "1990-1996": [("私人書信", "書信往返"), ("呼叫器留言", "短句與電話回覆")],
            "1997-2009": [("即時通訊", "長短訊息往返"), ("電子郵件", "私人郵件串")],
            "2010-2019": [("通訊軟體私訊", "長短訊息往返"), ("電子郵件", "私人郵件串")],
            "2020-2026": [("通訊軟體私訊", "長短訊息往返"), ("私人長訊息", "長短訊息往返")],
        },
        "requirement": "讓情緒透過停頓、改口、未回答的問題與具體行動呈現，不要替人物寫出完整心理分析。",
    },
}


CATEGORY_CONFIG = [
    {
        "category": "工作討論與公事補強", "count": 70,
        "mode_counts": {"正式文件": 25, "工作討論串": 35, "短訊息包": 10},
        "tone_counts": {"正式謹慎": 20, "簡短俐落": 15, "自然直接": 10, "客氣克制": 10, "急迫但清楚": 10, "耐心說明": 5},
        "relationships": ["同事", "主管與部屬", "跨部門同仁", "公司與客戶", "採購與供應商", "承辦人與協辦人"],
        "situations": [
            ("專案延遲與重新排程", "進度表", "不同部門仍在等待彼此資料", "回報進度"),
            ("軟體錯誤無法穩定重現", "錯誤紀錄", "截圖與實際操作結果不一致", "排查問題"),
            ("會議決議沒有明確負責人", "會議紀錄", "多人以為別人會接手", "確認分工"),
            ("工作交接缺少關鍵步驟", "交接文件", "原負責人暫時聯絡不上", "補齊交接"),
            ("採購規格與報價不一致", "報價單", "品項名稱相近但內容不同", "核對規格"),
            ("客戶追加原範圍外需求", "需求單", "交期與預算都沒有跟著調整", "澄清範圍"),
            ("事故回報需要保留時序", "事故紀錄", "口頭說法與登記時間不同", "釐清經過"),
            ("加班與排班臨時變動", "班表", "同仁已經安排私人行程", "協調人力"),
            ("帳款與發票資料對不上", "發票與對帳單", "付款紀錄缺少一筆註記", "核對帳款"),
            ("遠端協作檔案版本混亂", "共享文件", "多人同時修改不同副本", "統一版本"),
        ],
    },
    {
        "category": "法律公文與政策補強", "count": 70,
        "mode_counts": {"正式文件": 50, "工作討論串": 10, "社群討論串": 10},
        "tone_counts": {"正式謹慎": 28, "客氣克制": 14, "帶著不滿": 10, "耐心說明": 8, "急迫但清楚": 5, "簡短俐落": 5},
        "relationships": ["房東與房客", "勞工與雇主", "事故當事人", "管委會與住戶", "居民與承辦人", "契約雙方", "申訴人與機關"],
        "situations": [
            ("租屋押金與修繕費爭議", "租賃契約", "雙方對點交狀況說法不同", "提出書面主張"),
            ("加班費與出勤紀錄爭議", "出勤紀錄", "排班紀錄散落在不同地方", "整理證據"),
            ("交通事故責任尚待調查", "事故照片", "當事人把推測寫成確定結論", "釐清事實"),
            ("社區噪音與管理規約爭議", "管委會紀錄", "多次反映卻沒有一致處理方式", "要求說明"),
            ("採購契約內容前後不一致", "契約草稿", "附件與正文使用不同名稱", "核對條款"),
            ("個人資料疑似外洩", "通知與存取紀錄", "目前只能確認部分時間點", "要求調查"),
            ("網路交易款項與交付糾紛", "交易紀錄", "平台、買家與賣家各有一段資料", "提出申訴"),
            ("政策草案影響不同居民", "政策說明資料", "短期便利與長期成本衝突", "提出意見"),
            ("政府回覆未處理原陳情重點", "陳情書", "回函只引用一般原則", "補充陳情"),
            ("疑似違規事項需要查辦", "查核資料", "尚無法確認是否涉案", "擬具處理意見"),
        ],
    },
    {
        "category": "情緒安慰與關係衝突補強", "count": 55,
        "mode_counts": {"短訊息包": 30, "社群討論串": 15, "私人往返": 10},
        "tone_counts": {"溫和安慰": 25, "猶豫試探": 10, "帶著不滿": 8, "自然直接": 5, "耐心說明": 5, "急迫但清楚": 2},
        "relationships": ["家人", "朋友", "伴侶", "同學", "同事", "久未聯絡的朋友", "手足"],
        "situations": [
            ("考試或面試失利", "通知", "安慰聽起來像在說教", "陪伴與鼓勵"),
            ("工作出錯後持續自責", "工作紀錄", "當事人不想立刻分析原因", "先接住情緒"),
            ("朋友之間的誤會擴大", "舊對話", "一句話被轉傳後失去上下文", "澄清與道歉"),
            ("家人對人生選擇不認同", "行事曆", "關心逐漸變成反覆追問", "說明界線"),
            ("伴侶為時間安排爭執", "共同計畫", "雙方都覺得沒有被聽見", "表達不滿"),
            ("生病或照顧期間需要幫忙", "就醫與採買清單", "接受幫助的人怕造成負擔", "具體提供協助"),
            ("親友離世後不知道怎麼開口", "紀念物", "制式安慰讓人更有距離", "陪伴與傾聽"),
            ("需要拒絕朋友的請託", "未讀訊息", "怕拒絕會傷害關係", "溫和拒絕"),
            ("道歉後仍沒有得到回覆", "道歉文字", "事情暫時沒有立即解法", "承認影響"),
            ("分手後歸還共同物品", "物品清單", "情緒與實際安排混在一起", "結束關係"),
        ],
    },
    {
        "category": "社群口語幽默與爭論補強", "count": 50,
        "mode_counts": {"社群討論串": 30, "短訊息包": 20},
        "tone_counts": {"輕鬆幽默": 25, "自然直接": 10, "帶著不滿": 8, "簡短俐落": 5, "急迫但清楚": 2},
        "relationships": ["朋友", "同事", "同學", "家人", "遊戲隊友", "陌生網友"],
        "situations": [
            ("上班通勤又遇到延誤", "群組截圖", "有人認真回答了原本的幹話", "吐槽與接話"),
            ("聚餐選店選到大家都沒意見", "餐廳清單", "每個人都說隨便卻一直否決", "開玩笑催決定"),
            ("線上遊戲隊友臨時消失", "組隊訊息", "反話被誤會成真的不滿", "吐槽與澄清"),
            ("社群熱門話題吵成兩派", "留言串", "大家只回應最刺耳的一句", "爭辯與追問"),
            ("辦公室設備又在期限前故障", "錯誤畫面", "同一件事已經發生不只一次", "自嘲與抱怨"),
            ("看球賽時比分突然逆轉", "即時比分", "群組訊息快到彼此交錯", "即時反應"),
            ("朋友曬出失敗料理", "料理照片", "吐槽踩到對方真正介意的地方", "收回玩笑"),
            ("搶票排隊最後仍然落空", "排隊畫面", "有人開始分享離譜偏方", "誇張抱怨"),
            ("家庭群組轉傳可疑資訊", "轉傳訊息", "長輩把查證當成不尊重", "查證與緩頰"),
            ("假日結束前大家集體不想上班", "行事曆", "玩笑裡其實帶著壓力", "互相吐槽"),
        ],
    },
    {
        "category": "日常短訊息與協調補強", "count": 50,
        "mode_counts": {"短訊息包": 30, "社群討論串": 10, "搜尋與欄位組": 10},
        "tone_counts": {"自然直接": 15, "簡短俐落": 15, "客氣克制": 8, "急迫但清楚": 7, "輕鬆幽默": 5},
        "relationships": ["家人", "朋友", "伴侶", "同學", "鄰居", "同事"],
        "situations": [
            ("臨時更改集合時間", "行事曆", "有人只看到前一版時間", "通知改期"),
            ("請人代收包裹", "取貨通知", "門禁與交接方式沒有說清楚", "請託與確認"),
            ("家人晚歸報平安", "交通資訊", "手機快要沒電", "報平安"),
            ("朋友聚會分配採買", "採買清單", "同一樣東西有兩個人都買了", "重新分工"),
            ("鄰居協調施工時間", "社區公告", "不同住戶作息差很多", "協調時段"),
            ("接送地點臨時改變", "地圖定位", "出口名稱容易混淆", "確認位置"),
            ("借用物品後找不到配件", "物品照片", "雙方記得的內容不同", "核對物品"),
            ("失物協尋需要補充特徵", "失物照片", "最初描述太籠統", "補充資訊"),
            ("家庭群組誤傳私人訊息", "刪除通知", "越解釋越像掩飾", "澄清誤傳"),
            ("確認對方現在是否方便通話", "未接來電", "事情重要但不是緊急事件", "詢問時間"),
        ],
    },
    {
        "category": "消費住宿與交易補強", "count": 30,
        "mode_counts": {"客服交易對話": 25, "短訊息包": 5},
        "tone_counts": {"帶著不滿": 9, "急迫但清楚": 7, "客氣克制": 6, "耐心說明": 4, "正式謹慎": 4},
        "relationships": ["顧客與客服", "買家與賣家", "房客與住宿業者", "乘客與業者", "訂位者與店家"],
        "situations": [
            ("蝦皮購物訂單延遲到貨", "訂單編號", "物流狀態多日沒有更新", "催單"),
            ("退貨後退款仍未入帳", "退款紀錄", "平台與銀行顯示不同狀態", "追問退款"),
            ("商品規格與頁面描述不同", "商品頁截圖", "賣家只回覆制式說明", "反映差異"),
            ("住宿訂房內容與確認信不同", "訂房確認信", "房型名稱相近但條件不同", "核對訂房"),
            ("餐點漏送與補送時間不明", "訂單明細", "店家只說會處理但沒有時間", "要求補送"),
            ("二手交易現場驗貨發現瑕疵", "商品照片", "照片沒有拍到問題位置", "議價或取消"),
            ("會員取消後仍收到續約通知", "續約信件", "系統顯示與客服說法不同", "確認取消"),
            ("維修完成後原問題仍存在", "維修單", "測試方式與實際使用情境不同", "再次報修"),
            ("交通票券扣款成功但沒有出票", "付款紀錄", "系統查不到完整訂單", "要求查詢"),
            ("預約時間被業者臨時更動", "預約訊息", "替代時段都不方便", "協商改期"),
        ],
    },
    {
        "category": "數位生活與混合輸入補強", "count": 25,
        "mode_counts": {"搜尋與欄位組": 25},
        "tone_counts": {"簡短俐落": 7, "自然直接": 7, "耐心說明": 5, "輕鬆幽默": 3, "急迫但清楚": 3},
        "relationships": ["使用者與客服", "同事", "朋友", "學生與老師", "管理者與使用者"],
        "situations": [
            ("帳號登入與雙重驗證失敗", "錯誤代碼", "手機與電腦顯示不同結果", "整理搜尋詞"),
            ("檔案路徑與版本名稱混亂", "檔名", "副檔名被系統隱藏", "詢問操作"),
            ("手機更新後設定位置改變", "設定畫面", "舊教學使用不同選單名稱", "比較步驟"),
            ("線上表單一直無法送出", "欄位訊息", "錯誤提示沒有指出哪一欄", "排查欄位"),
            ("學生查證人工智慧產生內容", "生成文字", "回答看似合理但沒有來源", "設計追問"),
            ("網站連結在不同瀏覽器失效", "網址", "登入狀態影響顯示內容", "描述問題"),
            ("照片備份與儲存空間不足", "容量資訊", "雲端與本機數字不同", "比較方案"),
            ("視訊會議聲音與字幕異常", "裝置名稱", "只有部分參與者聽不到", "排查設備"),
            ("購物平台通知太多", "通知設定", "關閉促銷後仍收到部分提醒", "調整設定"),
            ("輸入法更新後操作習慣改變", "鍵盤設定", "Enter 與選字行為和以前不同", "描述需求"),
        ],
    },
]


OUTCOME_COUNTS = {
    "工作討論與公事補強": {"仍未解決": 10, "部分解決": 15, "已有明確處理": 45},
    "法律公文與政策補強": {"仍未解決": 20, "部分解決": 15, "已有明確處理": 35},
    "情緒安慰與關係衝突補強": {"仍未解決": 20, "部分解決": 10, "已有明確處理": 25},
    "社群口語幽默與爭論補強": {"仍未解決": 10, "部分解決": 5, "已有明確處理": 35},
    "日常短訊息與協調補強": {"仍未解決": 5, "部分解決": 5, "已有明確處理": 40},
    "消費住宿與交易補強": {"仍未解決": 5, "部分解決": 5, "已有明確處理": 20},
    "數位生活與混合輸入補強": {"已有明確處理": 25},
}


CONNECTOR_COUNTS = {
    "又／再／也": 90,
    "和／與／以及": 90,
    "但／不過／可是": 60,
    "因為／所以／因此": 50,
    "如果／除非／否則": 60,
}


FEATURE_COUNTS = {
    "Emoji 或反應符號": 15,
    "注音語助詞": 10,
    "網址、檔名或路徑": 15,
    "英文縮寫與產品詞": 25,
    "金額、訂單或案件編號": 20,
    "日期與時間": 25,
}

FEATURE_REQUIREMENTS = {
    "Emoji 或反應符號": "自然加入一至三個 Emoji 或反應符號，讓符號與相鄰中文符合真實訊息語境，不得每句都加。",
    "注音語助詞": "自然加入少量台灣聊天常見的注音語助詞或笑聲，例如「ㄟ」「ㄏㄏ」，不得密集堆疊。",
    "網址、檔名或路徑": "自然出現安全的網址片段、檔名、資料夾路徑或電子郵件欄位；不得使用真實私人帳號與可辨識個資。",
    "英文縮寫與產品詞": "自然混用少量台灣常見英文縮寫、App 名稱或技術詞，保留中文語序，不要整段改寫成英文。",
    "金額、訂單或案件編號": "自然出現阿拉伯數字金額、訂單編號或案件編號，使用虛構且不對應真人的資料。",
    "日期與時間": "自然出現至少兩個以阿拉伯數字書寫的日期或時間，並讓前後中文搭配符合台灣用法。",
}


MIN_ERA_BY_ACTIVITY = {
    "專案延遲與重新排程": "1946-1969",
    "軟體錯誤無法穩定重現": "1990-1996",
    "客戶追加原範圍外需求": "1946-1969",
    "遠端協作檔案版本混亂": "1997-2009",
    "個人資料疑似外洩": "1990-1996",
    "網路交易款項與交付糾紛": "1997-2009",
    "考試或面試失利": "1946-1969",
    "工作出錯後持續自責": "1946-1969",
    "需要拒絕朋友的請託": "1997-2009",
}


RELATIONSHIPS_BY_ACTIVITY = {
    "專案延遲與重新排程": ["同事", "主管與部屬", "跨部門同仁", "承辦人與協辦人"],
    "軟體錯誤無法穩定重現": ["同事", "跨部門同仁", "公司與客戶"],
    "會議決議沒有明確負責人": ["同事", "主管與部屬", "承辦人與協辦人"],
    "工作交接缺少關鍵步驟": ["同事", "主管與部屬"],
    "採購規格與報價不一致": ["採購與供應商", "公司與客戶"],
    "客戶追加原範圍外需求": ["公司與客戶", "跨部門同仁"],
    "事故回報需要保留時序": ["主管與部屬", "承辦人與協辦人"],
    "加班與排班臨時變動": ["同事", "主管與部屬"],
    "帳款與發票資料對不上": ["採購與供應商", "公司與客戶"],
    "遠端協作檔案版本混亂": ["同事", "跨部門同仁"],
    "租屋押金與修繕費爭議": ["房東與房客"],
    "加班費與出勤紀錄爭議": ["勞工與雇主"],
    "交通事故責任尚待調查": ["事故當事人"],
    "社區噪音與管理規約爭議": ["管委會與住戶", "居民與承辦人"],
    "採購契約內容前後不一致": ["契約雙方"],
    "個人資料疑似外洩": ["申訴人與機關", "契約雙方"],
    "網路交易款項與交付糾紛": ["契約雙方", "申訴人與機關"],
    "政策草案影響不同居民": ["居民與承辦人"],
    "政府回覆未處理原陳情重點": ["申訴人與機關", "居民與承辦人"],
    "疑似違規事項需要查辦": ["申訴人與機關", "居民與承辦人"],
    "蝦皮購物訂單延遲到貨": ["顧客與客服", "買家與賣家"],
    "退貨後退款仍未入帳": ["顧客與客服", "買家與賣家"],
    "商品規格與頁面描述不同": ["買家與賣家", "顧客與客服"],
    "住宿訂房內容與確認信不同": ["房客與住宿業者"],
    "餐點漏送與補送時間不明": ["訂位者與店家", "顧客與客服"],
    "二手交易現場驗貨發現瑕疵": ["買家與賣家"],
    "會員取消後仍收到續約通知": ["顧客與客服"],
    "維修完成後原問題仍存在": ["顧客與客服"],
    "交通票券扣款成功但沒有出票": ["乘客與業者", "顧客與客服"],
    "預約時間被業者臨時更動": ["訂位者與店家"],
}


TITLE_PATTERNS = [
    "{activity}時真正會打出的字", "{channel}裡的{speech_act}", "{object_name}還沒說清楚",
    "{relationship}談{activity}", "{tone}地處理{activity}", "從{object_name}開始的對話",
]


def stable_index(key: str, size: int) -> int:
    digest = hashlib.sha256(key.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") % size


def choose(key: str, values: list | tuple):
    return values[stable_index(key, len(values))]


def expanded(counter: dict[str, int], seed: str) -> list[str]:
    values = [name for name, count in counter.items() for _ in range(count)]
    random.Random(seed).shuffle(values)
    return values


def assignment_specs() -> list[dict]:
    specs = []
    for category in CATEGORY_CONFIG:
        modes = expanded(category["mode_counts"], f"{SEED}:{category['category']}:modes")
        tones = expanded(category["tone_counts"], f"{SEED}:{category['category']}:tones")
        outcomes = expanded(OUTCOME_COUNTS[category["category"]], f"{SEED}:{category['category']}:outcomes")
        if not (len(modes) == len(tones) == len(outcomes) == category["count"]):
            raise ValueError(f"quota mismatch for {category['category']}")
        for occurrence, (mode, tone, outcome) in enumerate(zip(modes, tones, outcomes)):
            specs.append({"category": category, "mode": mode, "tone": tone, "outcome": outcome, "occurrence": occurrence})
    return specs


def allocate_eras(specs: list[dict]) -> list[dict]:
    by_name = {item["era"]: item for item in ERA_CONFIG}
    remaining = {item["era"]: item["count"] for item in ERA_CONFIG}
    initial = dict(remaining)
    ordered = sorted(
        specs,
        key=lambda spec: (len(MODE_CONFIG[spec["mode"]]["eligible_eras"]), stable_index(f"{SEED}:{spec['category']['category']}:{spec['occurrence']}", 1_000_003)),
    )
    for spec in ordered:
        allowed = MODE_CONFIG[spec["mode"]]["eligible_eras"]
        candidates = [name for name in allowed if remaining[name] > 0]
        if not candidates:
            raise ValueError(f"no era capacity for {spec['category']['category']} / {spec['mode']}")
        salt = f"{SEED}:{spec['category']['category']}:{spec['mode']}:{spec['occurrence']}"
        era_name = max(candidates, key=lambda name: (remaining[name] / initial[name], stable_index(salt + name, 1_000_003)))
        remaining[era_name] -= 1
        spec["era"] = by_name[era_name]
    if any(remaining.values()):
        raise ValueError(f"unallocated era capacity: {remaining}")
    random.Random(SEED).shuffle(specs)
    return specs


def assign_connectors(specs: list[dict]) -> None:
    values = expanded(CONNECTOR_COUNTS, f"{SEED}:connectors")
    for spec, connector in zip(specs, values):
        spec["connector_focus"] = connector


def feature_eligible(spec: dict, feature: str) -> bool:
    era_index = ERA_ORDER[spec["era"]["era"]]
    category = spec["category"]["category"]
    mode = spec["mode"]
    if feature == "Emoji 或反應符號":
        return era_index >= ERA_ORDER["2010-2019"] and mode in {"短訊息包", "社群討論串"}
    if feature == "注音語助詞":
        return era_index >= ERA_ORDER["1997-2009"] and category in {"社群口語幽默與爭論補強", "日常短訊息與協調補強", "情緒安慰與關係衝突補強"}
    if feature == "網址、檔名或路徑":
        return era_index >= ERA_ORDER["1997-2009"] and category in {"數位生活與混合輸入補強", "工作討論與公事補強", "消費住宿與交易補強"}
    if feature == "英文縮寫與產品詞":
        return era_index >= ERA_ORDER["1990-1996"] and category in {"數位生活與混合輸入補強", "工作討論與公事補強", "消費住宿與交易補強", "社群口語幽默與爭論補強"}
    if feature == "金額、訂單或案件編號":
        return category in {"消費住宿與交易補強", "法律公文與政策補強", "工作討論與公事補強"}
    if feature == "日期與時間":
        return True
    raise KeyError(feature)


def assign_features(specs: list[dict]) -> None:
    for spec in specs:
        spec["input_feature"] = "無指定混合特徵"
    for feature, count in FEATURE_COUNTS.items():
        candidates = [spec for spec in specs if spec["input_feature"] == "無指定混合特徵" and feature_eligible(spec, feature)]
        candidates.sort(key=lambda spec: stable_index(f"{SEED}:{feature}:{spec['category']['category']}:{spec['occurrence']}", 1_000_003))
        if len(candidates) < count:
            raise ValueError(f"not enough candidates for {feature}: {len(candidates)} < {count}")
        for spec in candidates[:count]:
            spec["input_feature"] = feature


def channel_for(spec: dict, key: str) -> tuple[str, str]:
    category = spec["category"]["category"]
    era = spec["era"]["era"]
    if spec["mode"] == "正式文件" and category == "工作討論與公事補強":
        return choose(key + ":channel", [("公司公文", "正式文件"), ("簽呈草稿", "簽辦與批示"), ("調查紀錄", "紀錄與擬辦"), ("契約往返", "條款與書面回覆")])
    if spec["mode"] == "工作討論串" and category == "法律公文與政策補強":
        if ERA_ORDER[era] <= ERA_ORDER["1970-1989"]:
            return choose(key + ":channel", [("承辦便箋", "便箋與擬辦"), ("會議紀錄", "紀錄與發言摘要")])
        if era == "1990-1996":
            return choose(key + ":channel", [("公司文件", "工作文件組"), ("傳真往返", "文件往返")])
        if era == "1997-2009":
            return choose(key + ":channel", [("電子郵件", "郵件串"), ("工作文件", "文件與批註")])
        return choose(key + ":channel", [("內部簽辦討論", "簽辦與回覆"), ("電子郵件", "郵件串"), ("共享文件", "文件與批註")])
    mode = MODE_CONFIG[spec["mode"]]
    channels = mode["channels"].get(era, mode["channels"].get("default"))
    if not channels:
        raise ValueError(f"no channel for {spec['mode']} / {spec['era']['era']}")
    return choose(key + ":channel", channels)


def build_prompt(sequence: int, spec: dict, seen_titles: set[str], seen_signatures: set[tuple]) -> dict:
    category = spec["category"]
    era = spec["era"]
    mode = MODE_CONFIG[spec["mode"]]
    base_key = f"{SEED}:{sequence}:{era['era']}:{category['category']}:{spec['mode']}"
    for attempt in range(100):
        key = f"{base_key}:{attempt}"
        activity, object_name, complication, speech_act = choose(key + ":situation", category["situations"])
        minimum_era = MIN_ERA_BY_ACTIVITY.get(activity)
        if minimum_era and ERA_ORDER[era["era"]] < ERA_ORDER[minimum_era]:
            continue
        relationship = choose(key + ":relationship", RELATIONSHIPS_BY_ACTIVITY.get(activity, category["relationships"]))
        compatible_regions = REGIONS if era["recent"] else [region for region in REGIONS if region != "線上跨地區"]
        region = choose(key + ":region", compatible_regions)
        channel, output_form = channel_for(spec, key)
        signature = (era["era"], category["category"], activity, complication, relationship, spec["tone"], spec["mode"], channel, spec["outcome"], spec["input_feature"])
        if signature not in seen_signatures:
            seen_signatures.add(signature)
            break
    else:
        raise ValueError(f"could not make unique signature for {sequence}")

    title_values = {"activity": activity, "channel": channel, "speech_act": speech_act, "object_name": object_name, "relationship": relationship, "tone": spec["tone"]}
    for offset in range(len(TITLE_PATTERNS)):
        pattern = TITLE_PATTERNS[(stable_index(key + ":title", len(TITLE_PATTERNS)) + offset) % len(TITLE_PATTERNS)]
        candidate = pattern.format(**title_values)
        if candidate not in seen_titles:
            title = candidate
            break
    else:
        title = f"{activity}的{output_form}（v3-{sequence:03d}）"
    seen_titles.add(title)

    requirements = [
        f"輸出形式為{output_form}，主要媒介是{channel}；目標約 {mode['target_chars']} 個漢字。",
        mode["requirement"],
        f"主要人物關係為{relationship}，整體語氣是{spec['tone']}；語氣必須由實際措辭呈現，不能只在旁白宣告。",
        f"圍繞{activity}推進，讓「{complication}」實際改變說法、回覆或決定，溝通目的為{speech_act}。",
        f"結局狀態為「{spec['outcome']}」；若尚未解決，不得強行和解、總結教訓或承諾下一步。",
        f"自然呈現連接詞組「{spec['connector_focus']}」的不同用法，避免連續硬塞或機械造句。",
        era["guard"],
        "使用台灣繁體中文與台灣慣用語；不得混入中國大陸行政、軟硬體、交通、客服或生活用詞。",
        "禁止套用『確認、說明、處理、留下紀錄、約定下一步』的固定結尾；只有情境真正需要時才能使用其中個別詞語。",
    ]
    if spec["input_feature"] != "無指定混合特徵":
        requirements.append(FEATURE_REQUIREMENTS[spec["input_feature"]])
    if category["category"] == "法律公文與政策補強":
        requirements.extend([
            "依情境自然使用二至四組台灣公文或法律搭配，例如擬、研擬、擬具、擬辦、涉、涉及、涉嫌、涉案、嚴查、查辦、相關規定、相關資料；不得為湊詞而誤用。",
            "區分當事人主張、可確認紀錄、待調查事項與機關決定；不得捏造法條編號、期限、門檻或法律結論。",
        ])

    return {
        "id": f"tw-typing-v3-{sequence:03d}",
        "version": "v3",
        "era": era["era"],
        "recent_30_years": era["recent"],
        "category": category["category"],
        "title": title,
        "target_chars": mode["target_chars"],
        "accepted_char_range": mode["accepted_char_range"],
        "region": region,
        "content_mode": spec["mode"],
        "channel": channel,
        "output_form": output_form,
        "relationship": relationship,
        "activity": activity,
        "object": object_name,
        "complication": complication,
        "speech_act": speech_act,
        "tone": spec["tone"],
        "outcome": spec["outcome"],
        "connector_focus": spec["connector_focus"],
        "input_feature": spec["input_feature"],
        "named_entities": [],
        "scenario": f"以{era['era']}年的{region}為背景，讓{relationship}透過{channel}談{activity}。{complication}，需要{speech_act}。整體以{spec['tone']}的語氣呈現，結局保持為{spec['outcome']}。",
        "requirements": requirements,
        "language_requirements": ["使用台灣繁體中文與全形中文標點。", "用字須符合指定年代與媒介。", "人物必須有可辨識的說話差異。", "保留短句、省略、改口、反問、等待與不完整回覆。"],
        "avoid": ["不得重複 v2 常見固定開場與理性總結", "不得虛構真實私人個資", "不得捏造研究數字、法律條文、政策、產品規格、票價或營業時間", "不得把每一句都修成作文語氣", "不得讓所有衝突自動和解"],
        "evaluation": ["是否補到 v2 缺少的文字形態", "語氣是否與主題相稱", "短訊息是否真的短", "公文法律搭配是否自然", "混合字元是否符合真實輸入", "是否避免固定收尾"],
        "weight_class": "high",
    }


def assign_shopee(prompts: list[dict]) -> None:
    candidates = [
        prompt for prompt in prompts
        if prompt["category"] in {"消費住宿與交易補強", "數位生活與混合輸入補強"}
        and prompt["era"] in {"2010-2019", "2020-2026"}
    ]
    candidates.sort(key=lambda prompt: stable_index(f"{SEED}:shopee:{prompt['id']}", 1_000_003))
    for prompt in candidates[:8]:
        prompt["named_entities"].append("蝦皮購物")
        prompt["scenario"] += "內容自然使用「蝦皮購物」。"
        prompt["requirements"].append("自然使用「蝦皮購物」以及訂單、賣場、賣家、聊聊、客服、物流、超商取貨、退貨或退款中的相關搭配，不得每項都硬塞。")


def validate(prompts: list[dict]) -> None:
    if len(prompts) != 350:
        raise ValueError(f"expected 350 prompts, got {len(prompts)}")
    if len({item["id"] for item in prompts}) != len(prompts):
        raise ValueError("duplicate prompt id")
    if len({item["title"] for item in prompts}) != len(prompts):
        raise ValueError("duplicate title")
    expected_eras = {item["era"]: item["count"] for item in ERA_CONFIG}
    expected_categories = {item["category"]: item["count"] for item in CATEGORY_CONFIG}
    expected_modes = Counter()
    expected_tones = Counter()
    for category in CATEGORY_CONFIG:
        expected_modes.update(category["mode_counts"])
        expected_tones.update(category["tone_counts"])
    checks = [
        (Counter(item["era"] for item in prompts), Counter(expected_eras), "era"),
        (Counter(item["category"] for item in prompts), Counter(expected_categories), "category"),
        (Counter(item["content_mode"] for item in prompts), expected_modes, "content mode"),
        (Counter(item["tone"] for item in prompts), expected_tones, "tone"),
    ]
    for actual, expected, label in checks:
        if actual != expected:
            raise ValueError(f"{label} distribution mismatch: {actual} != {expected}")
    if sum(item["recent_30_years"] for item in prompts) != 245:
        raise ValueError("recent 30 years must be exactly 245 prompts")
    if Counter(item["connector_focus"] for item in prompts) != Counter(CONNECTOR_COUNTS):
        raise ValueError("connector distribution mismatch")
    actual_features = Counter(item["input_feature"] for item in prompts if item["input_feature"] != "無指定混合特徵")
    if actual_features != Counter(FEATURE_COUNTS):
        raise ValueError(f"feature distribution mismatch: {actual_features}")
    if sum("蝦皮購物" in item["named_entities"] for item in prompts) != 8:
        raise ValueError("expected exactly 8 Shopee prompts")
    for item in prompts:
        if item["era"] not in MODE_CONFIG[item["content_mode"]]["eligible_eras"]:
            raise ValueError(f"incompatible era/mode: {item['id']}")
        minimum_era = MIN_ERA_BY_ACTIVITY.get(item["activity"])
        if minimum_era and ERA_ORDER[item["era"]] < ERA_ORDER[minimum_era]:
            raise ValueError(f"anachronistic activity: {item['id']} / {item['activity']}")
        if not item["recent_30_years"] and item["region"] == "線上跨地區":
            raise ValueError(f"anachronistic region: {item['id']}")


def write_plan(stats: dict) -> None:
    lines = [
        "# AI 繁中輸入語料 v3：350 篇補強規劃",
        "",
        "v3 是獨立補強集，不修改 v2 的 10,000 題與現有 1,650 篇正文。設計依據為 `typing-articles-v2-attribute-report.md` 找出的缺口。",
        "",
        "## 主題配額",
        "",
        "| 主題 | 篇數 | 目的 |",
        "| --- | ---: | --- |",
        "| 工作討論與公事補強 | 70 | 補足目前約 35 篇缺口，並增加交接、事故、採購、帳款與跨部門文字 |",
        "| 法律公文與政策補強 | 70 | 增加擬、涉、嚴查、查辦、相關規定等自然搭配與正式文件 |",
        "| 情緒安慰與關係衝突補強 | 55 | 提高安慰、界線、拒絕、未回覆與未和解情境 |",
        "| 社群口語幽默與爭論補強 | 50 | 補幽默、反話、吐槽、爭論及自然台灣口語 |",
        "| 日常短訊息與協調補強 | 50 | 補真正會逐句輸入的短訊息、改期、報平安與臨時協調 |",
        "| 消費住宿與交易補強 | 30 | 補客服、訂單、退款、住宿、票券與蝦皮購物關聯 |",
        "| 數位生活與混合輸入補強 | 25 | 補搜尋、表單、檔名、網址、英文縮寫與數字 |",
        "",
        "## 年代配額",
        "",
        "| 年代 | 篇數 | 占比 |",
        "| --- | ---: | ---: |",
        *[f"| {era} | {count} | {count / 350:.1%} |" for era, count in stats["era_counts"].items()],
        "",
        "1997–2026 合計 245 篇，維持近 30 年正好 70%。",
        "",
        "## 與現有 1,650 篇合併後的預期效果",
        "",
        "若 350 篇全部生成並通過驗證，總數會成為 2,000 篇：",
        "",
        "- 近 30 年為 1,408 篇，占 70.4%，延續原本的 70% 設計。",
        "- 工作討論相關由 163 篇增至 233 篇，占 11.65%，已接近原訂 12%。",
        "- 正式文件媒介由 27 篇增至 102 篇，占 5.1%。",
        "- 國際旅行仍為 125 篇，占比由 7.58% 降至 6.25%，更接近完整規劃的 6.5%。",
        "- 新增 95 篇以短句為主的訊息包，改善原本長段落偏多的問題。",
        "",
        "## 文字形態配額",
        "",
        "| 形態 | 篇數 |",
        "| --- | ---: |",
        *[f"| {name} | {count} |" for name, count in stats["content_mode_counts"].items()],
        "",
        "短訊息包共有 95 篇，占 27.1%。每篇仍提供足夠的總字量，但改由大量短句、追問、改口與多人接話組成。正式文件 75 篇，直接補 v2 只有 27 篇正式媒介的缺口。",
        "",
        "## 語氣配額",
        "",
        "語氣改為依主題分配，不再把十種語氣平均灑到所有主題。",
        "",
        "| 語氣 | 篇數 | 占比 |",
        "| --- | ---: | ---: |",
        *[f"| {name} | {count} | {count / 350:.1%} |" for name, count in stats["tone_counts"].items()],
        "",
        "## 額外補強",
        "",
        "- 120 篇保持未解決或只部分解決，避免固定理性結尾。",
        "- 110 篇指定混合輸入特徵：日期時間 25、金額或編號 20、英文詞 25、網址或路徑 15、Emoji 15、注音語助詞 10。",
        "- 350 篇全部指定一組連接詞重點，平均補入「又／再／也」「和／與／以及」「但／不過／可是」「因為／所以／因此」「如果／除非／否則」的自然相鄰語境。",
        "- 8 篇明確要求自然使用「蝦皮購物」及訂單、賣場、賣家、聊聊、客服、物流、超商取貨、退貨或退款等搭配。",
        "- 法律公文類不得捏造法條與結論，並區分主張、紀錄、待查事項及正式決定。",
        "- 全部維持台灣繁體中文用語；v3 沒有中國繁中例外類別。",
        "",
    ]
    PLAN.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    specs = allocate_eras(assignment_specs())
    assign_connectors(specs)
    assign_features(specs)
    seen_titles: set[str] = set()
    seen_signatures: set[tuple] = set()
    prompts = [build_prompt(index, spec, seen_titles, seen_signatures) for index, spec in enumerate(specs, 1)]
    assign_shopee(prompts)
    validate(prompts)

    with OUTPUT.open("w", encoding="utf-8") as stream:
        for prompt in prompts:
            stream.write(json.dumps(prompt, ensure_ascii=False, separators=(",", ":")) + "\n")

    stats = {
        "version": "v3",
        "total": len(prompts),
        "recent_30_years": sum(item["recent_30_years"] for item in prompts),
        "recent_share": sum(item["recent_30_years"] for item in prompts) / len(prompts),
        "era_counts": dict(sorted(Counter(item["era"] for item in prompts).items())),
        "category_counts": dict(Counter(item["category"] for item in prompts).most_common()),
        "content_mode_counts": dict(Counter(item["content_mode"] for item in prompts).most_common()),
        "tone_counts": dict(Counter(item["tone"] for item in prompts).most_common()),
        "outcome_counts": dict(Counter(item["outcome"] for item in prompts).most_common()),
        "connector_counts": dict(Counter(item["connector_focus"] for item in prompts).most_common()),
        "input_feature_counts": dict(Counter(item["input_feature"] for item in prompts).most_common()),
        "channel_counts": dict(Counter(item["channel"] for item in prompts).most_common()),
        "shopee_prompt_count": sum("蝦皮購物" in item["named_entities"] for item in prompts),
        "unique_titles": len({item["title"] for item in prompts}),
        "unique_scenarios": len({item["scenario"] for item in prompts}),
    }
    STATS.write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_plan(stats)

    preview_indexes = []
    for category in CATEGORY_CONFIG:
        preview_indexes.append(next(index for index, item in enumerate(prompts) if item["category"] == category["category"]))
    for mode in MODE_CONFIG:
        preview_indexes.append(next(index for index, item in enumerate(prompts) if item["content_mode"] == mode))
    preview_indexes = list(dict.fromkeys(preview_indexes))
    lines = ["# Typing prompt v3 preview", "", "完整資料集為 `typing-prompts-v3.jsonl`。", ""]
    for index in preview_indexes:
        item = prompts[index]
        lines.extend([
            f"## {item['id']}｜{item['title']}", "",
            f"- 年代：{item['era']}", f"- 類別：{item['category']}", f"- 形態：{item['content_mode']}",
            f"- 管道：{item['channel']}", f"- 語氣：{item['tone']}", f"- 結果：{item['outcome']}",
            f"- 混合輸入：{item['input_feature']}", f"- 情境：{item['scenario']}", "- 必寫要求：",
            *[f"  - {value}" for value in item["requirements"]], "",
        ])
    PREVIEW.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

    print(f"wrote {len(prompts)} prompts to {OUTPUT}")
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == "__main__":
    main()
