import Foundation
import Testing
@testable import Doorstep

@Suite struct ProductImageTests {
    @Test func picksCatalogPhotoOverLogoAndPixel() {
        let html = """
        <img src="https://i5.walmartimages.com/dfw/logo/walmart-logo.png" width="120" height="40" alt="Walmart">
        <img src="https://track.walmart.com/open?id=abc" width="1" height="1">
        <img src="https://i5.walmartimages.com/asr/abc123.jpeg?odnHeight=180&amp;odnWidth=180" width="90" height="90" alt="Swanson Celery Seed Extract 500 mg">
        <img src="https://www.facebook.com/icon.png" width="24" height="24" alt="Facebook">
        """
        #expect(ProductImage.best(in: html, itemNames: ["Swanson Celery Seed Extract"])
                == "https://i5.walmartimages.com/asr/abc123.jpeg?odnHeight=180&odnWidth=180")
    }

    @Test func altTextMatchOnUnknownHost() {
        let html = """
        <img src="https://brand.example.com/images/header.jpg" width="600" height="120" alt="">
        <img src="https://brand.example.com/p/rain-jacket.jpg" width="100" height="100" alt="Men's Watertight II Rain Jacket">
        """
        #expect(ProductImage.best(in: html, itemNames: ["Men’s Watertight II Rain Jacket"]) == "https://brand.example.com/p/rain-jacket.jpg")
    }

    @Test func noEvidenceNoImage() {
        // Amazon-style: only logos and progress glyphs.
        let html = """
        <img src="https://m.media-amazon.com/images/G/01/outbound/logo.png" alt="Amazon logo">
        <img src="https://m.media-amazon.com/images/G/01/outbound/completed.png" alt="Completed">
        <img src="https://m.media-amazon.com/images/G/01/outbound/shipped.gif" alt="amazon-order-shipped-gif">
        """
        #expect(ProductImage.best(in: html, itemNames: ["Supplements"]) == nil)
    }

    @Test func amazonCatalogImage() {
        let html = """
        <img src="https://m.media-amazon.com/images/I/71abcXYZ._SS160_.jpg" style="width:80px;height:80px" alt="">
        """
        #expect(ProductImage.best(in: html, itemNames: ["Household Supplies"]) == "https://m.media-amazon.com/images/I/71abcXYZ._SS160_.jpg")
    }
}

@Suite struct CategoryIconTests {
    @Test func amazonCategories() {
        #expect(CategoryIcon.symbol(for: "Supplements") == "pills")
        #expect(CategoryIcon.symbol(for: "Household Supplies") == "bubbles.and.sparkles")
        #expect(CategoryIcon.symbol(for: "3 items · Swimwear, Hair Care") == "figure.pool.swim")
        #expect(CategoryIcon.symbol(for: "Package from Costco") == nil)
    }
}

@Suite struct DomainTests {
    @Test func senderDomains() {
        #expect(Heuristics.registrableDomain(of: "shipment-tracking@amazon.com") == "amazon.com")
        #expect(Heuristics.registrableDomain(of: "orders@email.columbia.com") == "columbia.com")
        #expect(Heuristics.registrableDomain(of: "columbia@narvar.com") == nil)
    }

    @Test func merchantGuesses() {
        #expect(Heuristics.guessDomain(forMerchant: "Costco") == "costco.com")
        #expect(Heuristics.guessDomain(forMerchant: "Columbia Sportswear") == "columbia.com")
        #expect(Heuristics.guessDomain(forMerchant: "Macys") == "macys.com")
    }
}
