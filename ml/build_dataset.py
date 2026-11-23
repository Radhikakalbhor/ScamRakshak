"""Builds ml/data/hindi_hinglish.csv + ml/data/indian_english.csv from templates (combinatorics),
then does the FIRST stratified 80/20 split -> ml/data/train.csv (pre-augmentation) and ml/data/test.csv
(test also gets the hand-written messages from handwritten_test.py)."""
import os
import random
import re

import pandas as pd
from sklearn.model_selection import train_test_split

from handwritten_test import HANDWRITTEN
from preprocess import norm_key

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
R = random.Random(42)


def d(n):
    return "".join(R.choice("0123456789") for _ in range(n))


def amt():
    return R.choice(["499", "760", "1,250", "2,000", "3,450", "4,999", "5,000", "9,999", "12,500",
                     "15,000", "25,000", "49,000", "75,000", "1,00,000", "2,35,000", "350", "1200", "8000"])


SLOTS = {
    "bank": lambda: R.choice(["SBI", "HDFC Bank", "ICICI Bank", "PNB", "Axis Bank", "Bank of Baroda",
                              "Canara Bank", "Kotak", "Union Bank", "CG Gramin Bank", "Bank of India"]),
    "amt": amt, "bal": amt, "fee": lambda: R.choice(["99", "199", "499", "1,500", "2,999", "650", "10"]),
    "otp": lambda: d(6), "otp4": lambda: d(4), "acct": lambda: "XX" + d(4), "ref": lambda: d(12),
    "num": lambda: R.choice("6789") + d(9),
    "url": lambda: R.choice(["bit.ly/", "tinyurl.com/", "sbi-kyc-update.xyz/", "rewards-claim.top/",
                             "http://kyc-verify.in/", "https://bank-secure-login.site/", "cutt.ly/",
                             "http://indiapost-redelivery.live/", "electricity-bill-pay.online/",
                             "https://pmyojana-form.club/"]) + d(4),
    "gurl": lambda: R.choice(["amzn.in/d/", "fkrt.it/", "https://www.bluedart.com/track?n=",
                              "https://www.indiapost.gov.in/track/", "dtdc.in/t/", "myntr.in/"]) + d(5),
    "date": lambda: f"{R.randint(1, 28):02d}-{R.randint(1, 12):02d}-{R.choice(['2025', '2026'])}",
    "time": lambda: R.choice(["9:30", "10:00", "8:45", "11:15", "7:00"]),
    "courier": lambda: R.choice(["FedEx", "DHL", "Blue Dart", "India Post", "DTDC", "Delhivery", "Ekart"]),
    "merchant": lambda: R.choice(["Amazon", "Flipkart", "Swiggy", "Zomato", "BigBasket", "Meesho", "Myntra",
                                  "Reliance Digital", "Jio", "Airtel"]),
    "name": lambda: R.choice(["Rahul", "Sunita", "Ramesh", "Priya", "Anil", "Kavita", "Suresh", "Pooja",
                              "Manoj", "Rekha", "Deepak", "Meena", "Vikas", "Anjali"]),
    "city": lambda: R.choice(["Raipur", "Bilaspur", "Durg", "Bhilai", "Korba", "Delhi", "Nagpur", "Jagdalpur"]),
    "prize": lambda: R.choice(["iPhone 15", "Tata Safari", "25 lakh", "Honda Activa", "LED TV", "gold coin"]),
    "app": lambda: R.choice(["QuickCash", "RupeeNow", "InstaLoan", "CashKaro Loan", "EasyPaisa Loan", "LoanBazaar"]),
    "discom": lambda: R.choice(["CSPDCL", "MSEDCL", "BSES", "UPPCL", "MPEB", "TPDDL"]),
    "upi": lambda: R.choice(["refund.help", "cust.care", "rewards2", "loanpay", "cbi.case", "kyc.desk"])
                   + d(3) + R.choice(["@ybl", "@okaxis", "@paytm", "@oksbi"]),
    "case": lambda: R.choice(["CBI/", "MH/CR/", "ED/", "DL/CYB/"]) + d(4) + "/" + R.choice(["2025", "2026"]),
    "off": lambda: R.choice(["Inspector Sharma", "Officer Verma", "DCP Singh", "CBI officer Rathore",
                             "SI Yadav"]),
    "ord": lambda: R.choice(["OD", "#", "ORD"]) + d(8), "awb": lambda: d(11), "cons": lambda: d(10),
    "tf": lambda: "1800" + d(3) + d(4),
}


def fill(t):
    return re.sub(r"\{(\w+)\}", lambda m: SLOTS[m.group(1)](), t)


# ---------------------------------------------------------------- templates: (lang, label) -> cat -> list
T = {}

T[("hi", "scam")] = {
    "kyc": [
        "प्रिय ग्राहक, आपका {bank} खाता आज रात बंद हो जाएगा। तुरंत KYC अपडेट करें: {url}",
        "{bank} अलर्ट: आपका KYC अधूरा है, 24 घंटे में खाता ब्लॉक होगा। अभी लिंक खोलें {url}",
        "आपका पैन कार्ड खाते से लिंक नहीं है, आपकी {bank} नेटबैंकिंग बंद कर दी गई है। अपडेट करें {url}",
        "सूचना: आधार KYC न होने के कारण आपका खाता फ्रीज़ किया जा रहा है। तुरंत {num} पर कॉल करें",
        "आपका {bank} YONO खाता निलंबित कर दिया गया है। दोबारा चालू करने के लिए विवरण भरें {url}",
        "आपके सिम का KYC रद्द हो गया है, 2 घंटे में नंबर बंद होगा। तुरंत {num} पर कॉल करें",
    ],
    "otp": [
        "आपके खाते में गलती से ₹{amt} आ गए हैं, वापस करने के लिए फ़ोन पर आया OTP बताएं",
        "मैं {bank} से बोल रहा हूँ, आपका कार्ड चालू करने के लिए अभी आया 6 अंकों का कोड भेजें",
        "आपका ₹{amt} का कैशबैक अटका है, पाने के लिए OTP इस नंबर {num} पर व्हाट्सऐप करें",
        "रिवॉर्ड पॉइंट ₹{amt} आज खत्म हो रहे हैं। रिडीम करने के लिए OTP बताएं और लिंक खोलें {url}",
        "आपकी गैस सब्सिडी ₹{amt} रुकी हुई है। वेरिफ़िकेशन के लिए SMS में आया OTP हमें भेजें",
        "बेटा, मैंने गलती से तुम्हारे नंबर पर OTP भेज दिया, जल्दी बता दो प्लीज़",
    ],
    "arrest": [
        "यह CBI का नोटिस है। आपके आधार से जुड़े खाते में मनी लॉन्ड्रिंग पाई गई है। गिरफ्तारी से बचने के लिए तुरंत {num} पर संपर्क करें",
        "साइबर क्राइम पुलिस: आपके नंबर से गैरकानूनी काम हुआ है। आप डिजिटल अरेस्ट में हैं, वीडियो कॉल पर रहें और किसी को न बताएं",
        "मुंबई पुलिस: आपके नाम का ड्रग्स पार्सल पकड़ा गया है। केस नंबर {case}। जांच के लिए ₹{amt} सुरक्षा राशि जमा करें",
        "ED नोटिस: आपके खाते की जांच चल रही है। खाता सीज़ होने से बचाने के लिए सारा पैसा सरकारी खाते में ट्रांसफर करें",
        "{off} बोल रहा हूँ, आपके खिलाफ FIR दर्ज है। मामला निपटाने के लिए आज ही ₹{amt} भेजें वरना वारंट जारी होगा",
    ],
    "courier": [
        "{courier}: आपका पार्सल कस्टम में रोका गया है। ₹{amt} कस्टम शुल्क भरें वरना पार्सल लौट जाएगा {url}",
        "आपके पार्सल में अवैध सामान मिला है। {courier} कस्टमर केयर से बात करने के लिए {num} पर कॉल करें",
        "इंडिया पोस्ट: पता अधूरा होने के कारण आपकी डिलीवरी रुकी है। ₹{fee} देकर पता अपडेट करें {url}",
        "आपका विदेश से आया गिफ्ट पैकेट कस्टम विभाग में है। छुड़ाने के लिए ₹{amt} इस UPI {upi} पर भेजें",
        "{courier} डिलीवरी फेल हुई। दोबारा डिलीवरी के लिए 2 घंटे में लिंक पर भुगतान करें {url}",
    ],
    "loan": [
        "आपका ₹{amt} लोन बकाया है। आज पैसे नहीं भरे तो आपकी फोटो आपके सारे कॉन्टैक्ट्स को भेज देंगे",
        "{app} लोन: भुगतान नहीं किया तो तुम्हारे परिवार को बदनाम करेंगे। अभी {upi} पर ₹{amt} भेजो",
        "बिना कागज़ 5 मिनट में ₹{amt} लोन पाएं। प्रोसेसिंग फीस ₹{fee} भरें और ऐप डाउनलोड करें {url}",
        "अंतिम चेतावनी: लोन ऐप की किस्त ₹{amt} बाकी है। आज शाम तक नहीं भरी तो पुलिस केस होगा और फोटो वायरल होगी",
        "बधाई हो! आपका ₹{amt} का प्री-अप्रूव्ड लोन मंजूर है। पैसे पाने के लिए ₹{fee} फाइल चार्ज भेजें {num}",
    ],
    "lottery": [
        "बधाई हो! आपने KBC लॉटरी में ₹25 लाख जीते हैं। इनाम पाने के लिए {num} पर व्हाट्सऐप करें",
        "आपका मोबाइल नंबर लकी ड्रॉ में चुना गया है। {prize} जीतने के लिए ₹{fee} रजिस्ट्रेशन शुल्क भेजें",
        "जियो लकी ड्रॉ विजेता! आपका ₹{amt} इनाम तैयार है। प्रोसेसिंग फीस जमा करें {url}",
        "आपको {merchant} की तरफ से मुफ्त {prize} मिला है। अभी क्लेम करें, ऑफर सिर्फ आज तक {url}",
        "प्रधानमंत्री योजना के तहत आपको ₹{amt} मिलेंगे। फॉर्म भरें और ₹{fee} शुल्क दें {url}",
    ],
    "electricity": [
        "प्रिय उपभोक्ता, आपका पिछला बिजली बिल अपडेट नहीं हुआ है। आज रात {time} बजे बिजली काट दी जाएगी। तुरंत बिजली अधिकारी को {num} पर कॉल करें",
        "{discom}: बिल बकाया होने के कारण आपका कनेक्शन आज रात कटेगा। तुरंत भुगतान करें {url}",
        "बिजली विभाग: आपका मीटर अपडेट नहीं है। कनेक्शन बचाने के लिए यह ऐप डाउनलोड करें {url} और {num} पर बात करें",
        "आपका बिजली कनेक्शन 2 घंटे में बंद होगा। ₹{fee} जमा करके चालू रखें, संपर्क {num}",
    ],
    "upi": [
        "आपको ₹{amt} भेजने की रिक्वेस्ट भेजी है, पैसे पाने के लिए अपना UPI PIN डालें",
        "मैं OLX से खरीदार हूँ, एडवांस भेज रहा हूँ। जो रिक्वेस्ट आई है उसमें PIN डालकर अप्रूव करो",
        "₹{amt} रिफंड पाने के लिए {upi} से आई कलेक्ट रिक्वेस्ट स्वीकार करें और PIN डालें",
        "आर्मी से हूँ, आपका सामान खरीदना है। QR कोड भेजा है, स्कैन करके PIN डालो पैसे आ जाएंगे",
        "आपका कैशबैक ₹{amt} भेज दिया गया है, Google Pay में आई रिक्वेस्ट पर PIN डालकर पैसे लें",
    ],
}

T[("hi", "genuine")] = {
    "bank": [
        "{bank}: आपके खाते {acct} से ₹{amt} दिनांक {date} को डेबिट हुए। शेष राशि ₹{bal}। यदि आपने नहीं किया तो {tf} पर कॉल करें",
        "प्रिय ग्राहक, आपके खाते {acct} में ₹{amt} जमा किए गए हैं। संदर्भ {ref}। -{bank}",
        "आपके खाते {acct} से UPI द्वारा ₹{amt} {name} को भेजे गए। UPI Ref {ref} -{bank}",
        "वेतन ₹{amt} आपके खाते {acct} में जमा हो गया है। -{bank}",
        "{bank}: एटीएम से ₹{amt} निकाले गए, खाता {acct}, दिनांक {date}। शेष ₹{bal}",
    ],
    "otp": [
        "{otp} आपका OTP है ₹{amt} के लेनदेन के लिए। यह OTP किसी के साथ साझा न करें। बैंक कभी OTP नहीं मांगता। -{bank}",
        "{merchant} में लॉगिन के लिए आपका OTP {otp} है। 10 मिनट में समाप्त होगा। किसी को न बताएं।",
        "आपका सत्यापन कोड {otp} है। इसे किसी के साथ शेयर न करें, {bank} कर्मचारी भी इसे कभी नहीं मांगेंगे।",
        "डिजिलॉकर: आपका OTP {otp} है। यह 5 मिनट तक मान्य है। कृपया इसे किसी से साझा न करें।",
    ],
    "delivery": [
        "आपका {merchant} ऑर्डर {ord} आज डिलीवर होगा। सामान लेते समय डिलीवरी कोड {otp4} दिखाएं।",
        "{courier}: आपका शिपमेंट {awb} भेज दिया गया है। ट्रैक करें {gurl}",
        "आपका पार्सल {city} पहुंच गया है और कल तक डिलीवर हो जाएगा। - {courier}",
        "आपका {merchant} ऑर्डर डिलीवर हो गया है। खरीदारी के लिए धन्यवाद!",
        "आपका {merchant} रिफंड ₹{amt} आपके मूल भुगतान माध्यम में 5-7 दिन में आ जाएगा।",
    ],
    "bill": [
        "{discom}: उपभोक्ता क्रमांक {cons} का बिल ₹{amt} है, अंतिम तिथि {date}। आधिकारिक ऐप या वेबसाइट से भुगतान करें।",
        "आपके मोबाइल रिचार्ज की वैधता {date} को खत्म हो रही है। अपने ऐप से रिचार्ज करें। -{merchant}",
        "आपका बिजली बिल ₹{amt} सफलतापूर्वक जमा हुआ। रसीद क्रमांक {ref}। धन्यवाद - {discom}",
        "बीमा प्रीमियम ₹{amt} की देय तिथि {date} है। कृपया समय पर भुगतान करें।",
        "आपकी EMI ₹{amt} दिनांक {date} को खाते {acct} से कटेगी। कृपया पर्याप्त बैलेंस रखें। -{bank}",
    ],
    "personal": [
        "{name}, शाम को घर कब आओगे? खाना बना रही हूँ",
        "कल सुबह 10 बजे मीटिंग है, समय पर आ जाना {name}",
        "भैया, मैं {city} पहुंच गया हूँ, चिंता मत करना",
        "जन्मदिन की बहुत बहुत बधाई {name}! भगवान आपको खुश रखे",
        "माँ ने कहा है आज बाजार से सब्जी लेते आना",
        "बेटा, ₹{amt} भेज दिए हैं, मिल जाएं तो बता देना",
        "आज स्कूल की छुट्टी है, कल {city} में मिलते हैं",
        "डॉक्टर ने रिपोर्ट के लिए {date} को बुलाया है, साथ चलोगे?",
        "{name} की शादी का कार्ड आया है, अगले हफ्ते {city} जाना है",
    ],
}

T[("hinglish", "scam")] = {
    "kyc": [
        "Dear customer aapka {bank} account aaj raat block ho jayega. Turant KYC update kare {url}",
        "{bank} alert: aapka KYC pending hai, 24 ghante me account band hoga. Abhi link pe click karo {url}",
        "Aapka PAN card link nahi hai isliye aapki netbanking suspend kar di gayi hai. Update kare {url}",
        "Aadhaar KYC na hone ki wajah se aapka account freeze ho raha hai. Turant {num} pe call kare",
        "Aapka SIM KYC expire ho gaya hai, 2 ghante me number band ho jayega. Call karo {num}",
    ],
    "otp": [
        "Aapke account me galti se Rs {amt} aa gaye hai, wapas karne ke liye jo OTP aaya hai wo bata do",
        "Main {bank} se bol raha hu, aapka card activate karne ke liye abhi aaya 6 digit code bhejiye",
        "Aapka Rs {amt} cashback pending hai, OTP is number {num} pe WhatsApp karo",
        "Reward points Rs {amt} aaj expire ho rahe hai. Redeem karne ke liye OTP share kare {url}",
        "Bhai galti se tere number pe OTP chala gaya, jaldi bata de please",
        "Aapki gas subsidy Rs {amt} ruki hai, verification ke liye SMS wala OTP bhejo",
    ],
    "arrest": [
        "Ye CBI notice hai. Aapke Aadhaar se linked account me money laundering mili hai. Arrest se bachne ke liye {num} pe contact kare",
        "Cyber crime police: aapke number se illegal activity hui hai. Aap digital arrest me ho, video call pe raho aur kisi ko mat batao",
        "Mumbai police: aapke naam ka drugs parcel pakda gaya hai. Case no {case}. Jaanch ke liye Rs {amt} security deposit karo",
        "{off} bol raha hu, aapke khilaf FIR hai. Case settle karne ke liye aaj hi Rs {amt} bhejo warna warrant niklega",
        "ED notice: aapke account ki investigation chal rahi hai. Sara paisa safe government account me transfer karo",
    ],
    "courier": [
        "{courier}: aapka parcel customs me ruka hai. Rs {amt} customs fee bharo warna parcel return ho jayega {url}",
        "Aapke parcel me illegal saman mila hai. {courier} customer care se baat karne ke liye {num} pe call karo",
        "India Post: address incomplete hai isliye delivery ruki hai. Rs {fee} pay karke address update kare {url}",
        "Videsh se aaya gift packet customs me hai. Chhudane ke liye Rs {amt} is UPI {upi} pe bhejo",
        "{courier} delivery failed. Redelivery ke liye 2 ghante me payment karo {url}",
    ],
    "loan": [
        "Tera Rs {amt} loan due hai. Aaj paisa nahi bhara to teri photo sab contacts ko bhej denge",
        "{app} loan: payment nahi kiya to tumhari family ko badnaam karenge. Abhi {upi} pe Rs {amt} bhejo",
        "Bina document 5 minute me Rs {amt} loan pao. Processing fee Rs {fee} bharo aur app download karo {url}",
        "Last warning: loan app ki EMI Rs {amt} baaki hai. Aaj shaam tak nahi bhari to police case hoga aur photo viral karenge",
        "Congrats! Aapka Rs {amt} pre approved loan sanction ho gaya. Paisa lene ke liye Rs {fee} file charge bhejo {num}",
    ],
    "lottery": [
        "Badhai ho! Aapne KBC lottery me 25 lakh jeete hai. Inaam lene ke liye {num} pe WhatsApp karo",
        "Aapka mobile number lucky draw me select hua hai. {prize} jeetne ke liye Rs {fee} registration fee bhejo",
        "Jio lucky draw winner! Aapka Rs {amt} prize ready hai. Processing fee jama karo {url}",
        "Aapko {merchant} ki taraf se free {prize} mila hai. Abhi claim karo, offer sirf aaj tak {url}",
        "PM yojana ke tahat aapko Rs {amt} milenge. Form bharo aur Rs {fee} fee do {url}",
    ],
    "electricity": [
        "Dear consumer aapka pichla bijli bill update nahi hua. Aaj raat {time} baje light kaat di jayegi. Turant officer ko {num} pe call kare",
        "{discom}: bill due hone ki wajah se aapka connection aaj raat katega. Turant payment kare {url}",
        "Bijli vibhag: aapka meter update nahi hai. Connection bachane ke liye ye app download karo {url} aur {num} pe baat karo",
        "Aapka electricity connection 2 ghante me disconnect hoga. Rs {fee} jama karke chalu rakhe, contact {num}",
    ],
    "upi": [
        "Aapko Rs {amt} bhejne ki request bheji hai, paise receive karne ke liye apna UPI PIN daalo",
        "Main OLX se buyer hu, advance bhej raha hu. Jo request aayi hai usme PIN daal ke approve karo",
        "Rs {amt} refund lene ke liye {upi} se aayi collect request accept karo aur PIN daalo",
        "Army se hu, aapka saman lena hai. QR code bheja hai, scan karke PIN daalo paise aa jayenge",
        "Aapka cashback Rs {amt} bhej diya hai, GPay me aayi request pe PIN daal ke paise lo",
    ],
}

T[("hinglish", "genuine")] = {
    "bank": [
        "Rs {amt} aapke account {acct} me credit hua hai. Ref {ref} -{bank}",
        "Aapke a/c {acct} se Rs {amt} debit hue {date} ko. Agar aapne nahi kiya to {tf} pe call kare -{bank}",
        "Salary Rs {amt} aapke account {acct} me aa gayi hai -{bank}",
        "UPI se Rs {amt} {name} ko bheje gaye. Ref no {ref}. Bal Rs {bal}",
    ],
    "otp": [
        "{otp} aapka OTP hai Rs {amt} ke transaction ke liye. Kisi ke saath share na kare. Bank kabhi OTP nahi maangta -{bank}",
        "{merchant} login OTP {otp} hai. 10 min me expire hoga. Kisi ko mat batana",
        "Aapka verification code {otp} hai. Ise share na kare, {bank} staff bhi kabhi nahi maangega",
    ],
    "delivery": [
        "Aapka {merchant} order {ord} aaj deliver hoga. Saman lete waqt delivery code {otp4} dikhaye",
        "{courier}: aapka shipment {awb} dispatch ho gaya hai. Track kare {gurl}",
        "Aapka parcel {city} pahunch gaya hai, kal tak deliver ho jayega - {courier}",
        "Aapka {merchant} order deliver ho gaya. Shopping ke liye thank you!",
        "Aapka {merchant} refund Rs {amt} 5-7 din me original payment mode me aa jayega",
    ],
    "bill": [
        "{discom}: consumer no {cons} ka bill Rs {amt} hai, last date {date}. Official app ya website se pay kare",
        "Aapke recharge ki validity {date} ko khatam ho rahi hai. App se recharge kare -{merchant}",
        "Aapka bijli bill Rs {amt} successfully jama hua. Receipt no {ref} - {discom}",
        "Aapki EMI Rs {amt} {date} ko account {acct} se kategi. Balance maintain rakhe -{bank}",
        "LIC premium Rs {amt} ki due date {date} hai. Time pe pay kar dena",
    ],
    "personal": [
        "{name} shaam ko ghar kab aaoge? khana bana rahi hu",
        "Kal subah 10 baje meeting hai, time pe aa jana",
        "Bhaiya main {city} pahunch gaya, tension mat lena",
        "Happy birthday {name}! bhagwan tumhe hamesha khush rakhe",
        "Mummy bol rahi hai aate waqt sabzi le aana",
        "Beta Rs {amt} bhej diye hai, mil jaye to bata dena",
        "Aaj school ki chutti hai, kal {city} me milte hai",
        "Yaar {name} ki shaadi ka card aaya hai, next week {city} chalna hai",
        "Doctor ne report ke liye {date} ko bulaya hai, saath chaloge?",
        "Match dekh raha hai kya? kya mast khela {name} ne",
    ],
}

T[("en", "scam")] = {
    "kyc": [
        "Dear customer, your {bank} account will be blocked today. Update your KYC immediately: {url}",
        "{bank}: Your PAN is not linked. Netbanking suspended. Click {url} to reactivate",
        "Your account is temporarily frozen due to incomplete KYC. Call {num} now to avoid closure",
    ],
    "otp": [
        "Sir, Rs {amt} was credited to your account by mistake. Please share the OTP you received to reverse it",
        "This is {bank} card department. Tell me the 6 digit code sent to your mobile to activate your card",
        "Your reward points worth Rs {amt} expire today. Share OTP to redeem {url}",
    ],
    "arrest": [
        "CBI notice: money laundering found in your Aadhaar linked account. Contact {num} immediately to avoid arrest",
        "You are under digital arrest. Stay on video call and do not tell anyone. Case {case}",
        "{off} here. A parcel with drugs in your name was seized. Pay Rs {amt} security deposit for verification",
    ],
    "courier": [
        "{courier}: your parcel is held at customs. Pay Rs {amt} duty or it will be returned {url}",
        "India Post: your package could not be delivered due to incomplete address. Update for Rs {fee} {url}",
    ],
    "loan": [
        "Your loan of Rs {amt} is overdue. Pay now or your photos will be sent to all your contacts",
        "Instant loan Rs {amt} approved without documents. Pay processing fee Rs {fee} {url}",
    ],
    "lottery": [
        "Congratulations! Your number won Rs 25 lakh in KBC lucky draw. WhatsApp {num} to claim",
        "You have won a free {prize} from {merchant}. Claim now, offer valid today only {url}",
    ],
    "electricity": [
        "Dear consumer, your electricity power will be disconnected tonight at {time} because previous month bill was not updated. Contact officer {num}",
        "{discom}: your connection will be cut today due to unpaid bill. Pay immediately {url}",
    ],
    "upi": [
        "I have sent you a request of Rs {amt}. Enter your UPI PIN to receive the money",
        "To get your refund of Rs {amt}, approve the collect request from {upi} and enter PIN",
        "I am from army, want to buy your item. Scan the QR I sent and enter PIN to receive advance",
    ],
}

T[("en", "genuine")] = {
    "bank": [
        "{bank}: Rs {amt} debited from A/c {acct} on {date}. Avl Bal Rs {bal}. Not you? Call {tf}",
        "Rs {amt} credited to your A/c {acct} on {date}. Ref {ref} -{bank}",
        "Your salary of Rs {amt} has been credited to A/c {acct}. -{bank}",
        "Sent Rs {amt} to {name} via UPI from A/c {acct}. UPI Ref {ref}",
    ],
    "otp": [
        "{otp} is your OTP for transaction of Rs {amt}. Do not share it with anyone. Bank never asks for OTP. -{bank}",
        "Use OTP {otp} to log in to {merchant}. Valid for 10 minutes. Do not share this code with anyone.",
        "Your verification code is {otp}. {bank} will never call you to ask for this code.",
    ],
    "delivery": [
        "Your {merchant} order {ord} will be delivered today. Share delivery code {otp4} only at the doorstep",
        "{courier}: shipment {awb} has been dispatched. Track at {gurl}",
        "Your {merchant} order has been delivered. Thank you for shopping!",
        "Refund of Rs {amt} for your {merchant} order will reach your original payment method in 5-7 days",
    ],
    "bill": [
        "{discom}: bill of Rs {amt} for consumer no {cons} is due on {date}. Pay via official app or website",
        "Your mobile plan expires on {date}. Recharge via the {merchant} app",
        "Payment of Rs {amt} received for your electricity bill. Receipt {ref}. Thank you - {discom}",
        "EMI of Rs {amt} will be debited from A/c {acct} on {date}. Please maintain sufficient balance -{bank}",
    ],
}

PREFIX = {"hi": ["", "", "", "सूचना: ", "जरूरी: ", "प्रिय ग्राहक, "],
          "hinglish": ["", "", "", "Alert: ", "Urgent: ", "Hello, "],
          "en": ["", "", "", "Alert: ", "URGENT: ", "Dear user, "]}
SUFFIX = {"hi": ["", "", "", " धन्यवाद।", " जल्दी करें!", " -टीम"],
          "hinglish": ["", "", "", " Thanks", " jaldi karo!", " pls"],
          "en": ["", "", "", " Thank you.", " Act fast!", " Regards"]}
# genuine messages get neutral affixes only (no urgency words)
GPREFIX = {"hi": ["", "", "नमस्ते, "], "hinglish": ["", "", "Hi, "], "en": ["", "", "Hi, "]}
GSUFFIX = {"hi": ["", "", " धन्यवाद।"], "hinglish": ["", "", " thanks"], "en": ["", "", " Thank you."]}

PER_CAT = {("hi", "scam"): 55, ("hi", "genuine"): 90, ("hinglish", "scam"): 55, ("hinglish", "genuine"): 90,
           ("en", "scam"): 28, ("en", "genuine"): 55}


def generate():
    rows, seen = [], set()
    for (lang, label), cats in T.items():
        pre, suf = (PREFIX, SUFFIX) if label == "scam" else (GPREFIX, GSUFFIX)
        for cat, temps in cats.items():
            made, tries = 0, 0
            while made < PER_CAT[(lang, label)] and tries < 5000:
                tries += 1
                t = R.choice(temps)
                msg = (R.choice(pre[lang]) + fill(t) + R.choice(suf[lang])).strip()
                k = norm_key(msg)
                if k in seen:
                    continue
                seen.add(k)
                rows.append({"text": msg, "label": label, "lang": lang, "category": cat, "source": "template"})
                made += 1
    return pd.DataFrame(rows)


def main():
    gen = generate()
    hh = gen[gen.lang.isin(["hi", "hinglish"])]
    hh[["text", "label", "lang", "category"]].to_csv(os.path.join(DATA, "hindi_hinglish.csv"), index=False,
                                                    encoding="utf-8")
    gen[gen.lang == "en"][["text", "label", "lang", "category"]].to_csv(
        os.path.join(DATA, "indian_english.csv"), index=False, encoding="utf-8")

    uci = pd.read_csv(os.path.join(DATA, "raw", "SMSSpamCollection"), sep="\t", header=None,
                      names=["label", "text"], quoting=3, encoding="utf-8")
    uci["label"] = uci.label.map({"spam": "scam", "ham": "genuine"})
    uci["lang"], uci["category"], uci["source"] = "en", "uci", "uci"

    pool = pd.concat([uci[gen.columns], gen], ignore_index=True)
    pool["key"] = pool.text.map(norm_key)
    pool = pool[pool.key != ""].drop_duplicates("key").reset_index(drop=True)

    # FIRST split (stratified by label+lang), before any augmentation
    strat = pool.label + "_" + pool.lang
    train, test = train_test_split(pool, test_size=0.2, stratify=strat, random_state=42)

    hw = pd.DataFrame(HANDWRITTEN, columns=["text", "label", "lang"])
    hw["category"], hw["source"] = "handwritten", "handwritten"
    hw["key"] = hw.text.map(norm_key)
    test = pd.concat([test, hw], ignore_index=True).drop_duplicates("key")
    train = train[~train.key.isin(set(test.key))]

    cols = ["text", "label", "lang", "category", "source"]
    train[cols].to_csv(os.path.join(DATA, "train.csv"), index=False, encoding="utf-8")
    test[cols].to_csv(os.path.join(DATA, "test.csv"), index=False, encoding="utf-8")
    print("hindi_hinglish:", hh.groupby(["lang", "label"]).size().to_dict())
    print("indian_english:", gen[gen.lang == "en"].label.value_counts().to_dict())
    print("train:", len(train), train.groupby(["lang", "label"]).size().to_dict())
    print("test:", len(test), test.groupby(["lang", "label"]).size().to_dict(), "handwritten:", len(hw))


if __name__ == "__main__":
    main()
