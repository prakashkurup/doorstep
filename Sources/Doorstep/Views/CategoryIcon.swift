import AppKit

/// When an email has no product photo (Amazon now sends only a category, like
/// "Supplements"), a category glyph is quicker to recognize than a store letter.
enum CategoryIcon {
    private static let rules: [(pattern: String, symbol: String)] = [
        ("supplement|vitamin|protein", "pills"),
        ("health|medic|pharmacy|first aid|wellness", "cross.case"),
        ("household|cleaning|laundry|paper towel|trash bag", "bubbles.and.sparkles"),
        ("kitchen|dining|dinnerware|cookware|cutlery|drinkware", "fork.knife"),
        ("coffee|tea\\b", "cup.and.saucer"),
        ("grocery|food|snack|pantry|beverage", "carrot"),
        ("swim", "figure.pool.swim"),
        ("beauty|hair|skin|cosmetic|makeup|personal care|fragrance|grooming", "sparkles"),
        ("shoe|footwear|sneaker|boot", "shoe"),
        ("clothing|apparel|shirt|jacket|dress|pants|fashion|sock", "tshirt"),
        ("book|kindle", "book"),
        ("cable|charger|electronic|phone|headphone|audio|camera", "cable.connector"),
        ("computer|laptop|monitor|keyboard|mouse", "desktopcomputer"),
        ("toy|game", "gamecontroller"),
        ("pet|dog|cat", "pawprint"),
        ("baby|infant", "figure.and.child.holdinghands"),
        ("garden|outdoor|plant|patio|lawn", "leaf"),
        ("art|craft|paint|sewing", "paintbrush"),
        ("office|school|stationery|notebook", "pencil"),
        ("sport|fitness|exercise|yoga", "dumbbell"),
        ("tool|hardware|home improvement", "wrench.and.screwdriver"),
        ("furniture|home decor|bedding|bath", "sofa"),
        ("automotive|car ", "car"),
        ("gift", "gift"),
    ]

    static func symbol(for title: String) -> String? {
        let t = title.lowercased()
        for rule in rules where t.range(of: rule.pattern, options: .regularExpression) != nil {
            if NSImage(systemSymbolName: rule.symbol, accessibilityDescription: nil) != nil { return rule.symbol }
        }
        return nil
    }
}
