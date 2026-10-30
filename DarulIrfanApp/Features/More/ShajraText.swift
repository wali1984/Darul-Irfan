import Foundation

// The Shajra of Silsila Naqshbandia Owaisiah: the chain from the Holy
// Prophet ﷺ to the present Sheikh, each link's supplication line in Urdu
// with the website's English line for it, the two titles and the closing
// dua. Shown by ShajraView.
//
// GENERATED from parity-spec/redesign/shajra.json by a script that copies
// every string byte for byte. Never retype or "correct" any of it, and
// never add or drop a diacritic: ShajraTests pins the SHA-256 of each
// line. The Urdu was built letter by letter from the Silsila's own
// sources:
// - naqshbandiaowaisiah.org/assets/images/ShajrahAalia.jpg (the chart: Urdu wording)
// - Laiha-e-Amal, page 20 (book-ocr-laiha-e-amal): the same Shajra, the letters the lines are built from
// - naqshbandiaowaisiah.org/shajra-silsila-naqshbandia-owaisiah.html (English list)

/// One link of the Shajra.
struct ShajraEntry: Identifiable, Equatable, Sendable {
    /// Who the link is.
    enum Kind: String, Equatable, Sendable {
        /// The Holy Prophet ﷺ, at the head of the chain.
        case prophet
        /// A Sheikh of the chain, 1 to 11.
        case sheikh
        /// The present Sheikh, at its foot.
        case presentSheikh
    }

    /// Its place in the chain: 0 for the Holy Prophet ﷺ, 1 to 11 for the
    /// Sheikhs, 12 for the present Sheikh.
    let index: Int
    let kind: Kind
    /// The supplication line, as the Silsila's Shajra writes it.
    let urdu: String
    /// The website's English line for the same link.
    let english: String

    var id: Int { index }
}

/// The Shajra's words. They are content, shown with `Text(verbatim:)`,
/// never string catalogue keys.
enum ShajraText {
    /// The Urdu title, whole.
    static let titleUrdu = "شجرہ مبارک سلسلہ نقشبندیہ اویسیہ"
    /// The title's first two words (Shajra Mubarak): the header's gold line.
    static let titleUrduLead = "شجرہ مبارک"
    /// The rest of the title, the Silsila's name: the line under it.
    static let titleUrduSilsila = "سلسلہ نقشبندیہ اویسیہ"
    /// The English title.
    static let titleEnglish = "Shajra Silsila Naqshbandia Owaisiah"
    /// The Arabic dua that closes the Shajra.
    static let closingArabic = "وَصَلَّى اللّٰهُ تَعَالٰى عَلٰى حَبِيْبِهٖ مُحَمَّدٍ وَّآلِهٖ وَاَصْحَابِهٖ اَجْمَعِيْنَ بِرَحْمَتِكَ يَا اَرْحَمَ الرَّاحِمِيْنَ"

    /// The chain, from the Holy Prophet ﷺ to the present Sheikh.
    static let entries: [ShajraEntry] = [
        ShajraEntry(
            index: 0,
            kind: .prophet,
            urdu: "الٰہی بحرمت حضرت محمد رسول اللہ صلی اللہ علیہ وآلہٖ وسلم",
            english: "The Holy Prophet Muhammad (Sall Allah-o 'Alaihi wa Sallam)"
        ),
        ShajraEntry(
            index: 1,
            kind: .sheikh,
            urdu: "الٰہی بحرمت حضرت ابوبکر صدیق رضی اللہ تعالیٰ عنہ",
            english: "Hadhrat Abu Bakr Siddiq (Radhi Allah-o 'Unho, d. 13H)"
        ),
        ShajraEntry(
            index: 2,
            kind: .sheikh,
            urdu: "الٰہی بحرمت حضرت حسن بصری رحمۃ اللہ تعالیٰ علیہ",
            english: "Hadhrat Imam Hassan al Basri (Rahmat Allah 'Alaihi, d. 110H)"
        ),
        ShajraEntry(
            index: 3,
            kind: .sheikh,
            urdu: "الٰہی بحرمت حضرت داؤد طائی رحمۃ اللہ تعالیٰ علیہ",
            english: "Hadhrat Dawood Tai (Rahmat Allah 'Alaihi)"
        ),
        ShajraEntry(
            index: 4,
            kind: .sheikh,
            urdu: "الٰہی بحرمت حضرت جنید بغدادی رحمۃ اللہ تعالیٰ علیہ",
            english: "Hadhrat Junaid Baghdadi (Rahmat Allah 'Alaihi, d. 297 H)"
        ),
        ShajraEntry(
            index: 5,
            kind: .sheikh,
            urdu: "الٰہی بحرمت حضرت خواجہ عبید اللہ احرار رحمۃ اللہ تعالیٰ علیہ",
            english: "Hadhrat Obaid Ullah Ahrar (Rahmat Allah 'Alaihi, d. 895 H)"
        ),
        ShajraEntry(
            index: 6,
            kind: .sheikh,
            urdu: "الٰہی بحرمت حضرت مولانا عبدالرحمٰن جامی رحمۃ اللہ تعالیٰ علیہ",
            english: "Hadhrat Maulana Abdur Rahman Jami (Rahmat Allah 'Alaihi, d. 898 H)"
        ),
        ShajraEntry(
            index: 7,
            kind: .sheikh,
            urdu: "الٰہی بحرمت حضرت ابوایوب محمد صالح رحمۃ اللہ تعالیٰ علیہ",
            english: "Hadhrat Abul Ayub Muhammad Saleh (Rahmat Allah 'Alaihi, d. late 10 cent H)"
        ),
        ShajraEntry(
            index: 8,
            kind: .sheikh,
            urdu: "الٰہی بحرمت حضرت سلطان العارفین خواجہ اللہ دین مدنی رحمۃ اللہ تعالیٰ علیہ",
            english: "(Sultan ul-Arifeen) Hadhrat Allah Din Madni (Rahmat Allah 'Alaihi)"
        ),
        ShajraEntry(
            index: 9,
            kind: .sheikh,
            urdu: "الٰہی بحرمت حضرت مولانا عبدالرحیم رحمۃ اللہ تعالیٰ علیہ",
            english: "Hadhrat 'Abdul Rahim (Rahmat Allah 'Alaihi, d. 1372 H)"
        ),
        ShajraEntry(
            index: 10,
            kind: .sheikh,
            urdu: "الٰہی بحرمت قلزم فیوضات حضرت مولانا اللہ یار خان رحمۃ اللہ تعالیٰ علیہ",
            english: "Hadhrat Maulana Allah Yar Khan (Rahmat Allah 'Alaihi, d. 1404 H)"
        ),
        ShajraEntry(
            index: 11,
            kind: .sheikh,
            urdu: "الٰہی بحرمت قاسم فیوضات حضرت مولانا امیر محمد اکرم اعوان رحمۃ اللہ تعالیٰ علیہ",
            english: "Hadhrat Maulana Muhammad Akram Awan (Rahmat Allah 'Alaihi, d. 1439 H)"
        ),
        ShajraEntry(
            index: 12,
            kind: .presentSheikh,
            urdu: "الٰہی بحرمت ختم خواجگان خاتمہ من وخاتمہ حضرت امیر عبدالقدیر اعوان مدظلہ العالی بخیر گردان",
            english: "Hadhrat Ameer Abdul Qadeer Awan Present Sheikh of the Order."
        ),
    ]
}
