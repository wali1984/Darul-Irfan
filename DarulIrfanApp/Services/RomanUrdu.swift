import Foundation

/// Urdu spellings of words people type in Roman Urdu ("namaz", "tauba"), so a
/// search finds the Urdu works as well as the English ones. Covers the
/// religious and silsila vocabulary the library and bayans use; a word that
/// is not here is searched as typed.
enum RomanUrdu {
    /// The Urdu spellings for one typed word, empty when it is not known.
    static func spellings(for term: String) -> [String] {
        let key = term.lowercased()
            .folding(options: [.diacriticInsensitive], locale: nil)
            .filter { $0.isLetter }
        return lexicon[key] ?? []
    }

    private static let lexicon: [String: [String]] = {
        var map: [String: [String]] = [:]
        for (romans, urdu) in entries {
            for roman in romans.split(separator: " ") { map[String(roman), default: []] += urdu }
        }
        return map
    }()

    /// Space-separated Roman spellings -> Urdu spellings.
    private static let entries: [(String, [String])] = [
        ("allah", ["اللہ"]),
        ("namaz namaaz nimaz salah salat salaat", ["نماز", "صلوٰۃ"]),
        ("zikr zikar dhikr zikrullah", ["ذکر"]),
        ("sabr sabar", ["صبر"]),
        ("shukr shukar", ["شکر"]),
        ("tauba tawba tobah tawbah taubah", ["توبہ"]),
        ("dua duaa doa", ["دعا"]),
        ("tawakkul tawakul", ["توکل"]),
        ("quran quraan koran", ["قرآن"]),
        ("hadees hadis hadith ahadees ahadith", ["حدیث", "احادیث"]),
        ("tafseer tafsir", ["تفسیر"]),
        ("roza roze rozah sawm", ["روزہ", "روزے"]),
        ("zakat zakaat", ["زکوٰۃ"]),
        ("hajj haj", ["حج"]),
        ("rasool rasul", ["رسول"]),
        ("nabi", ["نبی"]),
        ("ishq", ["عشق"]),
        ("mohabbat muhabbat", ["محبت"]),
        ("iman imaan emaan eeman", ["ایمان"]),
        ("ihsan ehsan", ["احسان"]),
        ("taqwa", ["تقویٰ"]),
        ("tasawwuf tasawuf tasawof", ["تصوف"]),
        ("tazkiya tazkiyah tazkia", ["تزکیہ"]),
        ("bayan bayaan", ["بیان"]),
        ("sheikh shaikh shaykh", ["شیخ"]),
        ("baiat bayat bait bayah", ["بیعت"]),
        ("silsila silsilah", ["سلسلہ"]),
        ("murshid", ["مرشد"]),
        ("muraqaba muraqabah muraqbah", ["مراقبہ"]),
        ("lataif lataaif", ["لطائف"]),
        ("qalb", ["قلب"]),
        ("rooh ruh", ["روح"]),
        ("nafs", ["نفس"]),
        ("jannat jannah", ["جنت"]),
        ("jahannam dozakh", ["جہنم", "دوزخ"]),
        ("akhirat aakhirat akhirah", ["آخرت"]),
        ("maut", ["موت"]),
        ("qabr", ["قبر"]),
        ("ilm", ["علم"]),
        ("rahmat rehmat rahmah", ["رحمت"]),
        ("maghfirat", ["مغفرت"]),
        ("istighfar istaghfar", ["استغفار"]),
        ("darood durood drood durud", ["درود"]),
        ("masjid", ["مسجد"]),
        ("ramzan ramazan ramadan", ["رمضان"]),
        ("eid", ["عید"]),
        ("fajr fajar", ["فجر"]),
        ("zuhr zohar zuhar", ["ظہر"]),
        ("asr", ["عصر"]),
        ("maghrib", ["مغرب"]),
        ("isha esha", ["عشاء"]),
        ("tahajjud tahajud", ["تہجد"]),
        ("owaisi owaisia owaisiah awaisi", ["اویسیہ", "اویسی"]),
        ("naqshbandi naqshbandia naqshbandiah", ["نقشبندیہ", "نقشبندی"]),
        ("hazrat", ["حضرت"]),
        ("sahaba sahabah", ["صحابہ"]),
        ("aulia auliya awliya", ["اولیاء"]),
        ("wali", ["ولی"]),
        ("karamat", ["کرامات"]),
        ("fana", ["فنا"]),
        ("baqa", ["بقا"]),
        ("marifat maarifat marifah", ["معرفت"]),
        ("irfan", ["عرفان"]),
        ("sohbat suhbat", ["صحبت"]),
        ("adab", ["ادب"]),
        ("akhlaq ikhlaq", ["اخلاق"]),
        ("ikhlas", ["اخلاص"]),
        ("niyat niyyat", ["نیت"]),
        ("walidain waldain", ["والدین"]),
        ("aulad", ["اولاد"]),
        ("nikah", ["نکاح"]),
        ("sadqa sadaqa sadaqah", ["صدقہ"]),
        ("qurbani", ["قربانی"]),
        ("hidayat hidaya hidayah", ["ہدایت"]),
        ("taqdeer taqdir", ["تقدیر"]),
        ("qurb", ["قرب"]),
        ("tauheed tawheed tawhid tohid", ["توحید"]),
        ("shirk", ["شرک"]),
        ("sunnat sunnah", ["سنت"]),
        ("seerat seerah sirat", ["سیرت"]),
        ("jihad", ["جہاد"]),
        ("ummat ummah", ["امت"]),
        ("deen din", ["دین"]),
        ("islam", ["اسلام"]),
        ("kalima kalimah", ["کلمہ"]),
        ("wazifa wazeefa", ["وظیفہ"]),
        ("tasbeeh tasbih", ["تسبیح"]),
        ("khanqah", ["خانقاہ"]),
        ("dars", ["درس"]),
        ("mehfil mahfil", ["محفل"]),
        ("ijtima ijtema", ["اجتماع"]),
        ("dawat dawah daawat", ["دعوت"]),
        ("tabligh tableegh", ["تبلیغ"]),
    ]
}
