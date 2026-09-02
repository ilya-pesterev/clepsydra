import Foundation

/// Что показывать на экране между помидорами.
public enum QuoteMode: String, Equatable {
    case philosophers
    case statham
}

/// Реплика для режима Стетхема. Каждая строка — отдельная наклейка, поэтому
/// разбивка задана руками: ломать надо по шутке, а не по ширине экрана.
public struct StickerQuote: Equatable {
    public let lines: [String]

    public init(_ lines: [String]) {
        self.lines = lines
    }
}

public enum StathamQuotes {

    public static let all: [StickerQuote] = [
        StickerQuote(["Запомни: всего одна ошибка —", "и ты ошибся."]),
        StickerQuote(["Делай, как надо.", "Как не надо, не делай."]),
        StickerQuote(["Работа — это не волк.", "Работа — ворк.", "А волк — это ходить."]),
        StickerQuote(["Не будьте эгоистами,", "в первую очередь", "думайте о себе!"]),
        StickerQuote(["Мы должны оставаться мыми,", "а они — оними."]),
        StickerQuote(["Марианскую впадину знаешь?", "Это я упал."]),
        StickerQuote(["Как говорил мой дед,", "«Я твой дед»."]),
        StickerQuote(["Жи-ши пиши", "от души."]),
        StickerQuote(["Без подошвы тапочки —", "это просто тряпочки."]),
        StickerQuote(["Слово — не воробей.", "Вообще ничто не воробей,", "кроме самого воробья."]),
        StickerQuote(["Если тебе где-то не рады", "в рваных носках, то и в целых", "туда идти не стоит."]),
        StickerQuote(["Работа не волк.", "Никто не волк.", "Только волк волк."]),
        StickerQuote(["Если закрыть глаза,", "становится темно."]),
        StickerQuote(["Тут — это вам не там."]),
        StickerQuote(["В Риме был,", "а папы не видал."]),
        StickerQuote(["Кто рано встаёт —", "тому весь день спать хочется."]),
        StickerQuote(["Если ты смелый, ловкий", "и очень сексуальный —", "иди домой, ты пьян."])
    ]

    /// Случайная реплика, но не та же, что была на прошлом экране.
    public static func next(after previous: StickerQuote?) -> StickerQuote {
        let pool = all.filter { $0 != previous }
        return pool.randomElement() ?? all[0]
    }
}
